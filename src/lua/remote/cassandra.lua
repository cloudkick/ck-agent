--                                                                                                                                                                            
--  Copyright 2012 Rackspace
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
--


module(..., package.seeall);
local util = require 'util'

function failed_connecting(line)
  local match1, match2, match3 = nil, nil, nil

  _, _, match1 = line:lower():find('.*(error connecting).*')
  _, _, match2 = line:lower():find('.*(connection refused).*')
  _, _, match3 = line:lower():find('.*(connection timeout).*')

  if match1 or match2 or match3 then
    return true
  end

  return false
end
