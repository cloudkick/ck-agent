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
local io = require 'io'
local util = require 'util'
local Check = util.Check
local log = util.log
local structs = require 'structs'

function os.capture(cmd, raw)
  local f = assert(io.popen(cmd, 'r'))
  local s = assert(f:read('*a'))
  f:close()
  if raw then return s end
  s = string.gsub(s, '^%s+', '')
  s = string.gsub(s, '%s+$', '')
  s = string.gsub(s, '[\n\r]+', ' ')
  return s
end

local function getvalue(args)
  local rv = 0
  return os.capture('ps aux', true)
end

function run(rcheck, args)
  local rv, value = pcall(getvalue, args)
  if rv then
    rcheck:add_metric('output', value, Check.enum.string)
  else
    log.err("err from psaux: %s", tostring(value))
    rcheck:set_error("%s", value)
  end
  return rcheck
end
