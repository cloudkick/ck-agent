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
local nicesize = util.nicesize
local io = require 'io'

local function sigar_net_interface_stat(args)
  -- Issues: (rand) interfaces are eth0-eth7, not clear which....
  --         (rand) sigar looks to be the culprit for the huge mem leaks
  local si = equus.sigar_create()
  assert(si)
  local ni = equus.sigar_net_interface_stat_t()
  log.dbg("calling sigar_net_interface_stat_get(%s)", args.if_name)
  local r = {}
  r["in_packets"] = 0
  local rv = equus.sigar_net_interface_stat_get(si, args.if_name, ni)
  if rv == 0 then
    --ni.rx_dropped))
    --ni.rx_overruns))
    --ni.rx_frame))
    --ni.tx_dropped))
    --ni.tx_overruns))
    --tostring(ni.tx_collisions))
    --ni.tx_carrier))
    --ni.speed))
    r["in_bytes"] = ni.rx_bytes
    r["in_packets"] = ni.rx_packets
    r["in_err"] = ni.rx_errors
    r["in_mcast"] = 0
    r["out_bytes"] = ni.tx_bytes
    r["out_packets"] = ni.tx_packets
    r["out_err"] = ni.tx_errors
    log.dbg("in_packets " .. tostring(r["in_packets"]))
    log.dbg("in_bytes " .. tostring(r["in_bytes"]))
    log.dbg("out_packets " .. tostring(r["out_packets"]))
    log.dbg("out_bytes " .. tostring(r["out_bytes"]))
  end

  equus.sigar_destroy(si)

  return r
end

local function readdos(cmd)
  local f = nil
  f = assert(io.popen(cmd, 'r'))
  local s = assert(f:read('*l'))
  s = assert(f:read('*l'))
  s = assert(f:read('*l'))
  s = assert(f:read('*l'))
  local bytes = assert(f:read('*l'))
  local packets = assert(f:read('*l'))
  local mcast = assert(f:read('*l'))
  s = assert(f:read('*l'))
  local err = assert(f:read('*l'))
  f:close()
  in_bytes = string.gsub(bytes, "[^%d]+(%d+).*", "%1")
  out_bytes = string.gsub(bytes, "[^%d]+%d+%s+(%d+).*", "%1")
  if equus.p_is_darwin() == 1 then
      args.if_name = 'en1'
    end
  in_packets = string.gsub(packets, "[^%d]+(%d+).*", "%1")
  out_packets = string.gsub(packets, "[^%d]+%d+%s+(%d+).*", "%1")
  in_mcast = string.gsub(mcast, "[^%d]+(%d+).*", "%1")
  out_mcast = string.gsub(mcast, "[^%d]+%d+%s+(%d+).*", "%1")
  in_err = string.gsub(err, "[^%d]+(%d+).*", "%1")
  out_err = string.gsub(err, "[^%d]+%d+%s+(%d+).*", "%1")
  local r = {}
  r["in_bytes"] = tonumber(in_bytes)
  r["in_packets"] = tonumber(in_packets)
  r["in_err"] = tonumber(in_err)
  r["in_mcast"] = tonumber(in_mcast)
  r["out_bytes"] = tonumber(out_bytes)
  r["out_packets"] = tonumber(out_packets)
  r["out_err"] = tonumber(out_err)
  r["out_mcast"] = tonumber(out_mcast)
  return r
end

local function readproc(args)
  -- See proc(5):
  --     <http://www.kernel.org/doc/man-pages/online/pages/man5/proc.5.html>
  local r = {}
  local i = 0
  file = assert(io.open("/proc/net/dev", "r"))
  for line in file:lines() do
    i = i + 1
    if i > 2 then
        local l = util.split(line)
        local name = l[1]:sub(1, l[1]:find(':')-1)
        -- linux sometimes does this:
        -- eth0:6832715943
        -- (see, no whitespace between the interface and the first number. yay.)
        if string.len(l[1]) ~= l[1]:find(':') then
            table.insert(l, 2, l[1]:sub(l[1]:find(':')+1))
        end
        if l[11] ~= '0' and name == args.if_name then
          r["in_bytes"] = tonumber(l[2])
          r["in_packets"] = tonumber(l[3])
          r["in_err"] = tonumber(l[4])
          r["in_mcast"] = tonumber(l[9])
          r["out_bytes"] = tonumber(l[10])
          r["out_packets"] = tonumber(l[11])
          r["out_err"] = tonumber(l[12])
        end
    end
  end
  file:close()
  return r
end

local function getvalue(args)
  local a

  if equus.p_is_windows() == 1 or equus.p_is_darwin() == 1 then
    a = readdos('netstat -e')
--    a = sigar_net_interface_stat(args)
--  elseif equus.p_is_freebsd() == 1 then
--    a = sigar_net_interface_stat(args)
  else
    a = readproc(args)
  end

  return a
end

function run(rcheck, args)
  if equus.p_is_windows() == 0 and
     equus.p_is_linux() == 0 and
     equus.p_is_darwin() == 0 then
    rcheck:set_error("net check is only supported on windows, linux and freebsd")
    return rcheck
  end

  if args.if_name == nil then
    if equus.p_is_windows() == 1 then
      args.if_name = 'unknown'
    end
    if equus.p_is_linux() == 1 then
      args.if_name = 'eth0'
    end
    if equus.p_is_darwin() == 1 then
      args.if_name = 'en1'
    end
  else
    args.if_name = args.if_name[1]
  end

  local rv, r = pcall(getvalue, args)
  if rv then
    if r['in_packets'] ~= nil then
      for k,v in pairs(r) do
        rcheck:add_metric(k, v, Check.enum.gauge)
      end
      rcheck:set_status('interface %s in/out:%s/%s, in/out packets:%s/%s',
          args.if_name, nicesize(tonumber(r["in_bytes"])), nicesize(tonumber(r["out_bytes"])),
	  r['in_packets'], r['out_packets'])
    else
      rcheck:set_error('interface %s not found or missing traffic', args.if_name)
      log.err("didn't find data for interface %s", args.if_name)
    end
  else
    rcheck:set_error('interface %s not found', args.if_name)
    log.err("net failed err: %s", tostring(r))
  end

  return rcheck
end
