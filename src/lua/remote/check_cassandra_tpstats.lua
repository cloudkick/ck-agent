--                                                                                                                                                                            --  Copyright 2012 Rackspace
--
--  Licensed under the Apache License, Version 2.0 (the "License");
--  you may not use this file except in compliance with the License.
--  You may obtain a copy of the License at
--
--      http://www.apache.org/licenses/LICENSE-2.0
--
--  Unless required by applicable law or agreed to in writing, software
--  distributed under the License is distributed on an "AS IS" BASIS,
--  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
--  See the License for the specific language governing permissions and
--  limitations under the License.
--


module(..., package.seeall);
local alien = require 'alien'
local util = require 'util'
local Check = util.Check
local log = util.log
local io = require 'io'
local cassandra = require 'cassandra'

local function getvalue(path, args)
  local r = {}
  local i = 0
  local pending = 0
  stream, error = io.popen(path .. ' 2>&1')
  local lines = stream:lines()

  for line in lines do
    if cassandra.failed_connecting(line) then
      return r, i, pending, true
    end

    i = i + 1
    if i > 1 then
      local l = util.split(line)
      n = tonumber(l[2])
      if n ~= nil then
        pending = pending + n
        table.insert(r, {l[1].."_active", l[2], Check.enum.uint32})
        table.insert(r, {l[1].."_pending", l[3], Check.enum.uint32})
        table.insert(r, {l[1].."_completed", l[4], Check.enum.gauge})
        if # l > 4 then
          -- We're on cass 0.8+, parse new stuff
          table.insert(r, {l[1].."_blocked", l[5], Check.enum.uint32})
          table.insert(r, {l[1].."_all_time_blocked", l[6], Check.enum.gauge})
        end
      end
    end
  end
  return r, i, pending
end

function run(rcheck, args)
  -- Normalize the path
  args.path = args.path[1]

  if args.host then
    host = args.host[1]
  else
    host = '127.0.0.1'
  end
  if args.port then
    port = args.port[1]
  else
    port = "8080"
  end

  if args.path == nil then
    args.path = '/'
  end

  args.path = util.normalize_path(args.path)

  local nt_path = string.format("%sbin/nodetool", args.path)
  local realized_path = string.format("%s -host %s -port %s tpstats",
      nt_path, host, port)

  log.dbg("Path to binary is %s", tostring(nt_path))
  log.dbg("Full command is %s", tostring(realized_path))

  if not util.file_exists(nt_path) then
    rcheck:set_error("Unable to run nodetool: \"%s\" not found.", nt_path)
    return rcheck
  end

  local rv, r, i, pending, failed_connecting = pcall(getvalue, realized_path, args)
  if rv then
    -- There has got to be a better way
    log.dbg("processed %s lines, found %s metrics", tostring(i), tostring(# r))
    if i > 0 then
      for k,v in pairs(r) do
        rcheck:add_metric(v[1], v[2], v[3])
      end
      rcheck:set_status('Total pending tasks: %d', pending)
    else
      if failed_connecting then
        rcheck:set_error("Unable to connect to the remote JMX agent (invalid hostname or port?)", nt_path)
      else
        rcheck:set_error("Parsing nodetool response failed")
      end
    end
  else
    log.err("cassandra check failed: %s", r)
    rcheck:set_error("%s", r)
  end
  return rcheck
end
