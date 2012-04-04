--                                                                                                                                                                           --  Copyright 2012 Rackspace
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
local os = require 'os'

-- Details of tv_nsec from stat(2)
-- Since  kernel 2.5.48, the stat structure supports nanosecond resolution
-- for the three file timestamp fields.  Glibc exposes the nanosecond com-
-- ponent of each field using names either of the form st_atim.tv_nsec, if
-- the _BSD_SOURCE or _SVID_SOURCE feature test macro is  defined,  or  of
-- the  form st_atimensec, if neither of these macros is defined.  On file
-- systems that do not support  sub-second  timestamps,  these  nanosecond
-- fields are returned with the value 0.

-- extract timespec struct from an offset
local function get_timespec(buf, time)
  local timespec = {}
  local st_xtime = "st_" .. time .. "time"
  local xtim = time .. "tim"
  local st_xspec = "st_" .. time .. "timespec"

  if not structs.stat[xtim] == -1 then
    timespec.tv_sec = buf:get(structs.stat[xtim]+ 
                              structs.timespec.tv_sec, "int")
    timespec.tv_nsec = buf:get(structs.stat[xtim] + 
                               structs.timespec.tv_nsec, "int")
  elseif not structs.stat[st_xspec] == -1 then
    timespec.tv_sec = buf:get(structs.stat[st_xtime] + 1, "int")
    timespec.tv_nsec = buf:get(structs.stat[st_xspec] + 
                               structs.stat.st_mtimespec , "int")
  else 
    timespec.tv_sec = buf:get(structs.stat[st_xtime] + 1, "int")
    timespec.tv_nsec = 0
  end

  return timespec
end

local function getvalue(args)
  local libc = alien.default
  local buf = alien.buffer(structs.stat.__size)
  local rv = -1;

  if equus.p_is_darwin() == 1 then
    libc.stat64:types("int", "string", "pointer")
    rv = libc.stat64(args.path, buf:topointer())
  else
    -- #define stat(fname, buf) __xstat (_STAT_VER, fname, buf)
    libc.__xstat:types("int", "int", "string", "pointer")
    rv = libc.__xstat(0, args.path, buf:topointer())
  end

  if rv < 0 then
    error("libc.stat returned ".. rv)
  end

  local r = {}
  r.size = buf:get(structs.stat.st_size+1, "long")

  r.mtime = os.date("%H:%M:%S %Y-%m-%d", 
                    buf:get(structs.stat.st_mtime+1, "int"))
  r.atime = os.date("%H:%M:%S %Y-%m-%d", 
                    buf:get(structs.stat.st_atime+1, "int"))
  r.ctime = os.date("%H:%M:%S %Y-%m-%d", 
                    buf:get(structs.stat.st_ctime+1, "int"))

  r.mtim = get_timespec(buf, "m")
  r.atim = get_timespec(buf, "a")
  r.ctim = get_timespec(buf, "c")
  return r
end

function run(rcheck, args)
  if args.path == nil or #args.path == 0 then
    rcheck:set_error("No file set")
    return rcheck
  end

  args.path = args.path[1]

  local rv, r = pcall(getvalue, args)

  if rv then
    rcheck:add_metric('size', r.size, Check.enum.uint64)
    rcheck:add_metric('mtime', r.mtime, Check.enum.string)
    rcheck:add_metric('atime', r.atime, Check.enum.string)
    rcheck:add_metric('ctime', r.ctime, Check.enum.string)
    if not r.mtim.tv_nsec == 0 then
      rcheck:add_metric('mtime_nsec', r.mtim.tv_nsec, Check.enum.int32)
      rcheck:add_metric('atime_nsec', r.atim.tv_nsec, Check.enum.int32)
      rcheck:add_metric('ctime_nsec', r.ctim.tv_nsec, Check.enum.int32)
    end
  else
    log.err("file failed err: %s", r)
    rcheck:set_error("%s", r)
  end

  return rcheck
end
