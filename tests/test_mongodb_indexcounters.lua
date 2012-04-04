--
-- Copyright (c) 2009, Cloudkick, Inc.
-- All right reserved.
--

require "lunit"

module( "mongodb_indexcounters", package.seeall, lunit.testcase )

local http_server

custom_arguments = { ipaddress = {'127.0.0.1'}, port = { 28016 } }

function equus_setup()
  http_server = test_util.run_test_http_server('127.0.0.1', 28016, nil,
                                      { ['/_status'] = {
                                        method = 'GET',
                                        status_line = '200 OK',
                                        content_type = 'application/json',
                                        file = 'data/mongodb_response.json' }})
end

function equus_teardown()
  test_util.kill_test_server(http_server)
end

function test_mongodb_indexcounters()
  assert_equal('A', check_result.availability)
  assert_equal('G', check_result.state)
  assert_equal('indexcounters_misses', check_result.checks[1].name)
  assert_equal('indexcounters_missRatio', check_result.checks[2].name)
  assert_equal('indexcounters_resets', check_result.checks[3].name)
  assert_equal('indexcounters_accesses', check_result.checks[4].name)
  assert_equal('indexcounters_hits', check_result.checks[5].name)
  assert_equal('L', check_result.checks[1].type)
  assert_equal('n', check_result.checks[2].type)
  assert_equal('L', check_result.checks[3].type)
  assert_equal('L', check_result.checks[4].type)
  assert_equal('L', check_result.checks[5].type)
end
