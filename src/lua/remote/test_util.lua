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
local lanes = require 'lanes'
local util = require 'util'

local buffer = alien.buffer(1024)
local getcwd = alien.default.getcwd
local error_msg = alien.buffer()

getcwd:types('string', 'string', 'int')
buffer = getcwd(error_msg, 1024)

local cwd = tostring(buffer)
local local_plugins_path_default = cwd .. '/tests/'
local munin_plugins_path_default = cwd .. '/tests/'

local function get_conf_object(local_plugins_path, munin_plugins_path)
  local local_plugins_path = local_plugins_path or local_plugins_path_default
  local munin_plugins_path = munin_plugins_path or munin_plugins_path_default

  local conf = {}
  conf.local_plugins_path = local_plugins_path
  conf.munin_plugins_path = munin_plugins_path

  return conf
end

function get_check_module(check_name, local_plugins_path, munin_plugins_path)
  local rv, check = pcall(require, check_name)

  if rv then
    check.conf = get_conf_object(local_plugins_path, munin_plugins_path)
  end

  return rv, check
end

local function _run_test_tcp_server(ip, port, timeout, mode, mappings)
  local ip = ip or '*'
  local timeout = timeout or .01
  local mode = mode or 'line'
  local mappings = mappings or {}

  local func = lanes.gen({ cancelstep = true}, function()
    local client, line, err, command, response
    socket = require 'socket'
    local server = assert(socket.bind(ip, port))

    local parse_line = function(line, client)
      line = util.trim(line)

      if util.table.contains(mappings, line, 'key') then
        response = mappings[line]
        client:send(response)

        return true
      end

      return false
    end

    while true do
      local client = server:accept()
      local buffer = ''
      local match = false
      client:settimeout(timeout)

      line, err = client:receive('*l')

      while line do
        if mode == 'line' then
          if not err then
            if parse_line(line, client) then
              -- Match found, close the connection
              client:close()
            end
          else
            client:close()
          end
        end

        buffer = buffer .. line .. '\n'
        line, err = client:receive('*l')
      end

      if mode == 'line' then
        client:close()
      elseif mode == 'http' then
        local buffer_lower = buffer:lower()

        for key,value in pairs(mappings) do
          local match_pattern =  value['match_pattern']:lower()

          if string.find(buffer_lower, match_pattern) ~= nil then
            match = true
            local response = value['response']
            local response_len = string.len(response)
            local header = 'HTTP/1.1 ' .. value['status_line'] .. '\n' ..
                           'Content-type: ' .. value['content_type'] .. '\n' ..
                           'Content-Length: ' .. response_len .. '\n\n'

            client:send(header .. response)
            break
          end
        end
      end

      if not match then
        client:send('HTTP/1.1 404 Not found\n\n')
      end

      client:close()
    end
  end)

  local lane = func()

  -- Wait until the lane is running
  while lane.status ~= 'running' do
  end

  return lane
end

function run_test_http_server(ip, port, timeout, routes)
  local content

  for key,value in pairs(routes) do
    if value['file'] ~= nil then
      local path = cwd ..  '/tests/' .. value['file']
      local file = assert(io.open(path, 'r'))
      content = file:read('*a')
      file:close()
    else
      content = value['response']
    end

    routes[key] = { ['match_pattern'] = value['method']:upper() .. ' ' .. key,
                    ['status_line'] = value['status_line'],
                    ['content_type'] = value['content_type'],
                    ['response'] = content }
  end

  return _run_test_tcp_server(ip, port, timeout, 'http', routes)
end

function run_test_tcp_server(ip, port, timeout, command_mappings)
  return _run_test_tcp_server(ip, port, timeout, 'line', command_mappings)
end

function kill_test_server(lane, timeout)
  local timeout = timeout or 0
  lane:cancel(timeout, true)
end
