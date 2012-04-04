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
local util = require 'util'
local Check = util.Check
local log = util.log
local nicesize = util.nicesize
local io = require 'io'

local function readstats(args)
  local mctypes = {uptime=Check.enum.gauge,
    time="skip",
    version=Check.enum.string,
    pointer_size="skip",
    rusage_user="skip",
    rusage_system="skip",
    total_items=Check.enum.gauge,
    total_connections=Check.enum.gauge,
    cmd_flush=Check.enum.gauge,
    cmd_get=Check.enum.gauge,
    cmd_set=Check.enum.gauge,
    get_hits=Check.enum.gauge,
    get_misses=Check.enum.gauge,
    get_misses=Check.enum.gauge,
    evictions=Check.enum.gauge,
    bytes_read=Check.enum.gauge,
    bytes_written=Check.enum.gauge}

  local client_skt,err = socket.connect(args.ipaddress, args.port)
  local r = {}
  if client_skt then
    client_skt:send("stats\n")
    while client_skt ~= nil do
      local line, err, partial = client_skt:receive('*l')
      if not line and err then
        log.crit('Error from memcache. err=%s', err)
        error(err)
      end
      local l = util.split(line)
      local cmd = l[1]

      if cmd == "END" then
        return r
      end
      if cmd == "ERROR" then
        error(line)
      end
      local t = mctypes[l[2]]
      if t == nil then
        t = Check.enum.uint64
      end
      if t ~= "skip" then
        r[l[2]] = {l[3], t}
      end
    end
  else
    log.crit("Unable to connect to memcached on %s: %s", args.ipaddress, err)
    error(err)
  end
  return r
end

local function getvalue(args)
  a = readstats(args)
  return a
end

function run(rcheck, args)

  if args.ipaddress == nil then
    args.ipaddress = '127.0.0.1'
  else
    args.ipaddress = args.ipaddress[1]
  end

  if args.port == nil then
    args.port = '11211'
  else
    args.port = args.port[1]
  end

  local rv, r = pcall(getvalue, args)
  print(rv, r)
  if rv then
    for k,v in pairs(r) do
      rcheck:add_metric(k, v[1], v[2])
    end
    rcheck:set_status('')
  else
    rcheck:set_error('failed to connect to %s:%s', args.ipaddress, args.port)
    log.err("memcache failed err: %s", tostring(r))
  end
  return rcheck
end
