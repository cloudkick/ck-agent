--
-- Copyright (c) 2010, Cloudkick, Inc.
-- All right reserved.
--

require "lunit"

module( "check_compare_values", package.seeall, lunit.testcase )
local util = require('util')
local Check = util.Check

function test_no_change()
  local chk_obj = Check.create()
  chk_obj:add_metric("test1", 177.0, Check.enum.int32)
  chk_obj:set_status("hello %.2f", 127.0)
  assert_equal("hello 127.00", chk_obj.status)
  -- This is true so it won't change the status
  chk_obj:compare_metric("test1", Check.op.GT, 197, "U", "B")
  assert_equal("hello 127.00", chk_obj.status)
end

function test_change_status()
  local chk_obj = Check.create()
  chk_obj:add_metric("test1", 177.0, Check.enum.int32)
  chk_obj:set_status("hello %.2f", 127.0)
  assert_equal("hello 127.00", chk_obj.status)
  -- This is true so it won't change the status
  chk_obj:compare_metric("test1", Check.op.GT, 107, "U", "B")
  assert_not_equal("hello 127.00", chk_obj.status)
end

function test_null_input()
  local chk_obj = Check.create()
  chk_obj:add_metric("test1", 177.0, Check.enum.int32)
  chk_obj:set_status("hello %.2f", 127.0)
  assert_equal("hello 127.00", chk_obj.status)
  -- This is true so it won't change the status
  chk_obj:compare_metric("test1", Check.op.GT, nil, "U", "B")
  assert_equal("hello 127.00", chk_obj.status)
end
