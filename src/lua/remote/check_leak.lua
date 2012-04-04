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
local nicesize = util.nicesize
local log = util.log

local function getvalue(args)
  local r = {}
  equus.win32_mem_checkpoint()
  equus.win32_mem_difference()
  r["mem_total"] = equus.win32_mem_values()
  return r
end

function run(rcheck, args)
  if equus.p_is_windows() == 0 then
    rcheck:set_error("memory leak check is only supported on windows")
    return rcheck
  end

  local rv, r = pcall(getvalue, args)
  if rv then
    for k,v in pairs(r) do
      rcheck:add_metric(k, v, Check.enum.uint64)
    end
    rcheck:set_status("memory value:%s", nicesize(tonumber(r["mem_total"])))
  else
    log.err("memory check failed: %s", tostring(r))
    rcheck:set_error("%s", r)
  end
  return rcheck
end
