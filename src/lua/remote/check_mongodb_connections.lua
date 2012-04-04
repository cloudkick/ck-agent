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
local mongodb = require 'mongodb'
local util = require 'util'
local Check = util.Check

function run(rcheck, args)
  mongodb.run_check(rcheck, args, {'connections'})
  rcheck:pull_and_compare_error("connections_current", Check.op.GT, args)
  rcheck:pull_and_compare_error("connections_available", Check.op.GT, args)
end
