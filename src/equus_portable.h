/**
*  Copyright 2012 Rackspace
*
*  Licensed under the Apache License, Version 2.0 (the "License");
*  you may not use this file except in compliance with the License.
*  You may obtain a copy of the License at
*
*      http://www.apache.org/licenses/LICENSE-2.0
*
*  Unless required by applicable law or agreed to in writing, software
*  distributed under the License is distributed on an "AS IS" BASIS,
*  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
*  See the License for the specific language governing permissions and
*  limitations under the License.
*
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>

#ifndef _equus_portable_h_
#define _equus_portable_h_

#define WANT_POPEN_CAPTURE
#ifdef _WIN32
#define WANT_ASPRINTF
#define WANT_WIN32_EXEC_CALL
#else
#define WANT_UNIX_EXEC_CALL
#endif

#ifdef WANT_ASPRINTF
int equus_vasprintf(char **outstr, const char *fmt, va_list args);
int equus_asprintf(char **strp, const char *fmt, ...);
#define vasprintf equus_vasprintf
#define asprintf equus_asprintf
#endif

#ifdef WANT_POPEN_CAPTURE
#include "lua.h"
#include "lauxlib.h"
int equus_popen_capture(lua_State *L);
#endif


#ifdef WANT_WIN32_EXEC_CALL
#include "lua.h"
#include "lauxlib.h"
int equus_exec_call_win32_core(lua_State *L);
#endif

#ifdef WANT_UNIX_EXEC_CALL
#include "lua.h"
#include "lauxlib.h"
int equus_exec_call_unix_core(lua_State *L);
#endif

#endif