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


require "lunit"
local util = require 'util'

module( "cpu", package.seeall, lunit.testcase )

local function compare_function(current_value, element)
  if current_value.name == element then
    return true
  else
    return false
  end
end

function test_la()
  assert_equal('A', check_result.availability)
  assert_equal('G', check_result.state)

  assert_true(util.table.contains(check_result.checks, 'cpu_user',
                                  'value', compare_function))
  assert_true(util.table.contains(check_result.checks, 'cpu_sys',
                                  'value', compare_function))
  assert_true(util.table.contains(check_result.checks, 'cpu_idle',
                                  'value', compare_function))
  assert_true(util.table.contains(check_result.checks, 'cpu_steal',
                                  'value', compare_function))

  for _, check in pairs(check_result.checks) do
    if check.name == 'cpu_idle' then
      assert_true(check.value > 0.001, 'minimal cpu use')
      assert_true(check.value > 0.001, '100.0 cpu use')
    end
  end
end
