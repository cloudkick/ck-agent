--
-- Copyright (c) 2009, Cloudkick, Inc.
-- All right reserved.
--

require "lunit"

module( "test_net", package.seeall, lunit.testcase )

function test_net()
  assert_equal('A', check_result.availability)
  assert_equal('G', check_result.state)
  for j,v in ipairs(check_result.checks) do
    value = tonumber(v.value)
    if v.name == "out_packets" then
      assert_equal('G', v.type)
      assert_true(value > 1, 'Value of out packets > 1')
    elseif v.name == "out_bytes" then
      assert_equal('G', v.type)
      assert_true(value > 1, 'Value of out bytes > 1')
    elseif v.name == "out_err" then
      assert_equal('G', v.type)
      assert_true(v.value >= 0, 'Value of out err >= 0')
    elseif v.name == "out_mcast" then
      assert_equal('G', v.type)
      assert_true(v.value >= 0, 'Value of out mcast >= 0')
    elseif v.name == "in_bytes" then
        assert_equal('G', v.type)
        assert_true(value > 1, 'Value of in bytes > 1')
    elseif v.name == "in_packets" then
        assert_equal('G', v.type)
        assert_true(value > 1, 'Value of in packets > 1')
    elseif v.name == "in_err" then
      assert_equal('G', v.type)
      assert_true(value >= 0,  'Value of in err >= 0')
    elseif v.name == "in_mcast" then
      assert_equal('G', v.type)
      assert_true(value >= 0,  'Value of in mcast >= 0')
    else
      assert(false, 'Invalid check metric in net check: '.. v.name)
    end
  end
  
end
