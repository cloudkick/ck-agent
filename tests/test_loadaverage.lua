--
-- Copyright (c) 2009, Cloudkick, Inc.
-- All right reserved.
--

require "lunit"

module( "loadaverage", package.seeall, lunit.testcase )


function test_la()
  if equus.p_is_windows() == 1 then
    return
  end
  assert_equal('A', check_result.availability)
  assert_equal('G', check_result.state)
  assert_equal('loadaverage_1m', check_result.checks[1].name)
  assert_equal('n', check_result.checks[1].type)
  assert_true(check_result.checks[1].value > 0.001, 'minimal load average')
  assert_true(check_result.checks[1].value < 10.0, '10.0 load average')
end
