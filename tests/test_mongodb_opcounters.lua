--
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


--

require "lunit"

module( "mongodb_opcounters", package.seeall, lunit.testcase )

local http_server

custom_arguments = { ipaddress = {'127.0.0.1'}, port = { 28019 } }

function equus_setup()
  http_server = test_util.run_test_http_server('127.0.0.1', 28019, nil,
                                      { ['/_status'] = {
                                        method = 'GET',
                                        status_line = '200 OK',
                                        content_type = 'application/json',
                                        file = 'data/mongodb_response.json' }})
end

function equus_teardown()
  test_util.kill_test_server(http_server)
end

function test_mongodb_opcounters()
  assert_equal('A', check_result.availability)
  assert_equal('G', check_result.state)
  assert_equal('opcounters_delete', check_result.checks[1].name)
  assert_equal('opcounters_insert', check_result.checks[2].name)
  assert_equal('opcounters_command', check_result.checks[3].name)
  assert_equal('opcounters_getmore', check_result.checks[4].name)
  assert_equal('opcounters_update', check_result.checks[5].name)
  assert_equal('opcounters_query', check_result.checks[6].name)
  assert_equal('L', check_result.checks[1].type)
  assert_equal('L', check_result.checks[2].type)
  assert_equal('L', check_result.checks[3].type)
  assert_equal('L', check_result.checks[4].type)
  assert_equal('L', check_result.checks[5].type)
  assert_equal('L', check_result.checks[6].type)
end
