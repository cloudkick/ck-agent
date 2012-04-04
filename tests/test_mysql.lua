--
-- Copyright (c) 2009, Cloudkick, Inc.
-- All right reserved.
--

require "lunit"

module( "mysql", package.seeall, lunit.testcase )

function test_mysql()
  assert_equal('A', check_result.availability)
  assert_equal('G', check_result.state)

  assert_equal('Aborted_clients', check_result.checks[1].name)
  assert_equal('L', check_result.checks[1].type)
end
