--                                                                                                                                                                            --  Copyright 2012 Rackspace
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

module(..., package.seeall);
local io = require 'io'
local util = require 'util'
local Check = util.Check
local log = util.log
local structs = require 'structs'

local function command(cmd, no_lf)
    local t = assert(io.open(cmd))
    t:close()
    local f = io.popen(cmd..' 2>&1; echo "-retcode:$?"' ,'r')
    local l = f:read '*a'
    f:close()
    local i1,i2,ret = l:find('%-retcode:(%d+)\n$')
    if no_lf and i1 > 1 then i1 = i1 - 1 end
    l = l:sub(1,i1-1)
    return l,tonumber(ret)
end

local function equus_exec_call_win32(args)
  local escaped = {}
  local i
  local v

  for i,v in ipairs(args) do
    escaped[i] = '"' .. string.gsub(v, '"', '\\"') .. '"'
  end

  cmd = table.concat(escaped, " ")

  return equus_exec_call_win32_core(cmd)
end

local function getvalue(args)
  local p,rc
  local rv = 0
  local plugins_path = conf.local_plugins_path

  local c = plugins_path .. args.check

  log.dbg("Custom plugin is %s", tostring(c))

  if args.args ~= nil then
    log.dbg("Custom plugin args: %s", tostring(args.args))
    local cmd = util.cmd_to_table(c, args.args)
    if equus.p_is_windows() == 1 then
      p,rc = equus_exec_call_win32(cmd)
    else
      p,rc = equus_exec_call_unix_core(cmd)
    end
  else
    if equus.p_is_windows() == 1 then
      p,rc = equus_exec_call_win32_core('"' .. c .. '"')
    else
      if equus_exec_call_unix_core ~= nil then
        local cmd = {}
        table.insert(cmd, c)
        p,rc = equus_exec_call_unix_core(cmd)
      else
        p,rc = command(c)
      end
    end
  end
  return p,rc
end

function run(rcheck, args)
  if args.check == nil then
    error("Invalid check name")
  end

  if type(args.check) == "table" then
    args.check = args.check[1]
  end

  if type(args.args) == "table" then
    args.args = args.args[1]
  end

  if type(args.args) ~= "string" then
    args.args = nil
  end

  if type(args.args) == "string" and args.args:len() == 0 then
    args.args = nil
  end

  if args.args ~= nil then
    if equus.p_is_windows() == 1 and equus_exec_call_win32_core == nil then
      rcheck:set_error("Custom arguments require a newer agent version.")
      return rcheck
    end
    if equus.p_is_windows() == 0 and equus_exec_call_unix_core == nil then
      rcheck:set_error("Custom arguments require a newer agent version.")
      return rcheck
    end
  end

  local rv, r, rc = pcall(getvalue, args)

  log.dbg("Custom plugin output: %s", tostring(r))

  if rv and rc == 0 then
    rcheck.output = r
  else
    if rc ~= 0 and rc ~= nil then
      r = string.format("exit code: %d output: %s", rc, tostring(r))
    end
    log.err("err from custom plugin: %s", tostring(r))
    rcheck:set_error("%s", tostring(r))
  end
  return rcheck
end
