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
local socket = require 'socket'
local string  = require 'string'
local alien = require 'alien'

function setflag(set, flag)
  if set % (2*flag) >= flag then
    return set
  end
  return set + flag
end

function set_cloexec(fd)
  if alien.platform == 'darwin' or alien.platform == 'bsd' or alien.platform == 'linux' then

    -- magic numbers are the same for darwin, bsd, and linux
    local F_GETFD = 1
    local F_SETFD = 2
    local FD_CLOEXEC = 1

    -- int fcntl(int file_descriptor, int command, (optional) int args)
    local fcntl = alien.default.fcntl
    fcntl:types("int", "int", "int", "int")

    local flags = fcntl(fd, F_GETFD, nil)

    if flags >= 0 then
      flags = setflag(flags, FD_CLOEXEC)
      flags = fcntl(fd, F_SETFD, flags)
    end

    return flags
  end
end

function sleep(sec)
  socket.select(nil, nil, sec)
end

function nicesize(b)
   local l = "B"
   if b > 1024 then
       b = b / 1024
       l = "KB"
       if b > 1024 then
           b = b / 1024
           l = "MB"
           if b > 1024 then
               b = b / 1024
               l = "GB"
           end
       end
   end
   return string.format("%.2f %2s", b, l)
end

function string.get_value_type(str)
  local value_type

  if string.find(str, '^%d+%.%d$') then
    value_type = Check.enum.double
  elseif string.find(str, '^%d+$') then
    value_type = Check.enum.int64
  elseif string.find(str, '^[%w-%d\\%?%*&]+$') then
    value_type = Check.enum.string
  else
    value_type = Check.enum.guess
  end

  return value_type
end

function add_quotes(str)
  -- Add quotes around a string.
  start_pos, _ = string.find(str, '"')
  endpos_pos, _ = string.find(str, '"')
  length = string.len(str)

  if start_pos ~= 1 then
    str = '"' .. str
  end

  if end_pos ~= length then
    str = str .. '"'
  end

  return str
end

function string_to_value_type(str)
  local value_type

  if str == 'int32' then
    value_type = Check.enum.int32
  elseif str == 'int' or str == 'int64' then
    value_type = Check.enum.int64
  elseif str == 'float' then
    value_type = Check.enum.double
  elseif str == 'gauge' then
    value_type = Check.enum.gauge
  elseif str == 'string' then
    value_type = Check.enum.string
  else
    value_type = Check.enum.guess
  end

  return value_type
end

function normalize_path(path, platform, allow_relative, add_trailing_slash)
  local newpath, slash
  local platform = platform or 'unix'
  local allow_relative = allow_relative or true
  local add_trailing_slash = add_trailing_slash or true

  if platform ~= 'unix' and platform ~= 'windows' then
    error('Invalid platform: ' .. platform)
  end

  if platform == 'unix' then
    slash = '/'
  else
    slash = '\\'
  end

  while newpath ~= path do
    if (newpath) then
      path = newpath
    end

    -- If someone has a path like /blah/../tmp/, turn that into /tmp/
    if platform == 'unix' then
      newpath = string.gsub(path, "/[^/]+/%.%./", "/")
    else
      newpath = string.gsub(path, "\\[^\\]+\\%.%.\\", "\\")
    end
  end

  if not allow_relative and slash == '/' then
    if string.sub(newpath, 1, 1) ~= slash then
      newpath = slash .. newpath
    end
  end

  if add_trailing_slash then
    len = string.len(newpath)

    if string.sub(newpath, len) ~= slash then
      newpath = newpath .. slash
    end
  end

  return newpath
end

function file_exists(path)
  local stream = io.open(path)

  if not stream then
    return false
  end

  stream:close()
  return true
end

function table.contains(table, element, element_type, compare_function)
  local element_type = element_type or 'value'
  local compare_function = compare_function or nil
  local current_value

  if compare_function == nil then
    compare_function = function(current_value, element)
      if current_value == element then
        return true
      else
        return false
      end
    end
  end

  for key, value in pairs(table) do
    if element_type == 'key' then
      current_value = key
    else
      current_value = value
    end

    if compare_function(current_value, element) then
      return true
    end
  end

  return false
end

function trim(s)
  -- from PiL2 20.4
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end

function remove_chars(s, chars)
  for _, char in ipars(chars) do
    string = string.replace(s, char, '')
  end

  return string
end

function remove_non_alphanum(s)
  return string.gsub(s, '[^%w%s.-= ]', '')
end

-- based roughly on the logic in apache's ap_getword_conf
function cmd_to_table(arg0, argstr)
  local offset = 1
  local t = {}
  table.insert(t, arg0)
  while offset <= argstr:len() do
    local ch = argstr:sub(offset, offset)
    if string.match(ch, '%s') ~= nil then

    else
      if ch == "'" or ch == '"' then
        -- inside a quote
        offset = offset + 1
        local endc = offset
        local notdone = 1
        while endc <= argstr:len() and notdone == 1 do
          local ch = argstr:sub(endc, endc)
          if ch == "'" or ch == '"'  then
            notdone = 0
          else
            endc = endc + 1
          end
        end

        if endc ~= offset then
          table.insert(t, argstr:sub(offset, endc-1))
        end

        offset = endc

      else
        -- no quotes, go to next space
        local endc = offset
        local notdone = 1
        while endc <= argstr:len() and notdone == 1 do
          local ch = argstr:sub(endc, endc+1)
          if string.match(ch, '%s') ~= nil then
            notdone = 0
          else
            endc = endc + 1
          end
        end

        if endc ~= offset then
          table.insert(t, argstr:sub(offset, endc))
        end
        offset = endc
      end

    end

    offset = offset + 1
  end
  return t
end

-- See Also: http://lua-users.org/wiki/SplitJoin
function split(str, pattern)
  pattern = pattern or "[^%s]+"
  if pattern:len() == 0 then pattern = "[^%s]+" end
  local parts = {__index = table.insert}
  setmetatable(parts, parts)
  str:gsub(pattern, parts)
  setmetatable(parts, nil)
  parts.__index = nil
  return parts
end

function log_msg(level, str)
  equus.equus_log(level, str)
end

function varargs_tostr(...)
  local s = {}
  for n=1,select('#', ...) do
    local e = select(n, ...)
    table.insert(s, tostring(e))
  end
  return table.concat(s, " ")
end

function log_msgv(level, ...)
  log_msg(level, string.format(...))
end

log_levels = {
  nothing = equus.EQUUS_LOG_NOTHING,
  critial = equus.EQUUS_LOG_CRITICAL,
  errors = equus.EQUUS_LOG_ERRORS,
  warnings = equus.EQUUS_LOG_WARNINGS,
  info = equus.EQUUS_LOG_INFO,
  debug = equus.EQUUS_LOG_DEBUG,
  everything = equus.EQUUS_LOG_EVERYTHING,
  all = equus.EQUUS_LOG_EVERYTHING
}


log = {
  crit = function (...)
    log_msgv(equus.EQUUS_LOG_CRITICAL, ...)
  end,
  err = function (...)
    log_msgv(equus.EQUUS_LOG_ERRORS, ...)
  end,
  msg = function (...)
    log_msgv(equus.EQUUS_LOG_INFO, ...)
  end,
  info = function (...)
    log_msgv(equus.EQUUS_LOG_INFO, ...)
  end,
  dbg = function (...)
    log_msgv(equus.EQUUS_LOG_DEBUG, ...)
  end}




Check = {}
Check.__index = Check

function Check.create()
   local tbl = {}             -- our new object
   setmetatable(tbl, Check)
   tbl.checks = {}
   tbl.availability = 'A'
   tbl.state = 'G'
   tbl.status = ''
   return tbl
end

function Check:bad()
  self.state = 'B'
end

function Check:good()
  self.state = 'G'
end

function Check:available()
  self.availability = 'A'
end

function Check:unavailable()
  self.availability = 'U'
end

function Check:unreachable()
  self.availability = 'N'
end

function Check:set_error(...)
  self.status = string.format(...)
  self:bad()
  self:unavailable()
end

function Check:set_status(...)
  self.status = string.format(...)
end

function Check:add_metric(name, value, xt)
  local t = {}
  t.type = xt
  t.name = name
  t.value = value
  table.insert(self.checks, t)
end

function Check:remove_metric(name)
  for i, v in ipairs(self.checks) do
    if v.name == name then
      table.remove(self.checks, i)
      return
    end
  end
end

function Check:set_state_avail(avail, state)
  self.availability = avail
  self.state = state
end

function Check:pull_and_compare_error(name, op, args, compare_type)
  local compare_type = compare_type or "error"
  local avail, state, val

  if type(args) == 'table' then
    val = args[name]
  elseif type(args) == 'string' or type(args) == 'number' then
    val = args
  end

  if val == nil then
    return false
  end

  if type(val) == 'table' then
    val = tonumber(val[1])
  elseif type(val) == 'string' or type(val) == 'number' then
    val = tonumber(val)
  end

  if compare_type == "warning" then
    avail = "A"
    state = "B"
  elseif compare_type == "error" then
    avail = "U"
    state = "B"
  else
    error('Invalid compare_type: ' .. compare_type)
  end

  local rv, r =self:compare_metric(name, op, val, avail, state)
  return rv
end

function Check:compare_metric(name, op, value, avail, state)
  local found = false
  -- Check if the value is null
  if value == nil then
    return found
  end
  -- Make sure to not compare if the assigned avail and state are not
  -- present
  if avail == nil or state == nil then
    return found
  end
  for i, v in ipairs(self.checks) do
    if v.name == name then
      found = true
      if op == Check.op.GT then
        if v.value > value then
          self:set_state_avail(avail, state)
          self:set_status("%s of %.2f is greater than %.2f", name, v.value, value)
        end
      elseif op == Check.op.LT then
        if v.value < value then
          self:set_state_avail(avail, state)
          self:set_status("%s of %.2f is less than %.2f", name, v.value, value)
        end
      elseif op == Check.op.GTE then
        if v.value < value then
          self:set_state_avail(avail, state)
          self:set_status("%s of %.2f is greater than or equal to %.2f", name, v.value, value)
        end
      elseif op == Check.op.LTE then
        if v.value < value then
          self:set_state_avail(avail, state)
          self:set_status("%s of %.2f is less than or equal to %.2f", name, v.value, value)
        end
      elseif op == Check.op.EQ then
        if v.value < value then
          self:set_state_avail(avail, state)
          self:set_status("%s of %.2f is equal to %.2f", name, v.value, value)
        end
      elseif op == Check.op.NEQ then
        if v.value < value then
          self:set_state_avail(avail, state)
          self:set_status("%s of %.2f is not equal to %.2f", name, v.value, value)
        end
      end
    end
  end
  return found
end

Check.op = {
  GT = 0,
  LT = 1,
  GTE = 2,
  LTE = 3,
  EQ = 4,
  NEQ = 5
}

Check.enum = {
  guess = '0',
  int32 = 'i',
  uint32 = 'I',
  int64 = 'l',
  uint64 = 'L',
  double = 'n',
  string = 's',
  gauge = 'G'
 }


trusted_ca_certs = {
[[-----BEGIN CERTIFICATE-----
MIID4jCCAsygAwIBAgIBATALBgkqhkiG9w0BAQUwgYQxCzAJBgNVBAYTAlVTMRMw
EQYDVQQIEwpDYWxpZm9ybmlhMRYwFAYDVQQHEw1TYW4gRnJhbmNpc2NvMRgwFgYD
VQQKEw9DbG91ZGtpY2ssIEluYy4xETAPBgNVBAsTCFNlcnZpY2VzMRswGQYDVQQD
ExJDbG91ZGtpY2sgU2VydmljZXMwHhcNMTAwMTI0MjIyNTUwWhcNMzAwMTI0MjIy
NTUwWjCBhDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCkNhbGlmb3JuaWExFjAUBgNV
BAcTDVNhbiBGcmFuY2lzY28xGDAWBgNVBAoTD0Nsb3Vka2ljaywgSW5jLjERMA8G
A1UECxMIU2VydmljZXMxGzAZBgNVBAMTEkNsb3Vka2ljayBTZXJ2aWNlczCCAR8w
CwYJKoZIhvcNAQEBA4IBDgAwggEJAoIBAK7hi/h2RCUveZhrrCYSaJyLzXpmkdcZ
rdAswyyEFhxlDPgVXzKayoB3DokuUqUcJ85dvASihQ6MXcYZsRO2jVnSWegRDfAp
LBaqluk0W9Ed/9PTC7bO0gCB3pqwvBWaLoTI/nuzf51KwhJ4kU0BoRxUklYLm+BN
U1Os8JxTKP7g0AplAZXU8daLTlZvfMTHV5cd/S1l8OvJPVditTWN66nlMYB5haif
INLKe6oicD3O4C54RW+tf2K5nvrRLqWCgZnj41iQl1N5TXjrqnKHIyVKyBy4z+wW
M4Nk7ZdElMVORuXjinVTUFUJnl56eH4foz1zHAWCFCpv9SDQONrv3MECAwEAAaNk
MGIwDwYDVR0TAQH/BAUwAwEB/zAPBgNVHQ8BAf8EBQMDBwYAMB0GA1UdDgQWBBSu
SaNtPsOBzjHJFnhQC9m0RbycHDAfBgNVHSMEGDAWgBSuSaNtPsOBzjHJFnhQC9m0
RbycHDALBgkqhkiG9w0BAQUDggEBACGi92lkFVRjXf/cth7LZesqdWV60EYzP4HP
Br1GZ7xGRdJio6pdjwI2senLKbW1eVRjm0aXOdoKS57EzjdeAqhRGYYt5aKiq225
/cmcpjsWx/gd7icREccjUyWIbGFv0GEua0l+eC8Dtg1c/+SBExlU9yw81ySAHhfR
TW6p4nVmqKVUtojDc5P6pv5QptkIbXMO083qshr5hdx6e3N57F/eJHrq/g7SA7DV
8ryCqCfKTPfoS7qModP1q2X8kCOIxK8Q5ttkz0dhNCtxoACvp19lD+4mcOLFCb+v
TtCLIhv3eJ8ylli9XW5QmLI7COb08aRAqjBjIPMgW9dFR3R/308=
-----END CERTIFICATE-----]],
[[-----BEGIN CERTIFICATE-----
MIIBnzCCAQgCCQCidv3z8sGW3DANBgkqhkiG9w0BAQUFADAUMRIwEAYDVQQDEwls
b2NhbGhvc3QwHhcNMDkwMTI2MjE0MzIwWhcNMTkwMTI0MjE0MzIwWjAUMRIwEAYD
VQQDEwlsb2NhbGhvc3QwgZ8wDQYJKoZIhvcNAQEBBQADgY0AMIGJAoGBAMup89QK
q8LFoaY4anq9LBiytIXau3LdyWbpF6G8B2O5CvZUzbIR+IG4rRycIU9CJMzxwvCO
5mYmmQaAato9zVHgMlhLdWV3kvp63h+xccEMqyTGSLNAl86ThGCuVAsR39kzTTG3
j5IdxImd03D38dzB7Emu8cwC/bxio7KHW24bAgMBAAEwDQYJKoZIhvcNAQEFBQAD
gYEAfL5REWbC2TVvAqifMhptbDczc0Q8GbR8hH+JOVxF5oxWJVu6nQOt4X2I34TG
eU/esHoxEpnuxatDV9i3SdjFiwmLSpv8GHc94cxc8IeCwO4IgpmoQiJw9kPUsWtm
3tYSHP0PlbAwEmCd0z8jZ25mRkMGkT1PsyaTUO0ow6bXht8=
-----END CERTIFICATE-----]],
}
