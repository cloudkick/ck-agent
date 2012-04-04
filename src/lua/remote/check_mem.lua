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
local nicesize = util.nicesize
local log = util.log
local io = require 'io'

local function win_readmeminfo()
  local f = alien.Kernel32.GlobalMemoryStatusEx
  f:types{ ret = "int", abi = "stdcall", "pointer" }
  memstatusex = alien.defstruct{
    { "dwLength", "ulong" },
    { "dwMemoryLoad", "ulong" },               -- % of memory in use
    { "ullTotalPhysLow", "ulong" },            -- total bytes of physical memory
    { "ullTotalPhysHigh", "ulong" },           -- (high word)
    { "ullAvailPhysLow", "ulong" },            -- free bytes of physical memory
    { "ullAvailPhysHigh", "ulong" },
    { "ullTotalPageFileLow", "ulong" },        -- total bytes of paging file
    { "ullTotalPageFileHigh", "ulong" },
    { "ullAvailPageFileLow", "ulong" },        -- free bytes of paging file
    { "ullAvailPageFileHigh", "ulong" },
    { "ullTotalVirtualLow", "ulong" },         -- total bytes of virtual memory
    { "ullTotalVirtualHigh", "ulong" },
    { "ullAvailVirtualLow", "ulong" },         -- free bytes of virtual memory
    { "ullAvailVirtualHigh", "ulong" },
    { "ullAvailExtendedVirtualLow", "ulong" }, -- free bytes of extended memory
    { "ullAvailExtendedVirtualHigh", "ulong" }
  }
  mem_status = memstatusex:new()
  mem_status.dwLength = 64
  log.dbg("calling alien.Kernel32.GlobalMemoryStatusEx()")
  assert( f(mem_status()) ~= 0 )
  local r = {}
  r["total"] = mem_status.ullTotalPhysHigh * 2^32 + mem_status.ullTotalPhysLow
  r["free"] = mem_status.ullAvailPhysHigh * 2^32 + mem_status.ullAvailPhysLow
  r["buffer"] = 0
  r["cached"] = 0
  r["swap_total"] = mem_status.ullTotalPageFileHigh * 2^32 + mem_status.ullTotalPageFileLow
  r["swap_free"] = mem_status.ullAvailPageFileHigh * 2^32 + mem_status.ullAvailPageFileLow
  return r
end

local function get_sysctl_value(key)
  local stream = assert(io.popen('sysctl ' .. key, 'r'))
	
  for line in stream:lines() do
    _, _, value = string.find(line, '^' .. key .. ': (.+)$')
  end
  
  stream:close()
    
  return value
end

local function freebsd_readmeminfo()
  local r = {}
  
  local pagesize, mem_total, mem_free, mem_application, mem_cached,
        mem_buffer
  local swap_total = 0
  local swap_used = 0
  local swap_free = 0
  
  pagesize = get_sysctl_value('hw.pagesize')
  mem_total = get_sysctl_value('hw.physmem')
  mem_free = get_sysctl_value('vm.stats.vm.v_free_count') * pagesize
  mem_application = get_sysctl_value('vm.stats.vm.v_active_count') * pagesize
  mem_cached = get_sysctl_value('vm.stats.vm.v_cache_count') * pagesize
  mem_buffer = mem_total - mem_application - mem_cached
  
  local swap_stream = assert(assert(io.popen('swapctl -l -k ', 'r')))
  
  for line in swap_stream:lines() do
    _, _, swap_total_temp, swap_used_temp = string.find(line, '^.+%s(%d+)%s(.+)$')
    if swap_total_temp ~= nil and swap_used_temp ~= nil then
      swap_total = swap_total + swap_total_temp
      swap_used = swap_used + swap_used_temp
    end
  end
  
  swap_stream:close()
  
  swap_free = swap_total - swap_used
  
  r['total'] = mem_total
  r['free'] = mem_free
  r['buffer'] = mem_buffer
  r['cached'] = mem_cached
  
  r['swap_total'] = swap_total * 1024
  r['swap_free'] = swap_free * 1024
  
  return r
end

local function readmeminfo()
  -- See proc(5):
  --     <http://www.kernel.org/doc/man-pages/online/pages/man5/proc.5.html>
  local r = {}
  file = assert(io.open("/proc/meminfo", "r"))
  for line in file:lines() do
    l = util.split(line)
    if l[1] == 'MemTotal:' then
      r["total"] = l[2] * 1024
    end
    if l[1] == 'MemFree:' then
      r["free"] = l[2] * 1024
    end
    if l[1] == 'Buffers:' then
      r["buffer"] = l[2] * 1024
    end
    if l[1] == 'Cached:' then
      r["cached"] = l[2] * 1024
    end
    if l[1] == 'SwapTotal:' then
      r["swap_total"] = l[2] * 1024
    end
    if l[1] == 'SwapFree:' then
      r["swap_free"] = l[2] * 1024
    end
  --  if l[1] == 'Active:' then
  --    r["active"] = l[2] * 1024
  --  end
  --  if l[1] == 'Inactive:' then
  --    r["inactive"] = l[2] * 1024
  --  end
  end
  file:close()
  return r
end

local function getvalue(args)
  local r = {}
  local a = nil
  if equus.p_is_windows() == 1 then
    a = win_readmeminfo()
  else
    a = readmeminfo()
  end
  r["mem_total"] = a["total"]
  r["mem_used"] = a["total"] - a["free"] - a["buffer"] - a["cached"]
  r["mem_free"] = a["free"]
  r["swap_total"] = a["swap_total"]
  r["swap_used"] = a["swap_total"] - a["swap_free"]
  return r
end

function run(rcheck, args)
  if equus.p_is_windows() == 0 and equus.p_is_linux() == 0 then
    rcheck:set_error("memory check is only supported on windows, linux and freebsd")
    return rcheck
  end

  local rv, r = pcall(getvalue, args)
  if rv then
    for k,v in pairs(r) do
      rcheck:add_metric(k, v, Check.enum.uint64)
    end
    rcheck:set_status("memory used:%s swap used:%s", nicesize(tonumber(r["mem_used"])), nicesize(tonumber(r["swap_used"])))
  else
    log.err("memory check failed: %s", r)
    rcheck:set_error("%s", r)
  end
  return rcheck
end
