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

local function stats_add(qstats, stat, item)
  --log.dbg("stats add %s %s", stat, item)

  if not qstats[stat] then qstats[stat] = {} end
  if not qstats[stat][item] then qstats[stat][item] = 0 end

  qstats[stat][item] = qstats[stat][item] + 1
end

-- Parse the first line of the message information from mailq
-- this varies from sendmail to postfix/courier
local function parsemessagetop(line, m, sendmail)
  if sendmail then
    -- AA02508        3      1005     Dec 17 10:01        root
    local msg_reg = "([%u%d]+)%s+(%d+)%s+%d+%s*(%a+)%s+(%d+)%s+(%d+)%:(%d+)%s+(.*)%s*"
    m.id, m.size, m.month, m.day, m.hour, 
     m.minute, m.sender = line:match(msg_reg)
  else
    -- 92F7852E6C5     2532 Wed Oct 13 07:40:40  MAILER-DAEMON
    local msg_reg = "([%u%d]+)%s+(%d+)%s+(%a+)%s+(%a+)%s+(%d+)%s+(%d+)%:(%d+)%:(%d+)%s+(.*)%s*$"
     m.id, m.size, m.dow, m.month, m.day, m.hour, 
      m.minute, m.second, m.sender = line:match(msg_reg)
  end

  if not m.id or not m.size or not m.month or not m.day or not m.hour
    or not m.minute or not m.sender then
    return nil
  end
end 

local function parsemessage(line, f, qstats, sendmail, rcheck)
  local i = 1
  local m = {}
  m.recipients = {}

  repeat
    if i == 1 then
      parsemessagetop(line, m, sendmail)
    -- second line has the reason things are on the queue
    elseif i == 2 then
      m.reason = line:match("%s*%p*%s*([%w%s]+)%s*%p*%s*$")
    -- remaining lines are recipients
    elseif i > 2 then
      if line:find("^$") then return m end
      r = line:match("%s*(.*)%s*$")
      table.insert(m.recipients, r)
    end
    i = i + 1
    line = f:read()
  until not line

  if i <= 2 then
    rcheck:set_error("mailq match error")
    return nil
  end
  return m
end

local function getmetrics(args, rcheck)
  local header_found, tmp, qid = nil
  local sendmail = nil
  local qstats = {}
  qstats.messages = 0
  qstats.size = 0

  -- TODO: test framework to use something like:
  --   cmd = "cat equus/tests/mailq/0001.mailq"
  cmd = "mailq"
  local f = assert(io.popen('mailq', 'r'))

  while true do
    local line = f:read()
    if not line then break end
    --log.dbg("line %s", line)

    if not header_found then
      header_found, tmp, qid = line:find("%-+(Q%l*%s*ID)%-+%s+%-+Size%-+%s%-+.*Time%-+%s%-+Sender.Recipient%-+$")
      if qid == "QID" then sendmail = true end
    else
      if line:find("%-+%s+%d+%s+.*byte. in %d+ [Rr]equest..*$") then break end
      local msg = parsemessage(line, f, qstats, sendmail, rcheck)
      stats_add(qstats, "reason", msg.reason)
      stats_add(qstats, "sender", msg.sender)
      qstats.messages = qstats.messages + 1
      qstats.size = qstats.size + msg.size
    end
  end

  if not header_found then
    f:close()
    rcheck:set_error("mailq header match error")
    return nil
  end

  f:close()
  return qstats
end

function run(rcheck, args)
  local rv, r = pcall(getmetrics, args, rcheck)

  if not rv then
    log.err("err calling mailq: %s", r)
    rcheck:set_error("mailq error")
    return rcheck
  end
  
  if not r then return rcheck end

  for i, v in pairs(r.reason) do
    rcheck:add_metric(i, v, Check.enum.uint64)
  end
  for i, v in pairs(r.sender) do
    rcheck:add_metric(string.format("Messages from %s", i), v,
                      Check.enum.uint64)
  end

  rcheck:add_metric("Messages", r.messages, Check.enum.uint64)
  rcheck:add_metric("Queue Size", r.size, Check.enum.uint64)
  rcheck:set_status(string.format("%s messages and %s bytes", 
                    r.messages, r.size))
  return rcheck
end
