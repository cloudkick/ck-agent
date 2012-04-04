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
      auth = { authentication = "Basic " .. (mime.b64(user[1] .. ":" .. pw[1])) }
    else
      rcheck:set_error("The Cloudkick Agent Binary must be upgraded to support HTTP Password authentication.")
      return nil
    end
  end

  local r, code = http.request{url = url, headers = auth,
                               sink = ltn12.sink.table(body)}

  if not (code == 200) then
     rcheck:set_error("GET on %s returned %s", url, code)
     return nil
  end

  if body == nil then
     rcheck:set_error("GET on %s returned no body", url)
  end

  return body
end

-- nginx_status output is a fixed four-line format e.g.
--
-- Active connections: 1
-- server accepts handled requests
--  3 3 21
-- Reading: 0 Writing: 1 Waiting: 0
--
-- http://wiki.nginx.org/NginxHttpStubStatusModule
--
function parse_line(line, i, rcheck)
  if i == 1 then
    parse_colon(line, rcheck)
  elseif i == 2 then
    if not line == "server accepts handled requests" then
      rcheck:set_error("unknown nginx line: %s", f)
    end
  elseif i == 3 then
    local j = 1
    for str in line:gfind("%s*%d+%s*") do
      parse_history(str, j, rcheck)
      j = j + 1
    end
  elseif i == 4 then
    for str in line:gfind("[%w%s]+: %d+") do
      parse_colon(str, rcheck)
    end
  else
     rcheck:set_error("too many lines for nginx status")
  end
end

function parse_history(str, j, rcheck)
  if j == 1 then
     rcheck:add_metric("accepted", str, Check.enum.gauge)
  elseif j == 2 then
     rcheck:add_metric("handled", str, Check.enum.gauge)
  elseif j == 3 then
     rcheck:add_metric("requested", str, Check.enum.gauge)
  else
     rcheck:set_error("unknown nginx history statistic")
  end
end

function parse_colon(str, rcheck)
  local i, j = str:find(":")
  local f = str:sub(0, i-1)
  local v = str:sub(i+1, str:len())

  f = f:lower()
  f = f:gsub("^ ", "")
  v = v:gsub(" ", "")

  if f == 'active connections' then
     rcheck:add_metric("active", v, Check.enum.uint64)
  elseif f == 'reading' or f == 'writing' or f == 'waiting' then
     rcheck:add_metric(f, v, Check.enum.uint64)
  else
     rcheck:set_error("unknown nginx statistic: %s", f)
  end
end

function run(rcheck, args)
  local url

  if args.port then
    port = args.port[1]
  else
    port = 80
  end

  if args.ipaddress and port then
    url = "http://" .. args.ipaddress[1] .. ":" .. port .. "/nginx_status"
  else
    url = "http://localhost/nginx_status"
  end

  if args.url then
    url = args.url[1]
  end

  local body = get_status(url, args.user, args.pw, rcheck)
  local num = 1

  if body then
    for line in body[1]:gmatch("([^\n]*)\n") do
      parse_line(line, num, rcheck)
      num = num + 1
    end
  end
end
