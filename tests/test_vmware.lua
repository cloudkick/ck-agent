--
-- Copyright 2010, Cloudkick, Inc.
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--

require "lunit"

module( "vmware", package.seeall, lunit.testcase )

function test_vmware()
  print(check_result.status)
  assert_equal('A', check_result.availability)
  assert_equal('G', check_result.state)

  --assert_equal('cpu_reservation_mhz', check_result.checks[1].name)
  --assert_equal('i', check_result.checks[1].type)
end

