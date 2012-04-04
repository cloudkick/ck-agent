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
local http = require("socket.http")
local io = require 'io'
local os = require 'os'

local jmxquery_older_versions = { '1.0' }
local jmxquery_current_version = '1.1'
local jmxquery_url = equus.equus_url().. 'jmxquery-' .. jmxquery_current_version .. '.jar'
local jmxquery_sig_url = equus.equus_url().. 'jmxquery-' .. jmxquery_current_version .. '.sig'

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

local function get_metrics(jmxquery_path, hostname, port, username, password,
                           object_name, attribute_name, attribute_keys)
  local cmd = {'java',
               '-classpath',
               jmxquery_path,
               'jmxquery.JMXQuery',
               '-U',
               'service:jmx:rmi:///jndi/rmi://'.. hostname ..':'.. port ..'/jmxrmi',
               '-O',
               object_name,
               '-A',
               attribute_name}

  if username then
    table.insert(cmd, '-username')
    table.insert(cmd, username)
  end

  if password then
    table.insert(cmd, '-password')
    table.insert(cmd, password)
  end

  if attribute_keys then
    table.insert(cmd, '-K')
    table.insert(cmd, attribute_keys)
  end

  log.dbg('jmx command: %s', table.concat(cmd, " "))

  local p,rc

  if equus.p_is_windows() == 1 then
    p,rc = equus_exec_call_win32(cmd)
  else
    p,rc = equus_exec_call_unix_core(cmd)
  end

  return p,rc
end

local function get_jmxquery_path(version)
  local version = version or jmxquery_current_version
  local filename = 'jmxquery-' .. version .. '.jar'
  local path = nil

  if equus.p_is_windows() == 1 then
    path = os.getenv("ProgramFiles") ..'\\Cloudkick Agent\\'
  else
    path = '/usr/lib/cloudkick-agent/'
  end

  return path .. filename
end

local function download_jmxquery(delete_older_versions)
  local delete_older_versions = delete_older_versions or true
  local file_path = get_jmxquery_path()
  local path, rv

  local sig,sigc,h = http.request(jmxquery_sig_url)
  assert(sig ~= nil, "jmxquery: Signature is null")
  assert(sigc ~= "200", "jmxquery: Signature http code is not 200")

  local data,datac,h =  http.request(jmxquery_url)
  assert(data ~= nil, "jmxquery: Data is null")
  assert(datac ~= "200", "jmxquery: Data http code is not 200")

  local rc = equus.equus_verify(data, data:len(), sig, sig:len(), "", 0)
  assert(rc == 0, "jmxquery from "..jmxquery_url.." signature validation failed")

  --log.info('jmxquery: signature verify result: '.. rc)
  --log.info('jmxquery: downloaded bytes: '.. data:len())

  local fp = assert(io.open(file_path, 'wb'))
  fp:write(data)
  fp:close()

  if delete_older_versions then
    for _, version in ipairs(jmxquery_older_versions) do
      path = get_jmxquery_path(version)

      if util.file_exists(path) then
        rv = os.remove(path)
        -- log.info('jmxquery: deleted old version ' .. version .. ' - ' .. tostring(rv))
      end
    end
  end

  return true
end

function run(rcheck, args)
  if args.hostname == nil then
    args.hostname = 'localhost'
  else
    args.hostname = args.hostname[1]
  end

  if args.username == nil then
    args.username = nil
  else
    args.username = args.username[1]
  end

  if args.password == nil then
    args.password = nil
  else
    args.password = args.password[1]
  end

  if args.port == nil then
    rcheck:set_error('port is required for JMX check')
    return rcheck
  else
    args.port = args.port[1]
  end

  if args.object_name == nil then
    rcheck:set_error('object_name is required for JMX check')
    return rcheck
  else
    args.object_name = args.object_name[1]
  end

  if args.attribute_name == nil then
    rcheck:set_error('attribute_name is required for JMX check')
    return rcheck
  else
    args.attribute_name = args.attribute_name[1]
  end

  if args.attribute_keys == nil then
    args.attribute_keys = nil
  else
    args.attribute_keys = args.attribute_keys[1]
  end

  -- Download the jmxquery.jar file if it's not already present
  local jmxquery_path = get_jmxquery_path()
  if not util.file_exists(jmxquery_path) then
    log.info('jmxquery.jar not found, trying to download it from %s', jmxquery_url)

    if not download_jmxquery() then
      log.crit('downloading jmxquery.jar failed')
      rcheck:set_error('JMX check failed: failed to download jmxquery.jar')
    return rchek
    end
  end

  local rv, r, rc = pcall(get_metrics, jmxquery_path, args.hostname, args.port,
                          args.username, args.password, args.object_name,
                          args.attribute_name, args.attribute_keys)

  if rv and rc == 0 then
   rcheck.output = r
  else
   if rc ~= 0 and rc ~= nil then
     r = string.format("exit code: %d output: %s", rc, tostring(r))
   end
   log.err("err from jmx plugin: %s", tostring(r))
   rcheck:set_error("%s", tostring(r))
  end
  return rcheck
end
