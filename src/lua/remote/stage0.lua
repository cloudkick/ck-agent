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
local socket = require 'socket'
local log = util.log
local lanes = require "lanes"
local alien = require "alien"
local helen = require 'helen'

function string:rfind(char)
  local i = self:len()
  while i >= 1 do
      if self:sub(i, i) == char then
        return i
      end
      i = i - 1
  end
  return -1
end

local function appname()
  local basename = equus.equus_get_argv(0)
  if equus.p_is_windows() == 1 then
    basename = basename:sub(basename:rfind('\\')+1)
  else
    basename = basename:sub(basename:rfind('/')+1)
  end
  return basename
end

function version_str()
  return "".. equus.EQUUS_VERSION_MAJOR ..".".. equus.EQUUS_VERSION_MINOR ..".".. equus.EQUUS_VERSION_PATCH
end

function log_version()
  log.msg(appname() .." version %s", version_str())
end

function log_original_command()
  local s = {}
  for i=0,equus.equus_get_argc()-1 do
     table.insert(s, equus.equus_get_argv(i))
  end
  log.msg('Launch Command: %s', table.concat(s, ' '))
end


local function detach()
  local rv=nil
  local err=nil
  local merr=nil
  local EXIT_FAILURE=1
  -- rough port of apr_proc_detach
  local libc = alien.default
  -- The chdir() is expected to conform to IEEE Std 1003.1-1988 (``POSIX.1'').
  libc.chdir:types("int", "string")
  -- fork() function call appeared in Version 6 AT&T UNIX.
  libc.fork:types("int")
  -- The setsid function is expected to be compliant with the IEEE Std 1003.1-1988 (``POSIX.1'') specification.
  libc.setsid:types("int")
  -- The setpgid() function conforms to IEEE Std 1003.1-1988 (``POSIX.1'').
  libc.setpgid:types("int", "int", "int")
  libc.exit:types("void", "int")
  libc.strerror:types("string", "int")

  rv = libc.chdir("/")
  if (rv <= -1) then
    err = alien.errno()
    merr = libc.strerror(err)
    log.crit("chdir('/') returned -1: errno=(%d) %s", err, merr)
    libc.exit(EXIT_FAILURE)
  end

  rv = libc.fork()
  if (rv <= -1) then
    err = alien.errno()
    merr = libc.strerror(err)
    log.crit("fork() returned -1: errno=(%d) %s", err, merr)
    libc.exit(EXIT_FAILURE)
  elseif (rv > 0) then
    -- this is the parent process
    libc.exit(0)
  else
    -- child
    rv = libc.setsid()
    if (rv <= -1) then
      err = alien.errno()
      merr = libc.strerror(err)
      log.crit("libc.setsid() returned -1: errno=(%d) %s", err, merr)
      libc.exit(EXIT_FAILURE)
    end
    equus.equus_shutdown_stdio()
  end
end

function write_pidfile(path)
  local libc = alien.default
  libc.getpid:types("int")
  local pid = libc.getpid()
  local fd = assert(io.open(path, "w"))
  fd:write(tostring(pid))
  fd:close()
end

function print_help()
  print(appname() ..' - Monitoring Agent by Cloudkick')
  print('')
  print('Usage: '.. appname() ..' <options>')
  print('')
  print('Options:')
  if equus.p_is_windows() == 1 then
     print('    --config|-c <path>   Path to Config File [default: '.. os.getenv("ProgramFiles") ..'\\Cloudkick Agent\\etc\\cloudkick.cfg]')
     -- these are pre-processed in equus.c:main()
     print('    --noservice          Do not start as Windows Service (default: start as service)')
     print('    --install            Install Windows Service')
     print('    --delete             Delete Windows Service')
     print('    --start              Start Windows Service')
     print('    --stop               Stop Windows Service')
     print('    --status             Status of Windows Service')
     -- these are pre-processed in equus.c:main()
     print('    --log|-l <path>      Path to Log File [default: Windows Event Logger, "-" for testing]')
  else
     print('    --config|-c <path>   Path to Config File [default: /etc/cloudkick.conf]')
     print('    --daemon|-d          Daemonize process')
     print('    --log|-l <path>      Path to Log File [default: /var/log/'.. appname() .. '.log]')
  end
  print('    --loglevel <ll>      Verbosity of logging. [default: info]')
  if equus.p_is_windows() == 0 then
    print('    --pid|-p <path>      Path to write file with process ID')
  end
  print('    --help|-h            Show this help page')
  print('')
end

function process_argv(conf)
  local skiparg = false
  for i=1,equus.equus_get_argc()-1 do
    local v = equus.equus_get_argv(i)
    if skiparg then
      -- noop
      skiparg = false
    elseif (v == "--help" or v == "-h") then
      print_help()
      return false
    -- TODO: check in win32
    elseif (v == "--daemon" or v == "-d") then
      conf.deamonize = true
    -- TODO: check in win32
    elseif (v == "--pid" or v == "-p") then
      conf.pid_file = equus.equus_get_argv(i+1)
      skiparg = true
    elseif (v == "--log" or v == "-l") then
      conf.log_file = equus.equus_get_argv(i+1)
      skiparg = true
    elseif (v == "--loglevel") then
      conf.log_level = equus.equus_get_argv(i+1)
      skiparg = true
    -- TODO: check in win32
    elseif (v == "--config" or v == "-c") then
      conf.config_file = equus.equus_get_argv(i+1)
      skiparg = true
    else
      if (v == "--install" or
          v == "--delete" or
          v == "--start" or
          v == "--status" or
          v == "--stop" or
          v == "--noservice") then
      else
        print('Unknown command: '.. v)
        print('')
        print_help()
        return false
      end
    end
  end
  return true
end

function mergeConfTables(t1, t2)
  for k,v in pairs(t2) do
    if v ~= nil then
      t1[k] = v
      --log.crit("merge: %s = %s", k, v)
    end
  end
  return t1
end

function loadconf(filename)
    -- returns a table with a files contents
    local function trim(s)
      -- from PiL2 20.4
      return (s:gsub("^%s*(.-)%s*$", "%1"))
    end
    local c = {}
    for line in io.lines(filename) do
        if string.sub(line, 1, 1) ~= "#" then
            local a,b = string.find(line, "(%s+)")
            if a ~= nil then
                local key = trim(string.sub(line, 1, a))
                local value = trim(string.sub(line, b))
                if key ~= nil and string.len(key) > 0 and value ~= nil and string.len(value) > 0 then
                  c[key] = value
                  --log.crit("conf: %s = %s", key, value)
                end
            end
        end
    end
    return c
end

local global_conf = {}
function pick_config()
  if equus.p_is_windows() == 1 then
    return os.getenv("ProgramFiles") .."\\Cloudkick Agent\\etc\\cloudkick.cfg"
  else
    return "/etc/cloudkick.conf"
  end
end

function load_config_defaults()
  -- set some defaults.
  local conf = {}

  conf.deamonize = nil
  conf.config_file = pick_config()
  conf.pid_file = nil
  conf.log_file = nil

  if process_argv(conf) == false then
    return
  end

  if conf.config_file ~= nil then
    local cf, err = pcall(loadconf, conf.config_file)
    if not cf and err then
      log.crit("Unable to load config: %s", err)
      return
    end
    conf = mergeConfTables(err, conf)
  end

  if conf.log_level == nil then
    conf.log_level = "info"
  end

  if conf.oauth_key == nil then
    log.crit("oauth_key missing from configuration file: %s", conf.config_file)
    log.crit("Did you run cloudkick-config?")
    log.crit("For support please visit https://support.cloudkick.com/Agent")
    return
  end

  if conf.oauth_secret == nil then
    log.crit("oauth_secret missing from configuration file: %s", conf.config_file)
    log.crit("Did you run cloudkick-config?")
    log.crit("For support please visit https://support.cloudkick.com/Agent")
    return
  end

  if conf.endpoint == nil then
    conf.endpoint = "agent-endpoint.cloudkick.com"
  end

  if conf.endpoint_port == nil then
    conf.endpoint_port = 4166 -- Joost Peer to Peer Protocol -- Thanks Colm!
  end

  if conf.node_id_file == nil then
    conf.node_id_file = "/var/lib/cloudkick-agent/node_id"
  end

  if conf.log_file == nil then
    if conf.deamonize == true then
      conf.log_file = "/var/log/".. appname() ..".log"
    end
  end

  -- ping_interval: 10 minute max, 30 sec min, 10 minute default
  if conf.ping_interval == nil then
    conf.ping_interval = 600
  else
    conf.ping_interval = math.max(math.min(tonumber(conf.ping_interval), 600), 30)
  end

  if util.log_levels[conf.log_level] == nil then
    log.crit("Unknown log level '%s'", conf.log_level)
    local ll = {}
    for k,v in pairs(util.log_levels) do table.insert(ll, k) end
    log.crit("Valid log levels: %s", table.concat(ll, ', '))
    log.crit("For support please visit https://support.cloudkick.com/Agent")
    return
  end

  equus.equus_log_level_set(util.log_levels[conf.log_level])

  if conf.log_file ~= nil then
    local rv = equus.equus_log_set_path(conf.log_file)
    if rv ~= 0 then
      log.crit("Failed to setup logfile. Exiting.")
      log.crit("For support please visit https://support.cloudkick.com/Agent")
      return
    end
  end

  if equus.p_is_windows() == 1 then
    platform = 'windows'
  else
    platform = 'unix'
  end

  if conf.local_plugins_path == nil then
    if platform == 'windows' then
      conf.local_plugins_path = os.getenv("ProgramFiles") .."\\Cloudkick Agent\\plugins\\"
    else
      conf.local_plugins_path = "/usr/lib/cloudkick-agent/plugins/"
    end
  else
    conf.local_plugins_path = util.normalize_path(conf.local_plugins_path, platform,
                                                  true, true)
  end

  if conf.munin_plugins_path == nil then
    conf.munin_plugins_path = conf.local_plugins_path
  else
    conf.munin_plugins_path = util.normalize_path(conf.munin_plugins_path, platform,
                                                  true, true)
  end

  global_conf = conf
  return conf
end

function run()
  local conf = nil
  conf = load_config_defaults()

  if not conf then
    return
  end

  if equus.g_equus_run_count <= 1 then
    if conf.deamonize == true then
      log.dbg("Starting to detach")
      detach()
    end

    if conf.pid_file ~= nil then
      log.dbg("Writing pid file")
      write_pidfile(conf.pid_file)
    end
  else
    log.info("Restarting...")
  end

  global_conf = conf

  log_version()
  log_original_command()
  while equus.equus_restart_get() == 0 do
    log.dbg('calling runloop()')
    helen.run_loop()
  end
end

local checks = {}
local run_once = 1

function periodic()
  log.dbg(""..#(checks).." checks active")
  --collectgarbage("collect")
  if run_once == 1 then
    -- run_check('disk')
    run_once = 0
  end

  local a = {}
  -- run_check('cpu', a, a)
  --run_check('io', a, a)

  for i,v in ipairs(checks) do
    local l = v.lane
    if l.status == "pending" then
      log.dbg ('task pending')
    elseif l.status == "running" then
      log.dbg ('task running')
    elseif l.status == "waiting" then
      log.dbg ('task waiting')
    else
      log.dbg ('task done')
      -- r = l[1]
      l:join()
      table.remove(checks, i)
    end
  end

  collectgarbage()

end

function run_check(name, token, payload)

  local checkname = 'check_'.. name
  local func = lanes.gen(function(wkfd, checkname, token, payload)
    local util = require 'util'
    local log = util.log
    log.dbg("in the lane for %s", checkname)

    local Check = util.Check
    local alien = require 'alien'
    local rv, err, check

    local function prep_result(checkname, rv)
      local Json = require 'Json'
      local data = Json.Encode(rv)
      local l = string.len(data)
      local s = "result ".. checkname .. " ".. token .." ".. l .. "\r\n".. data .. "\r\n"
      return s
    end

    local check_obj = Check.create()
    rv, check = pcall(require, checkname)
    if not rv then
      log.err("check failed to load: ".. check)
      check_obj:set_error(check)
    else
      check.conf = {}
      check.conf.local_plugins_path = global_conf.local_plugins_path
      check.conf.munin_plugins_path = global_conf.munin_plugins_path

      rv, err = pcall(check.run, check_obj, payload)
      if not rv then
        log.err("check failed pcall: ".. err)
        check_obj:set_error(err)
      end
    end


    rv = prep_result(checkname, check_obj)
    equus.equus_push_result(rv, string.len(rv));
    if equus.p_is_windows() == 1 then
--      local wakeup_pipe,err = socket.connect(helen.wakeup_pipe_ip, helen.wakeup_pipe_port)
--      if err ~= nil then
--        log.err("wakeup_pipe connect: %s", err)
--      end
--      wakeup_pipe.close()
    else
      log.dbg("writing wakeup_pipe")
      local libc = alien.default
      local buf = alien.array("char", 1)
      buf[1] = '1'
      libc.write:types("int", "int", "pointer", "int")
      local rv = libc.write(wkfd, buf.buffer, 1)
    end
    return nil
  end)


  local t
  if equus.p_is_windows() == 1 then
    t = {lane=func(nil, checkname, token, payload), name=checkname}
  else
    t = {lane=func(helen.wakeup_pipe:getfd(), checkname, token, payload), name=checkname}
  end
  table.insert(checks, t)

end

function helen_host()
  if global_conf.redirect_endpoint ~= nil then
    return global_conf.redirect_endpoint
  end
  return global_conf.endpoint
end

function redirect_helen_host(dest)
  global_conf.redirect_endpoint = dest
end

function helen_port()
  return global_conf.endpoint_port
end

function helen_key()
  return global_conf.oauth_key
end

function helen_secret()
  return global_conf.oauth_secret
end

function helen_config_file()
  return global_conf.config_file
end

function helen_ping_interval()
  return global_conf.ping_interval
end

function local_plugins_path()
  return global_conf.local_plugins_path
end

function munin_plugins_paths()
  return global_conf.munin_plugins_path
end
