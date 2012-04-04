--
-- Copyright (c) 2009, Cloudkick, Inc.
-- All right reserved.
--

require "lunit"

module( "psaux", package.seeall, lunit.testcase )

function test_ps()
  assert_equal('A', check_result.availability)
  assert_equal('G', check_result.state)
  assert_equal('output', check_result.checks[1].name)
  assert_equal('s', check_result.checks[1].type)
  if equus.p_is_windows() == 1 then
    -- TODO: this assumes cygwin on windows
    assert_match('bin/ps', check_result.checks[1].value , 'ps aux contains itself')
  else
    assert_match('ps aux', check_result.checks[1].value , 'ps aux contains itself')
  end
end
