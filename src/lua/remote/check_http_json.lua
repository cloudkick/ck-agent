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
local log = util.log
local json = require 'Json'
local Check = util.Check
local http = require 'socket.http'
local ltn12 = require 'ltn12'

local function get_response(url, rcheck)
  local response = {}
  local r, code = http.request{url = url, sink = ltn12.sink.table(response)}

  if r == nil then
    rcheck:set_error('GET on %s failed: %s', url, code)
    return nil
  end

  if (code >= 300 or code < 200) then
    rcheck:set_error('GET on %s returned %s', url, code)
    return nil
  end

  if response == nil then
    rcheck:set_error('GET on %s returned no body', url)
  else
    log.dbg("Response body %s", table.concat(response))
  end

  return table.concat(response)
end

local function parse_json_response(response, rcheck)
  local metric_name, metric_type, metric_value, value_type

  local rv, decoded = pcall(json.Decode, response)
  local valid_states = { 'ok', 'warn', 'err' }
  local valid_metric_types = { 'int', 'float', 'gauge', 'string' }

  if not rv then
    rcheck:set_error('Failed to parse response as JSON')
    return
  end

  local status = decoded.status
  local state = decoded.state
  local metrics = decoded.metrics

  if not status then
    status = ''
  end

  if not metrics then
    metrics = {}
  end

  if not state then
    rcheck:set_error('Check state missing')
    return
  end

  if not table.contains(valid_states, state) then
    rcheck:set_error('Invalid check state: %s', state)
    return
  end

  rcheck:set_status(status)

  if state == 'ok' then
    rcheck:set_state_avail('A', 'G')
  elseif state == 'warn' then
    rcheck:set_state_avail('A', 'B')
  elseif state == 'err' then
    rcheck:set_state_avail('U', 'B')
  end

  for index, metric in pairs(metrics) do repeat
    metric_name = metric['name']
    metric_type = metric['type']
    metric_value = metric['value']

    if not metric_name or not metric_type or not metric_value then
      -- Skip metrics with missing keys
      break
    end

    if not table.contains(valid_metric_types, metric_type) then
      -- Ignore invalid metric types
      break
    end

    value_type = util.string_to_value_type(metric_type)
    rcheck:add_metric(metric_name, metric_value, value_type)
  until true end
end

function run(rcheck, args)
  local url

  if not args.url then
    rcheck:set_error('Missing required argument \'url\'')
    return rcheck
  end

  url = args.url[1]
  local response = get_response(url, rcheck)

  if response then
    parse_json_response(response, rcheck)
  end

  return rcheck
end
