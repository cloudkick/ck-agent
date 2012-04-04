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
local os = require 'os'

local function get_mysql()
  local mysql = alien.load("mysqlclient_r")

  --  MYSQL *mysql_init(MYSQL *mysql)
  mysql.mysql_init:types("pointer", "pointer")

  -- MYSQL *mysql_real_connect(MYSQL *mysql, const char *host,
  -- const char *user, const char *passwd, const char *db,
  -- unsigned int port, const char *unix_socket,
  -- unsigned long client_flag)
  mysql.mysql_real_connect:types("pointer", "pointer", "string", "string",
                                 "string", "string", "uint", "string",
                                 "ulong")

  -- const char* mysql_error(MYSQL *mysql)
  mysql.mysql_error:types("string", "pointer")

  -- int mysql_options(MYSQL *mysql, enum mysql_option option, const void *arg)
  mysql.mysql_options:types("uint", "pointer", "uint", void)

  -- int mysql_query(MYSQL *mysql, const char *stmt_str)
  mysql.mysql_query:types("int", "pointer", "string")

  -- MYSQL_RES *mysql_store_result(MYSQL *mysql)
  mysql.mysql_store_result:types("pointer", "pointer")

  -- MYSQL_RES *mysql_use_result(MYSQL *mysql)
  mysql.mysql_use_result:types("pointer", "pointer")

  -- unsigned int mysql_num_fields(MYSQL_RES *result)
  mysql.mysql_num_fields:types("uint", "pointer")

  -- MYSQL_ROW mysql_fetch_row(MYSQL_RES *result)
  mysql.mysql_fetch_row:types("pointer", "pointer")

  --  MYSQL_FIELD *mysql_fetch_field(MYSQL_RES *result)
  mysql.mysql_fetch_field:types("pointer", "pointer")

  --  void mysql_free_result(MYSQL_RES *result)
  mysql.mysql_free_result:types(void, "pointer")

  -- void mysql_close(MYSQL *mysql)
  mysql.mysql_close:types(void, "pointer")

  -- void mysql_server_end(void)
  -- Note: Deprecated since 5.03
  mysql.mysql_server_end:types(void)

  -- void mysql_library_end(void)
  -- Note: available in mysql > 5.0.3
  -- mysql.mysql_library_end:types(void, void)

  -- void mysql_thread_end(void)
  mysql.mysql_thread_end:types(void)

  return mysql
end

function run(rcheck, args)
  if equus.p_is_windows() == 1 then
    rcheck:set_error("mysql check is not supported on windows")
    return rcheck
  end

  local mysql = get_mysql()
  local conn, err

  if args.host == nil then
    args.host = '127.0.0.1'
  else
    args.host = args.host[1]
  end

  if args.port == nil then
    if args.host == 'localhost' or args.host == '127.0.0.1' then
      args.port = 0 -- use unix socket on unix, shared memory on windows
    else
      args.port = 3306
    end
  else
    args.port = tonumber(args.port[1])
  end

  if args.user == nil then
    args.user = 'root'
  else
    args.user = args.user[1]
  end

  if args.pw then
    args.pw = args.pw[1]
  end

  -- http://dev.mysql.com/doc/refman/4.1/en/server-status-variables.html
  if args.stats == nil then
	  args.stats = {"Aborted_clients",
			            "Connections",
			            "Innodb_buffer_pool_pages_dirty",
			            "Innodb_buffer_pool_pages_free",
			            "Innodb_buffer_pool_pages_flushed",
			            "Innodb_buffer_pool_pages_total",
			            "Innodb_row_lock_time",
			            "Innodb_row_lock_time_avg",
			            "Innodb_row_lock_time_max",
			            "Innodb_rows_deleted",
			            "Innodb_rows_inserted",
			            "Innodb_rows_read",
			            "Innodb_rows_updated",
			            "Queries",
			            "Threads_connected",
			            "Threads_created",
			            "Threads_running",
			            "Uptime",

			            "Qcache_free_blocks",
			            "Qcache_free_memory",
			            "Qcache_hits",
			            "Qcache_inserts",
			            "Qcache_lowmem_prunes",
			            "Qcache_not_cached",
			            "Qcache_queries_in_cache",
			            "Qcache_total_blocks"
		  }
  end

  local stat_types = {
                  Aborted_clients = Check.enum.uint64,
			            Connections = Check.enum.gauge,

			            Innodb_buffer_pool_pages_dirty = Check.enum.uint64,
			            Innodb_buffer_pool_pages_free = Check.enum.uint64,
			            Innodb_buffer_pool_pages_flushed = Check.enum.uint64,
			            Innodb_buffer_pool_pages_total = Check.enum.uint64,
			            Innodb_row_lock_time = Check.enum.uint64,
			            Innodb_row_lock_time_avg = Check.enum.uint64,
			            Innodb_row_lock_time_max = Check.enum.uint64,
			            Innodb_rows_deleted = Check.enum.gauge,
			            Innodb_rows_inserted = Check.enum.gauge,
			            Innodb_rows_read = Check.enum.gauge,
			            Innodb_rows_updated = Check.enum.gauge,

			            Queries = Check.enum.gauge,

			            Threads_connected = Check.enum.uint64,
			            Threads_created = Check.enum.uint64,
			            Threads_running = Check.enum.uint64,

			            Uptime = Check.enum.uint64,

			            Qcache_free_blocks = Check.enum.uint64,
			            Qcache_free_memory = Check.enum.uint64,
			            Qcache_hits = Check.enum.gauge,
			            Qcache_inserts  = Check.enum.gauge,
			            Qcache_lowmem_prunes  = Check.enum.gauge,
			            Qcache_not_cached = Check.enum.gauge,
			            Qcache_queries_in_cache = Check.enum.uint64,
			            Qcache_total_blocks = Check.enum.uint64
		  }

  conn = mysql.mysql_init(conn)
  -- We should probably lower the connection timeout
  -- mysql.mysql_options()
  local ret =
    mysql.mysql_real_connect(conn, args.host, args.user, args.pw,
                             nil, args.port, nil, 0)
  err = mysql.mysql_error(conn)

  if ret == nil then
    mysql.mysql_close(conn)
    mysql.mysql_server_end()
    mysql.mysql_thread_end()

    rcheck:set_error("Could not connect: " .. err)
    return rcheck
  end

  mysql.mysql_query(conn, "show status")
  local result = mysql.mysql_use_result(conn)
  local num_fields = mysql.mysql_num_fields(result)

  if num_fields ~= 2 then
    mysql.mysql_free_result(result)
    mysql.mysql_close(conn)
    mysql.mysql_server_end()
    mysql.mysql_thread_end()

    rcheck:set_error("Unexpected number of fields %i", num_fields)
    return rcheck
  end

  -- Grab field names
  -- Possibly useful later for other mysql plugins
  -- local fields = {}
  -- for i=0, (num_fields) do
  -- f = mysql.mysql_fetch_field(result)
  --  if f == nil then break end
  --  field = alien.buffer(f)
  --  col = field:get(structs.MYSQL_FIELD.name+1, "string")
  --  fields[i] = col
  -- end

  while true do
    r = mysql.mysql_fetch_row(result)
    if r == nil then break end
    row = alien.array("string", num_fields, alien.buffer(r))

    if stat_types[row[1]] ~= nil then
      rcheck:add_metric(row[1], row[2], stat_types[row[1]])
    end
  end

  rcheck:set_status("metrics successfully retrieved")

  mysql.mysql_free_result(result)
  mysql.mysql_close(conn)
  mysql.mysql_server_end()
  --mysql.mysql_thread_end()

  return rcheck
end
