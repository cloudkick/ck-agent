--
-- Copyright (c) 2009, Cloudkick, Inc.
-- All right reserved.
--

require "lunit"

module( "mongodb_locks", package.seeall, lunit.testcase )

local http_server

custom_arguments = { ipaddress = {'127.0.0.1'}, port = { 28017 } }

function equus_setup()
  http_server = test_util.run_test_http_server('127.0.0.1', 28017, nil,
                                      { ['/_status'] = {
                                        method = 'GET',
                                        status_line = '200 OK',
                                        content_type = 'application/json',
                                        file = 'data/mongodb_response.json' }})
end

function equus_teardown()
  test_util.kill_test_server(http_server)
end

function test_mongodb_locks()
  assert_equal('A', check_result.availability)
  assert_equal('G', check_result.state)
  assert_equal('locks_ratio', check_result.checks[1].name)
  assert_equal('locks_lockTime', check_result.checks[2].name)
  assert_equal('locks_totalTime', check_result.checks[3].name)
  assert_equal('n', check_result.checks[1].type)
  assert_equal('L', check_result.checks[2].type)
  assert_equal('L', check_result.checks[3].type)
end
