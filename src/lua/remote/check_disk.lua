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
local alien = require 'alien'
local util = require 'util'
local Check = util.Check
local log = util.log
local structs = require 'structs'

local function win_getvalue(args)
  local f = alien.Kernel32.GetDiskFreeSpaceExA
  f:types{ ret = "int", abi = "stdcall", "string", "pointer", "pointer", "pointer" }
  ulargeint = alien.defstruct{
    { "low", "ulong" },
    { "high", "ulong" }
  }
  local disk_free = ulargeint:new()
  local disk_total = ulargeint:new()
  local disk_total_free = ulargeint:new()
  log.dbg("calling alien.Kernel32.GetDiskFreeSpaceExA('%q')", args.path)
  assert( f(args.path, disk_free(), disk_total(), disk_total_free()) ~= 0 )
  local r = {}
  r.bsize = 1024
  r.blocks = (disk_total.high * 2^32 + disk_total.low) / r.bsize
  r.bfree = (disk_total_free.high * 2^32 + disk_free.low) / r.bsize
  r.capacity = 100 - ((r.bfree/r.blocks) * 100)
  return r
end

local function getvalue(args)
  local libc = alien.default
  local buf = alien.buffer(structs.statfs.__size)
  local rv = 0
  if equus.p_is_darwin() == 1 then
    libc.statfs64:types("int", "string", "pointer")
    log.dbg("calling libc.statfs64('%q')", args.path)
    rv = libc.statfs64(args.path, buf:topointer())
    log.dbg("libc.statfs64('%q') = %d", args.path, rv)
  else
    libc.statfs:types("int", "string", "pointer")
    log.dbg("calling libc.statfs('%q')", args.path)
    rv = libc.statfs(args.path, buf:topointer())
    log.dbg("libc.statfs('%q') = %d", args.path, rv)
  end

  if rv < 0 then
    error("libc.statfs returned ".. rv)
  end

  local r = {}
  r.bsize = buf:get(structs.statfs.f_bsize+1, "uint")
  r.blocks = buf:get(structs.statfs.f_blocks+1, "long")
  r.bavail = buf:get(structs.statfs.f_bavail+1, "long") -- blocks available to non-root users. this is what we actually care about
  r.bfree = buf:get(structs.statfs.f_bfree+1, "long") -- blocks available to root

  local blocks_total_nonroot = r.blocks - r.bfree + r.bavail
  r.blocks_used = blocks_total_nonroot - r.bavail

  r.capacity = (r.blocks_used / blocks_total_nonroot) * 100
  if r.capacity > 100 then
    log.msg("capacity calculation returned %s, capping at 100%%", r.capacity)
    r.capacity = 100
  end

  return r
end

function run(rcheck, args)
  if args.path == nil then
    if equus.p_is_windows() == 1 then
      args.path = 'c:\\'
    else
      args.path = '/'
    end
  else
    args.path = args.path[1]
  end

  local rv = nil
  local r = nil
  if equus.p_is_windows() == 1 then
    rv, r = pcall(win_getvalue, args)
  else
    rv, r = pcall(getvalue, args)
  end
  if rv then
    rcheck:add_metric('capacity', r.capacity, Check.enum.double)
    rcheck:add_metric('bsize', r.bsize, Check.enum.uint64)
    rcheck:add_metric('blocks', r.blocks, Check.enum.uint64)
    rcheck:add_metric('bfree', r.bfree, Check.enum.uint64)

    local used = (r.blocks - r.bfree)

    if equus.p_is_windows() == 0 then
      rcheck:add_metric('bavail', r.bavail, Check.enum.uint64)
      used = r.blocks_used
    end

    local free = (r.blocks - used)
    local total_gb = (r.blocks * r.bsize) / 1024 / 1024 / 1024
    local used_gb = (used * r.bsize) / 1024 / 1024 / 1024
    local free_gb = ((r.blocks - used) * r.bsize) / 1024 / 1024 / 1024

    rcheck:set_status('capacity: %.2f%% total: %.2f GB, used: %.2f GB, free: %.2f GB',
      r.capacity, total_gb, used_gb, free_gb)
  else
    log.err("disk failed err: %s", r)
    rcheck:set_error("%s", r)
  end
  return rcheck
end
