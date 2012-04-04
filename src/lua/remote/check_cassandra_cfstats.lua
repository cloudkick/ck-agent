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

local ints = {["Space used (live)"]=1, ["Space used (total)"]=1, ["Read Latency"]=1,
              ["Write Latency"]=1, ["Row cache"]=1, ["Pending Tasks"]=1,
              ["Key cache hit rate"]=1,  ["Key cache capacity"]=1, ["Key cache size"]=1,
              ["Row cache hit rate"]=1,  ["Row cache capacity"]=1, ["Row cache size"]=1,
              ["Memtable Data Size"]=1, ["Compacted row minimum size"]=1, ["Compacted row maximum size"]=1,
              ["Compacted row mean size"]=1}

local rid_suffix = {["Read Latency"]=" ms.",  ["Write Latency"]=" ms."}

local function getvalue(path, args)
  local r = {}
  local c = nil
  local i = 0
  local name, num
  stream = io.popen(path .. ' 2>&1')
  local lines = stream:lines()
  for line in lines do

    if cassandra.failed_connecting(line) then
      return r, i, true
    end

    i = i + 1
    if i > 1 then
      line = string.gsub(line, '^[%s]+', '')
      local l = util.split(line, "[^:]+")
      name = l[1]
      if name == "Column Family" then
        -- print("starting new CF")
        -- for i,v in ipairs(l) do print(i,v) end
        l[2] = string.gsub(l[2], '^[%s]+', '')
        r[l[2]] = {}
        c = r[l[2]]
      else
        if c ~= nil  and name ~= nil then
          if rid_suffix[name] then
            l[2] = string.gsub(l[2], " ms.", "")
          end
          num = tonumber(l[2])
          if num == nil then
            table.insert(c, {name, l[2], Check.enum.string})
          else
            if ints[name] ~= nil then
              table.insert(c, {name, tonumber(l[2]), Check.enum.int64})
            else
              table.insert(c, {name, tonumber(l[2]), Check.enum.gauge})
            end
          end
        end
      end
    end
  end
  i = (i - 1) * 3
  return r, i
end

function run(rcheck, args)
  -- Normalize the path
  args.path = args.path[1]
  args.cf = args.cf[1]

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
  local realized_path = string.format("%s -host %s -port %s cfstats",
      nt_path, host, port)

  if not util.file_exists(nt_path) then
    rcheck:set_error("Unable to run nodetool: \"%s\" not found.", nt_path)
    return rcheck
  end

  local rv, r, i, failed_connecting = pcall(getvalue, realized_path, args)
  if rv then
    -- There has got to be a better way
    if i > 0 then
      if r[args.cf] == nil then
        rcheck:set_error("Unable to find column family \"%s\"", args.cf)
        return rcheck
      end
      for k,v in pairs(r[args.cf]) do
        rcheck:add_metric(v[1], v[2], v[3])
      end
      rcheck:set_status('Tracking column family \"%s\"', args.cf)
    else
      if failed_connecting then
        rcheck:set_error("Unable to connect to the remote JMX agent (invalid hostname or port?)", nt_path)
      else
        rcheck:set_error("Parsing nodetool response failed")
      end
    end
  else
    log.err("cassandra column family check failed: %s", r)
    rcheck:set_error("%s", r)
  end
  return rcheck
end
