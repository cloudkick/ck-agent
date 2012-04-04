--
-- Copyright (c) 2010, Cloudkick, Inc.
-- All right reserved.
--

require "lunit"

module( "check_compare_values", package.seeall, lunit.testcase )
local util = require('util')
local test_util = require('test_util')
local Check = util.Check

local _, le = test_util.get_check_module('check_local_exec')

function test_missing_plugin()
  local chk_obj = Check.create()
  le.run(chk_obj, {check={"test_missing_plugin_never_here"}})
  assert_match("No such file or directory", chk_obj.status)
end

function test_util_cmd_to_table()
  local t = util.cmd_to_table("test", "foo bar")
  assert_table(t)
  assert_equal("test", t[1])
  assert_equal("foo", t[2])
  assert_equal("bar", t[3])

  local t = util.cmd_to_table("test", "\"foo\" bar")
  assert_table(t)
  assert_equal("test", t[1])
  assert_equal('foo', t[2])
  assert_equal("bar", t[3])

  local t = util.cmd_to_table("test", "\"foo bar\"")
  assert_table(t)
  assert_equal("test", t[1])
  assert_equal("foo bar", t[2])
end

function test_exec()
  local content, rv = equus_exec_call_unix_core({'ls', '/'})
  assert_equal(0, rv)
  assert_match("usr", content)

  content, rv = equus_exec_call_unix_core({'ls', '/does_not_exist'})
  if equus.p_is_linux() == 1 then
    -- linux 'ls' returns 2 if a command line arg wasn't found. sigh.
    assert_equal(2, rv)
  else
    assert_equal(1, rv)
  end
end

