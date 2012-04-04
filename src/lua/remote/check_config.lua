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
local config = require 'config'

local function getvalue(args)
  local conf_attributes = config.get_config_attributes()

  return conf_attributes
end

function run(rcheck, args)
  local rv, r = pcall(getvalue, args)

  if rv then
    rcheck.conf = r
    rcheck:set_status('')
  else
    rcheck:set_error('failed to parse config: %s', r)
    log.err("config failed err: %s", r)
  end
  return rcheck
end
