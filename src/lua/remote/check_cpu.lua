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
local util = require 'util'
local Check = util.Check
local log = util.log
local io = require 'io'

local use_sigar = 1

local function get_sys_times(si)
  r = {}

  if use_sigar == 1 then
    local si = equus.sigar_create()
    assert(si)
    local cpu_t = equus.sigar_cpu_t()
    local rv = equus.sigar_cpu_get(si, cpu_t)

    r.cpu_user = cpu_t.user
    r.cpu_sys = cpu_t.sys
    r.cpu_idle = cpu_t.idle
    r.cpu_irq = cpu_t.irq
    r.cpu_iowait = cpu_t.wait
    r.cpu_steal = cpu_t.stolen
  else
    local f = alien.Kernel32.GetSystemTimes
    f:types{ ret = "int", abi = "stdcall", "pointer", "pointer", "pointer" }
    local filetime = alien.defstruct{
          { "low", "ulong" },
          { "high", "ulong" }
    }
    local idle = filetime:new()
    local kernel = filetime:new()
    local user = filetime:new()
    assert( f(idle(), kernel(), user()) ~= 0 )
    r["cpu_user"] = user.high * 2^32 + user.low
    r["cpu_sys"] = kernel.high * 2^32 + kernel.low
    r["cpu_idle"] = idle.high * 2^32 + idle.low
    r["cpu_irq"] = 0
    r["cpu_iowait"] = 0
    r["cpu_steal"] = 0
  end

  if user_sigar == 1 then
    equus.sigar_destroy(si)
  end

  return r
end

local function readstat()
  -- See proc(5):
  --     <http://www.kernel.org/doc/man-pages/online/pages/man5/proc.5.html>
  local r = {}
  file = assert(io.open("/proc/stat", "r"))
  for line in file:lines() do
    l = util.split(line)
    -- skip all devices with 0 reads
    if l[1] == 'cpu' then
      r["cpu_user"] = l[2] + l[3]
      r["cpu_sys"] = l[4]
      r["cpu_idle"] = l[5]
      if # l >= 6 then
        r["cpu_iowait"] = l[6]
      else
        r["cpu_iowait"] = 0
      end
      if # l >= 8 then
        r["cpu_irq"] = l[7] + l[8]
      else
        r["cpu_irq"] = 0
      end
      if # l >= 9 then
        r["cpu_steal"] = l[9]
      else
        r["cpu_steal"] = 0
      end
    end
    if l[1] == 'intr' then
      r['intr'] = l[2]
    end
  end
  file:close()
  return r
end

local function getvalue(args)
  local a, b

  if equus.p_is_windows() == 1 then
    a = get_sys_times()
  else
    a = readstat()
  end
  util.sleep(args.period)
  if equus.p_is_windows() == 1 then
    b = get_sys_times()
  else
    b = readstat()
  end
  b["cpu_user"] = b["cpu_user"] - a["cpu_user"]
  b["cpu_sys"] = b["cpu_sys"] - a["cpu_sys"]
  b["cpu_idle"] = b["cpu_idle"] - a["cpu_idle"]
  b["cpu_irq"] = b["cpu_irq"] - a["cpu_irq"]
  b["cpu_iowait"] = b["cpu_iowait"] - a["cpu_iowait"]
  b["cpu_steal"] = b["cpu_steal"] - a["cpu_steal"]

  total = b["cpu_user"] + b["cpu_sys"] + b["cpu_idle"] + b["cpu_iowait"] + b["cpu_steal"] + b["cpu_irq"]
  b["cpu_user"] = {(b["cpu_user"] / total) * 100.0, Check.enum.double}
  b["cpu_sys"] = {(b["cpu_sys"] / total) * 100.0, Check.enum.double}
  b["cpu_idle"] = {(b["cpu_idle"] / total) * 100.0, Check.enum.double}
  b["cpu_irq"] = {(b["cpu_irq"] / total) * 100.0, Check.enum.double}
  b["cpu_iowait"] = {(b["cpu_iowait"] / total) * 100.0, Check.enum.double}
  b["cpu_steal"] = {(b["cpu_steal"] / total) * 100.0, Check.enum.double}
  if b['intr'] ~= nil then
    b['intr'] = {tonumber(b['intr']), Check.enum.gauge}
  end

  return b
end

function run(rcheck, args)
  if equus.p_is_linux() == 0 and equus.p_is_windows() == 0 then
    rcheck:set_error("cpu check is only supported on windows and linux")
    return rcheck
  end

  if not args.period then
    args.period = 5.0
  end

  local rv, r = pcall(getvalue, args)
  if rv then
    for k,v in pairs(r) do
      rcheck:add_metric(k, v[1], v[2])
    end
    rcheck:set_status('user:%.2f%% system:%.2f%% idle:%.2f%% iowait:%.2f%% steal:%.2f%%',
      r['cpu_user'][1], r['cpu_sys'][1], r['cpu_idle'][1], r['cpu_iowait'][1], r['cpu_steal'][1])
  else
    log.err("reading the cpu stats failed: %s", r)
    rcheck:set_error("%s", r)
  end

  return rcheck
end
