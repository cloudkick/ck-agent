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
local socket = require 'socket'
local helen = require 'helen'
local util = require 'util'
local Check = util.Check

local metric_types = {
                        uptime_in_seconds = Check.enum.uint66,
                        connected_clients = Check.enum.uint64,
                        connected_slaves = Check.enum.uint64,
                        blocked_clients = Check.enum.uint64,
                        used_memory = Check.enum.uint64, -- in bytes
                        bgsave_in_progress = Check.enum.uint64,
                        changes_since_last_save = Check.enum.uint64,
                        bgrewriteaof_in_progress = Check.enum.uint64,
                        total_connections_received = Check.enum.gauge,
                        total_commands_processed = Check.enum.gauge,
                        expired_key = Check.enum.gauge,
                        pubsub_channels = Check.enum.uint64,
                        pubsub_patterns = Check.enum.uint64
                      }

local function get_stats(rcheck, host, port, password)
  local s, status, partial
  local ip, _ = socket.dns.toip(host)

  if not ip then
    rcheck:set_error('Failed resolving hostname to IP address')
    return rcheck
  end

  local func = socket.protect(function()
    local sock, err = socket.connect(ip, port)
    local try = socket.newtry(function() sock:close() end)

    if not sock then
      rcheck:set_error('Unable to connect to the redis server')
      return rcheck
    end

    sock:settimeout(5)
    if password then
      try(sock:send('AUTH ' .. password .. '\r\n'))
      s, status, partial = sock:receive('*a')

      if not partial then
        error()
      end

      if not string.find(partial:lower(), 'ok') then
        rcheck:set_error('Could not authenticate. Invalid password?')
        return rcheck
      end
    end

    try(sock:send('INFO\r\n'))
    s, status, partial = sock:receive('*a')

    if not s and not partial then
      error()
    end

    if string.find(partial:lower(), 'operation not permitted') then
      rcheck:set_error('Could not authenticate. Missing password?')
    end

    for _, line in ipairs(util.split(partial, '[^\n]+')) do repeat
      local split = util.split(line, '[^:]+')

      if not split then
        break
      end

      local metric, value = split[1], split[2]

      if not (util.table.contains(metric_types, metric, 'key')) then
        break
      end

      rcheck:add_metric(metric, tonumber(value), metric_types[metric])
    until true end

    sock:close()
  end)

  local rv = pcall(func)

  if not rv then
    rcheck:set_error('Failed parsing server response')
  else
    rcheck:set_status('tracking %d metrics', #rcheck['checks'])
  end

  return rcheck
end

function run(rcheck, args)
  local hostname, port
  local password = nil

  if not args.host then
    host = '127.0.0.1'
  else
    host = args.host[1]
  end

  if not args.port then
    port = 6379
  else
    port = tonumber(args.port[1])
  end

  if args.password then
    password = args.password[1]
  end

  rcheck = get_stats(rcheck, host, port, password)

  return rcheck
end
