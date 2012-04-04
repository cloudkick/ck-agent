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
local json = require 'Json'
local Check = util.Check
local log = util.log
local http = require 'socket.http'
local ltn12 = require 'ltn12'

function get_status(url, rcheck)
  local body = {}

  log.dbg("Hitting url %s", url)

  local r, code = http.request{url = url,
                               sink = ltn12.sink.table(body)}

  if r == nil then
    rcheck:set_error("GET on %s failed: %s", url, code)
    return nil
  end

  if body == nil then
     rcheck:set_error("GET on %s returned no body", url)
  else
     log.dbg("Response body %s", table.concat(body, ''))
  end

  if (code >= 300 or code < 200) and code ~= 599 then
     rcheck:set_error("GET on %s returned %s", url, code)
     return nil
  end

  return table.concat(body, '')
end

function parse_response(response, rcheck, extrainfo, metrics)
  local metric_type, value, value_type
  local decoded = json.Decode(response)
  local server_status = decoded.serverStatus

  local available_metrics = { locks = server_status.globalLock, memory = server_status.mem, bgflushing = server_status.backgroundFlushing, connections = server_status.connections, indexcounters = server_status.indexCounters.btree, opcounters = server_status.opcounters, asserts = server_status.asserts }
  local ignored_metrics = { "supported", "last_finished", "note" }
  local double_metrics = { "ratio", "missRatio", "total_ms", "average_ms", "last_ms" }

  if extrainfo then
    metrics["extrainfo"] = server_status.extra_info
  end
  
  for metric_name, metric_values in pairs(available_metrics) do
    for key, value in pairs(metric_values) do repeat

      if table.contains(ignored_metrics, key) or not table.contains(metrics, metric_name) then
        break
      end

      value_type = type(value)
      if value_type == "table" then
        -- In case we encounter a value of type "table" (new nested value gets
        -- added to the MongoDB status page), we just skip this iteration
        break
      elseif table.contains(double_metrics, key) then
        metric_type = Check.enum.double
      elseif value_type == "number" then
        metric_type = Check.enum.uint64
      elseif value_type == "boolean" then
        metric_type = Check.enum.string
        value = tostring(value)
      else
        metric_type = Check.enum.guess
      end

      rcheck:add_metric(metric_name .. "_" .. key, value, metric_type)
    until true end
  end
end

function run_check(rcheck, args, metrics)
  local url, port, extra_info
  
  if args.port then
    port = args.port[1]
  else
    port = 28017
  end

  if args.extra_info then
    extra_info = true
  else
    extra_info = false
  end

  if args.ipaddress and port then
    url = "http://" .. args.ipaddress[1] .. ":" .. port .. "/_status"
  else
    url = "http://localhost:28017/_status"
  end

  local body = get_status(url, rcheck)

  if body then
    parse_response(body, rcheck, extra_info, metrics)
  end
end
