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

-- Connect out to the edge service 
--

module(..., package.seeall);
local socket = require('socket')
local ssl = require 'ssl'
local sslcontext = require 'ssl.context'
local alien = require 'alien'
local state0 = require('stage0')
local util = require 'util'
local Json = require 'Json'
local log = util.log
local set_cloexec = util.set_cloexec

-- single connection to the helen upstream
local client_skt = nil
-- my side of pipe used to break out of select()
local my_pipe = nil
-- pipe used by workers to break out of select()

wakeup_pipe = nil
wakeup_pipe_ip = nil
wakeup_pipe_port = nil
local connect_delay = 0
local last_ping_time = 0
local count_ping_sent = 0
local count_pong_got = 0

function connect(host, port)
  local params = {
        mode = "client",
        protocol = "tlsv1",
        verify = "peer"
        }
  if client_skt ~= nil then
    client_skt:close()
  end
  ip, more = socket.dns.toip(host)

  if ip == nil then
    log.crit("Unable to resolve %s to an IP address: %s", host, more)
    error("Unable to resolve hostname to IP")
  end

  log.dbg("socket.connect(%s, %d)", ip, port)
  client_skt,err = socket.connect(ip, port)
  if client_skt then
    client_skt:setoption('keepalive', true) -- we dont wanna have to use pongs all the time
    client_skt:setoption('tcp-nodelay', true) -- we write full buffers.

    local ret = set_cloexec(client_skt:getfd())
    if ret and ret >= 0 then
      log.dbg('fcntl - set FD_CLOEXEC flag')
    else
      log.dbg('fcntl - set FD_CLOEXEC failed or not supported')
    end

    local sctxt = ssl.newcontext(params)
    for i,v in ipairs(util.trusted_ca_certs) do
      local succ, msg = sslcontext.loadcert_mem(sctxt, v)
      if not succ then
        error("error loading trusted cert ".. tostring(i) .. ": ".. msg)
      end
    end
    client_skt = ssl.wrap(client_skt, sctxt)
    client_skt:settimeout(30)
    local succ, msg
    while not succ do
      succ, msg = client_skt:dohandshake()
      if msg == 'wantread' then
         socket.select({client_skt}, nil)
      elseif msg == 'wantwrite' then
         socket.select(nil, {client_skt})
      elseif msg == nil then
        -- do nothing.
      else
         -- other error
        error("SSL connection error: ".. msg)
      end
    end
    cmd_hello(client_skt)
  else
    log.crit("Unable to connect to %s:%d: %s", host, port, err)
    error("Failed to connect to Helen")
  end
end

function cmd_hello(skt)
  skt:send('hello 1 '.. state0.version_str().. ' '.. stage0.helen_key() ..' '.. stage0.helen_secret()..'\n')
end

function cmd_ping(skt)
  skt:send('ping '.. socket.gettime() ..'\n')
  count_ping_sent = count_ping_sent + 1
end

function split_whitespace(str)
  local t = {}
  for word in str:gmatch("%S+") do table.insert(t, word) end
  return t
end

function handle_line(skt, line)
  local arr = split_whitespace(line)
  if #arr == 0 then
    log.err("unable to parse empty line")
    return
  end

  log.dbg("cmd=%s", arr[1])
  if arr[1] == "run_check" then
    if #arr ~= 4 then
      log.err("invalid params for run_check")
      return
    end

    local token = arr[2]
    local check = arr[3]
    local payload_len = tonumber(arr[4])

    local payload, err, partial = skt:receive()
    if err then
      log.err("got err reading payload: %s", err)
      return
    end

    log.info("check=%s token=%s payload_len=%d payload=%s", check, token, payload_len, payload)
    payload = Json.Decode(payload)

    stage0.run_check(check, token, payload)

  end

  if arr[1] == "error" then
    log.crit("helen: %s", table.concat(arr, " "))
    return
  end

  if arr[1] == "restart" then
    equus.equus_restart_set(1)
    return
  end

  if arr[1] == "pong" then
    if #arr ~= 2 then
      log.err("invalid params for pong")
      return
    end
    count_pong_got = count_pong_got + 1
    ptime = socket.gettime() - tonumber(arr[2])
    log.info('ping=%f', ptime)
    return
  end

  if arr[1] == "redirect" then
    if #arr ~= 2 then
      log.err("invalid params for redirect")
      return
    end
    stage0.redirect_helen_host(arr[2])
    return
  end

  if arr[1] == "accepted" then
    connect_delay = 0
    return
  end
end


function timertick(n, jitter)
  local max = 1800
  n = math.min(n, max) + (jitter * math.random())
  return n
end

function backoff_timer()
  connect_delay = timertick(connect_delay, 7)
  return connect_delay
end

function reconnect()
  while 1 == 1 do
    local t = backoff_timer()
    log.info("Connecting to %s:%d in %f seconds", stage0.helen_host(), stage0.helen_port(), t)
    socket.select({}, {}, t)
    local rv, err = pcall(connect, stage0.helen_host(), stage0.helen_port())
    last_ping_time = socket.gettime()
    if not rv then
      log.err("Connect to %s:%d failed: %s", stage0.helen_host(), stage0.helen_port(), err)
    else
      log.info("Connected to %s:%d", stage0.helen_host(), stage0.helen_port())
      return
    end
  end
end

function run_loop()
  local seed_rand=(function()
    local libc = alien.default
    local buf = alien.array("int", 1)
    libc.RAND_pseudo_bytes:types("int", "pointer", "int")
    libc.RAND_pseudo_bytes(buf.buffer, 4)
    math.randomseed(buf[1])
  end)()

  if equus.p_is_windows() == 1 then
    local create_pipe=(function ()
      my_pipe = socket.tcp()
      r,err = my_pipe:bind("localhost", 0)
      if err ~= nil then
        log.err("my_pipe bind: %s", err)
      end
      wakeup_pipe_ip,wakeup_pipe_port = my_pipe:getsockname()
      log.dbg("listening on: %s %d", wakeup_pipe_ip, wakeup_pipe_port)
      r,err = my_pipe:listen(5)
      if err ~= nil then
        log.err("my_pipe listen: %s", err)
      end
    end)()
  else
    local create_pipe=(function ()
      local libc = alien.default
      local buf = alien.array("int", 2)
      libc.pipe:types("int", "pointer")
      local rv = libc.pipe(buf.buffer)
      wakeup_pipe = socket.tcp(buf[2])
      my_pipe = socket.tcp(buf[1])
    end)()
  end

  reconnect()
  while equus.equus_restart_get() == 0 do
    log.dbg ('helen select')
    stage0:periodic()
    local reading = {my_pipe, client_skt}
    local writing = {}
    local r,w,e
    if equus.p_is_windows() == 1 then
      if equus.win32_getprocmemory ~= nil then
        equus.win32_getprocmemory()
      end
      r,w,e = socket.select(reading, writing, timertick(5, 10))
      local res = equus.equus_pop_result()
      while res ~= nil do
        log.dbg("result writing %d: %s ", res.length, res.data)
        client_skt:send(res.data, 1, res.length)
        equus.equus_free_result(res)
        res = equus.equus_pop_result()
      end
    else
      r,w,e = socket.select(reading, writing, timertick(15, 10))
    end

    local ntime = socket.gettime()
    local difftime = ntime - last_ping_time
    local ping_interval = stage0.helen_ping_interval()
    if difftime > timertick(ping_interval, ping_interval*.1) then
      last_ping_time = ntime
      log.info("sending ping")
      cmd_ping(client_skt)
    end

    if (count_ping_sent - count_pong_got) >= 2 then
      log.info('Failed to get ping replies, restarting...')
      equus.equus_restart_set(1)
    end

    for i,v in ipairs(r) do
      if v == my_pipe then
        log.dbg ('data on my_pipe: '.. tostring(v))
        if equus.p_is_windows() == 1 then
          --local line, err = v:receive()
          local my_pipe_tmp,err = my_pipe:accept()
          if err ~= nil then
            log.err("my_pipe accept: %s", err)
          end
          my_pipe_tmp:close()
        else
          local line, err, partial = v:receive(1)
        end
        local res = equus.equus_pop_result()
        while res ~= nil do
          log.dbg("result writing %d: %s ", res.length, res.data)
          client_skt:send(res.data, 1, res.length)
          equus.equus_free_result(res)
          res = equus.equus_pop_result()
        end
      elseif v == client_skt then
        log.dbg ('data on client_skt')
        local line, err, partial = v:receive('*l')
        if not line and err then
          log.crit('Error from connection. Reconnecting. err=%s', err)
          reconnect()
        else
          log.dbg("line: ".. line)
          handle_line(v, line)
        end
      else
        log.dbg ('data on unknown socket fd=%d', v:getfd())
      end
    end
  end
end
