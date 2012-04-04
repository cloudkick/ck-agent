--
-- Copyright (c) 2009, Cloudkick, Inc.
-- All right reserved.
--

require "lunit"
local test_util = require 'test_util'

module( "mongodb_connections", package.seeall, lunit.testcase )

custom_arguments = { ipaddress = {'127.0.0.1'}, port = { 28015 } }

function equus_setup()
  http_server = test_util.run_test_http_server('127.0.0.1', 28015, nil,
                                      { ['/_status'] = {
                                        method = 'GET',
                                        status_line = '200 OK',
                                        content_type = 'application/json',
                                        file = 'data/mongodb_response.json' }})
end

function equus_teardown()
  test_util.kill_test_server(http_server)
end

function test_mongodb_connections()
  assert_equal('A', check_result.availability)
  assert_equal('G', check_result.state)
  assert_equal('connections_available', check_result.checks[1].name)
  assert_equal('connections_current', check_result.checks[2].name)
  assert_equal('L', check_result.checks[1].type)
  assert_equal('L', check_result.checks[2].type)
end
