--                                                                                                                                                                            
--  Copyright 2012 Rackspace
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


local util = require 'util'
local alien = require 'alien'
local log = util.log
local test_util = require 'test_util'
local Check = util.Check

local buffer = alien.buffer()
local getcwd = alien.default.getcwd

getcwd:types('pointer', 'string')
getcwd(buffer)

local cwd = tostring(buffer)
local local_plugins_path = cwd .. '/tests/plugins/'
local munin_plugins_path = cwd .. '/tests/plugins/'

function print_check(name, c)
  log.crit('\t%s', name)
  log.crit('\t\tAvail: %s', c.availability)
  log.crit('\t\tState: %s', c.state)
  log.crit('\t\tStatus: %s', c.status)
  for j,v in ipairs(c.checks) do
    log.crit("\t\t%s[%s]: %s", v.name, v.type, ""..v.value)
  end
end

function run_check(name, payload, ll)
  payload = payload or {}
  local checkname = 'check_'.. name
  local check_obj = Check.create()
  check_obj:good()
  check_obj:available()

  local rv, check = test_util.get_check_module(checkname)
  if not rv then
    log.err("check failed to load: ".. check)
    check_obj:set_error(check)
  else
    check.conf = {}
    check.conf.local_plugins_path = local_plugins_path
    check.conf.munin_plugins_path = munin_plugins_path

    local origll = equus.equus_log_level_get()
    if ll ~= nil then
      equus.equus_log_level_set(ll)
    end

    log.dbg("running %s", name)
    rv, err = pcall(check.run, check_obj, payload)

    if ll ~= nil then
      equus.equus_log_level_set(origll)
    end

    if not rv then
      log.err("check failed pcall: ".. err)
      check_obj:set_error(err)
    end
  end

  return check_obj
end

function print_help()
  print('Usage:  eqtest <check_name> /path/to/test.lua')
  print('')
end

function main()
  local check = nil
  local basic_lunit = false
  local test = nil
  local skiparg = false
  for i=1,equus.equus_get_argc()-1 do
    local v = equus.equus_get_argv(i)
    if skiparg then
      -- noop
      skiparg = false
    elseif (v == "--help" or v == "-h") then
      print_help()
      return false
    elseif (v == "--unittest" or v == "-u") then
      basic_lunit = true
    else
      if check == nil then
        check = v
      elseif test == nil then
        test = v
      else
        print('too many args')
        return false
      end
    end
  end

  if check == nil then
    print('need checkname as an arg')
    return false
  end

  if basic_lunit then
    require "lunit"
    local chunk, err = loadfile(check)
    if err then
      print(err)
      return false
    else
      chunk()
    end
    lunit.loadrunner('lunit-console')
    lunit.run()
    return true
  end
  if test == nil then
    local rv = run_check(check)
    print_check(check, rv)
  else
    local arguments = {}
    local ll = equus.EQUUS_LOG_INFO
    require "lunit"
    local chunk, err = loadfile(test)

    if err then
      print(err)
      return false
    else
      chunk()
    end

    local test_module = _G[check]

    if not test_module then
      print('Could not load test ' .. test)
      return false
    end

    -- setup function must be run manually before the check
    if test_module.equus_setup then
      test_module.equus_setup()
    end

    -- allow tests to specify custom check arguments
    if test_module.custom_arguments then
      arguments = test_module.custom_arguments
    end

    local cr = run_check(check, arguments, ll)
    test_module['check_result'] = cr

    lunit.loadrunner('lunit-console')
    lunit.run()

    if test_module.equus_teardown then
      test_module.equus_teardown()
    end
  end

  return true
end

--run_check("disk", {path={"/"}})
--run_check("loadaverage")
--run_check("psaux")
--run_check("xx")
--run_check("io")
-- run_check("apache")
-- run_check("file", {path="/etc/passwd"})
-- run_check("file")
--run_check("cpu")
--run_check("mem")
--local path={"/data/equus/src/lua/test"}
--run_check("cassandra_tpstats", {path=path})
--run_check("cassandra_cfstats", {path=path, cf={"NumericArchive"}})

main()
