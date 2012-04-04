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
local http = require 'socket.http'
local ltn12 = require("ltn12")
local mime = require("mime.core")

local server_status = nil

local function request(u, a)
  if a then return http.request{url = u, a}
  else return http.request{url = u}
  end
end

local function get_status(url, user, pw, rcheck)
  local auth = nil
  local body = {}

  if user and pw then
    if mime.b64 ~= nil then
      auth = { authorization = "Basic " .. (mime.b64(user[1] .. ":" .. pw[1])) }
    else
      rcheck:set_error("The Cloudkick Agent Binary must be upgraded to support HTTP Password authentication.")
      return nil
    end
  end

  local r, code = http.request{url = url, headers = auth,
                               sink = ltn12.sink.table(body)}

  if body == nil then
    rcheck:set_error("GET on %s returned no body", url)
  else
    log.dbg("Response body %s", table.concat(body, ''))
  end

  if not (code == 200) then
    rcheck:set_error("GET on %s returned %s", url, code)
    return nil
  end

  return table.concat(body, '')
end

function parse_line(line, rcheck)
  local i, j = line:find(":")

  if i == nil then
    rcheck:set_error("Malformed Apache status page")
    return false
  end

  local f = line:sub(0, i-1)
  local v = line:sub(i+1, line:len())

  f = f:gsub(" ", "_")

  if f == 'Total_Accesses' then
     rcheck:add_metric(f, v, Check.enum.gauge)
  end

  if f == 'Total_kBytes' or f == 'Uptime' or
     f == 'BytesPerSec' or f == 'BytesPerReq' or f == 'BusyWorkers' or
     f == 'IdleWorkers' then
     rcheck:add_metric(f, v, Check.enum.uint64)
  end

  if f == 'CPULoad' or f == 'ReqPerSec' then
     rcheck:add_metric(f, v, Check.enum.double)
  end

  if f == 'ReqPerSec' then
    rcheck:set_status('ReqPerSec: %.2f', v)
  end

  if f == 'Scoreboard' then
     local t = parse_scoreboard(v, rcheck)
     for i,x in pairs(t) do
       rcheck:add_metric(i, x, Check.enum.uint64)
     end
  end

  return true
end

-- "_" Waiting for Connection, "S" Starting up, "R" Reading Request,
-- "W" Sending Reply, "K" Keepalive (read), "D" DNS Lookup,
-- "C" Closing connection, "L" Logging, "G" Gracefully finishing,
-- "I" Idle cleanup of worker, "." Open slot with no current process
function parse_scoreboard(board)
  local t = { waiting = 0, starting = 0, reading = 0, sending = 0,
              keepalive = 0, dns = 0, closing = 0, logging = 0,
              gracefully_finishing = 0, idle = 0, open = 0 }

  for c in board:gmatch"." do
    if c == '_' then t.waiting = t.waiting + 1
    elseif c == 'S' then t.starting = t.starting + 1
    elseif c == 'R' then t.reading = t.reading + 1
    elseif c == 'W' then t.sending = t.sending + 1
    elseif c == 'K' then t.keepalive = t.keepalive + 1
    elseif c == 'D' then t.dns = t.dns + 1
    elseif c == 'C' then t.closing = t.closing + 1
    elseif c == 'L' then t.logging = t.logging + 1
    elseif c == 'G' then t.gracefully_finishing = t.gracefully_finishing + 1
    elseif c == 'I' then t.idle = t.idle + 1
    elseif c == '.' then t.open = t.open + 1
    end
  end
  return t
end


function run(rcheck, args)
  local url

  if args.port then
    port = args.port[1]
  else
    port = 80
  end

  if args.ipaddress and port then
    url = "http://" .. args.ipaddress[1] .. ":" .. port .. "/server-status?auto"
  else
    url = "http://localhost/server-status?auto"
  end

  log.dbg("Server status url is %s", url)

  local body = get_status(url, args.user, args.pw, rcheck)

  if body then
    for line in body:gmatch("([^\n]*)\n") do
      status = parse_line(line, rcheck)

      if not status then
        return
      end
    end

  end
end
