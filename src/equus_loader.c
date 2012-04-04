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

#include "lua.h"
#include "lauxlib.h"
#include <stdlib.h>
#include "equus_loader.h"
#include "equus_loader_blob.h"
#include "equus_portable.h"

#include "extern/luasocket/src/luasocket.h"
#include "extern/luasocket/src/mime.h"
#include "extern/luasocket/src/unix.h"
#include "extern/luasec/src/ssl.h"
#include "extern/luasec/src/context.h"

#ifdef LOCAL_DEV
#include "equus_localdev.h"
#endif

#include "equus_util.h"

static void lua_stack_dump(lua_State *L, const char *msg);

static int
equus_loader_load(lua_State *L)
{
  int rv;
  const char *p;
  size_t sz = 0;
  const char *name = luaL_checkstring(L, 1);

  rv = equus_loader_has_module(name);
  if (rv != 0) {
    lua_pushnil(L);
    return 1;
  }

  rv = equus_loader_get_module(name, &p, &sz);
  if (rv != 0) {
    lua_pushnil(L);
    return 1;
  }

  rv = luaL_loadbuffer(L, p, sz, name);
  if (rv != 0) {
    return luaL_error(L, "error loading equus module " LUA_QS , name);
  }
  return 1;
}

static int ldump_writer(lua_State *L, const void *b, size_t size, void *B)
{
  (void) L;
  luaL_addlstring((luaL_Buffer *) B, (const char *) b, size);
  return 0;
}

typedef struct eql_cache_t eql_cache_t;

struct eql_cache_t {
  int len;
  const char *name;
  const char *data;
  eql_cache_t *next;
};

#ifdef _WIN32
static CRITICAL_SECTION cachemtx;
#else
static pthread_mutex_t cachemtx = PTHREAD_MUTEX_INITIALIZER;
#endif

eql_cache_t *cache_head = NULL;
static eql_cache_t* equus_local_cache_find_nolock(const char *name)
{
  eql_cache_t *e;
  for (e = cache_head; e != NULL; e = e->next) {
    if (strcmp(e->name, name) == 0) {
      return e;
    }
  }
  return NULL;
}

static eql_cache_t* equus_local_cache_find(const char *name)
{
  eql_cache_t *e;
  MTX_LOCK(cachemtx);
  e = equus_local_cache_find_nolock(name);
  MTX_UNLOCK(cachemtx);
  return e;
}

static void equus_local_cache_free(eql_cache_t *x)
{
  eql_cache_t *e;
  eql_cache_t *tmp;

  e = x;
  while (e != NULL) {
    free((void*)e->name);
    free((void*)e->data);
    tmp = e->next;
    e->next = NULL;
    free((void*)e);
    e = tmp;
  }
}

void equus_local_cache_clear()
{
  MTX_LOCK(cachemtx);
  equus_local_cache_free(cache_head);
  cache_head = NULL;
  MTX_UNLOCK(cachemtx);
}

static eql_cache_t* equus_local_cache_push(eql_cache_t *x)
{
  eql_cache_t *e;
  MTX_LOCK(cachemtx);

  e = equus_local_cache_find_nolock(x->name);

  if (e != NULL) {
    MTX_UNLOCK(cachemtx);
    equus_local_cache_free(x);
    return e;
  }

  e = cache_head;
  x->next = e;
  cache_head = x;

  MTX_UNLOCK(cachemtx);

  return x;
}

static int load_aux (lua_State *L, int status) {
  //lua_stack_dump(L, "load_aux");
  if (status == 0) {
    return 1;
  }
  else {
    lua_pushnil(L);
    lua_insert(L, -2);  /* put before error message */
    return 2;  /* return nil plus error message */
  }
}


int equus_local_cache_get(lua_State *L)
{
  const char *name = luaL_checkstring(L, 1);
  eql_cache_t *e = equus_local_cache_find(name);

  if (e == NULL) {
    luaL_error(L, "cache miss for " LUA_QS , name);
    return load_aux(L, -1);
  }

  //logErr("cache hit for %s len(%d)", name, e->len);
  return load_aux(L, luaL_loadbuffer(L, e->data, e->len, e->name));
}

int equus_local_cache_add(lua_State *L)
{
  int rv = 0;
  const char *name = luaL_checkstring(L, 1);
  const char *module = luaL_checkstring(L, 2);
  size_t mlen =  lua_strlen(L, 2);
  //logErr("storing %s with %d bytes", name, mlen);

  luaL_Buffer b;

  /* This lua State is used only to compile the input strings -> bytecode,
   * so we don't need anything extra.
   */

  lua_State *lvm = luaL_newstate();
  lua_settop(lvm, 0);

  rv = luaL_loadbuffer(lvm, module, mlen, name);
  if (rv != 0) {
    return rv;
  }

  luaL_buffinit(lvm, &b);
  lua_dump(lvm, ldump_writer, &b);
  luaL_pushresult(&b);
  {
    eql_cache_t *c = malloc(sizeof(eql_cache_t));
    const char* d = lua_tolstring(L, -1, (size_t*)&c->len);
    c->name = strdup(name);
    c->data = malloc(c->len+1);
    c->next = NULL;
    memcpy((void*)c->data, d, c->len);
    c = equus_local_cache_push(c);
    lua_close(lvm);
  }

  return 0;
}

#ifdef LOCAL_DEV
static int
equus_local_load(lua_State *L)
{
  int rv;
  const char *p;
  size_t sz = 0;
  const char *sigp;
  size_t sigsz = 0;
  const char *keyp;
  size_t keysz = 0;
  const char *name = luaL_checkstring(L, 1);

  rv = equus_localdev_has_module(name);
  if (rv != 0) {
    lua_pushnil(L);
    return 1;
  }

  rv = equus_localdev_get_module(name, &p, &sz);
  if (rv != 0) {
    lua_pushnil(L);
    return 1;
  }

  rv = equus_localdev_get_signature(name, &sigp, &sigsz);
  if (rv != 0) {
    lua_pushnil(L);
    return 1;
  }

  rv = equus_localdev_get_pubkey(name, &keyp, &keysz);
  if (rv != 0) {
    lua_pushnil(L);
    return 1;
  }

  rv = equus_verify(p, sz,
                    sigp, sigsz,
                    keyp, keysz);
  if (rv != 0) {
    return luaL_error(L, "error loading (local) equus module: Signature Validation Failed: " LUA_QS , name);
  }

  rv = luaL_loadbuffer(L, p, sz, name);

  if (rv != 0) {
    return luaL_error(L, "error loading (local) equus module " LUA_QS , name);
  }
  return 1;
}
#endif


static void lua_stack_dump(lua_State *L, const char *msg)
{
  int i;
  int top = lua_gettop(L);

  logErr("Lua Stack Dump: %s starting at %d", msg, top);

  for (i = 1; i <= top; i++) {
    int t = lua_type(L, i);
    switch (t) {
      case LUA_TSTRING:{
        logErr("%d:  '%s'", i, lua_tostring(L, i));
        break;
      }
      case LUA_TUSERDATA:{
        logErr("%d:  <userdata %p>", i, lua_topointer(L, i));
        break;
      }
      case LUA_TLIGHTUSERDATA:{
        logErr("%d:  <lightuserdata %p>", i, lua_topointer(L, i));
        break;
      }
      case LUA_TNIL:{
        logErr("%d:  NIL", i);
        break;
      }
      case LUA_TNONE:{
        logErr("%d:  None", i);
        break;
      }
      case LUA_TBOOLEAN:{
        logErr("%d:  %s", i, lua_toboolean(L, i) ? "true" : "false");
        break;
      }
      case LUA_TNUMBER:{
        logErr("%d:  %g", i, lua_tonumber(L, i));
        break;
      }
      case LUA_TTABLE:{
        logErr("%d:  <table %p>", i, lua_topointer(L, i));
        break;
      }
      case LUA_TTHREAD:{
        logErr("%d:  <thread %p>", i, lua_topointer(L, i));
        break;
      }
      case LUA_TFUNCTION:{
        logErr("%d:  <function %p>", i, lua_topointer(L, i));
        break;
      }
      default:{
        logErr("%d:  unknown: [%s]", i, lua_typename(L, i));
        break;
      }
    }
  }
}

static int
equus_lua_stack_dump(lua_State *L)
{
  const char *name = luaL_checkstring(L, 1);
  lua_stack_dump(L, name);
  return 0;
}


/* TODO: make alien header file */
int luaopen_alien_core(lua_State *L);
int luaopen_alien_struct(lua_State *L);
int luaopen_pack(lua_State *L);
int luaopen_lanes(lua_State *L);
int luaopen_equus_debugger(lua_State *L);
static int
equus_loader_preload(lua_State *L)
{
  int top;

  top = lua_gettop(L);
  lua_getglobal(L, "package");

  if (lua_type(L, -1) != LUA_TTABLE) {
    abort();
  }

  lua_pushliteral(L, "preload");
  lua_gettable(L, -2);

  if(lua_type(L, -1) != LUA_TTABLE) {
    abort();
  }

  /* Modules bundled in extern/ */
  lua_pushcfunction(L, luaopen_socket_core);
  lua_setfield(L, -2, "socket.core");

#ifndef _WIN32
  lua_pushcfunction(L, luaopen_socket_unix);
  lua_setfield(L, -2, "socket.unix");
#endif

  lua_pushcfunction(L, luaopen_mime_core);
  lua_setfield(L, -2, "mime.core");

  lua_pushcfunction(L, luaopen_ssl_context);
  lua_setfield(L, -2, "ssl.context");

  lua_pushcfunction(L, luaopen_ssl_core);
  lua_setfield(L, -2, "ssl.core");

  lua_pushcfunction(L, luaopen_alien_core);
  lua_setfield(L, -2, "alien.core");

  lua_pushcfunction(L, luaopen_alien_struct);
  lua_setfield(L, -2, "alien.struct");

  lua_pushcfunction(L, luaopen_pack);
  lua_setfield(L, -2, "pack");

  lua_pushcfunction(L, luaopen_lanes);
  lua_setfield(L, -2, "lua51-lanes");

  lua_settop(L, top);

  return 0;
}

int
luaopen_equus_loader(lua_State *L)
{
#ifndef LOCAL_DEV
  int rv;
#endif
  int top;

  lua_register(L, "equus_local_cache_add", equus_local_cache_add);
  lua_register(L, "equus_local_cache_get", equus_local_cache_get);
  lua_register(L, "equus_lua_stack_dump", equus_lua_stack_dump);

  luaopen_equus_debugger(L);

  lua_register(L,"equus_popen_capture", equus_popen_capture);
#ifdef WANT_WIN32_EXEC_CALL
  lua_register(L,"equus_exec_call_win32_core", equus_exec_call_win32_core);
#endif

#ifdef WANT_UNIX_EXEC_CALL
  lua_register(L,"equus_exec_call_unix_core", equus_exec_call_unix_core);
#endif

  equus_loader_preload(L);

  top = lua_gettop(L);
  lua_getglobal(L, "package");

  if (lua_type(L, -1) != LUA_TTABLE) {
    abort();
  }

  lua_pushliteral(L, "loaders");
  lua_gettable(L, -2);

  if(lua_type(L, -1) != LUA_TTABLE) {
    abort();
  }

  lua_pushnumber(L, lua_objlen(L, -1) + 1);
  lua_pushcfunction(L, equus_loader_load);
  lua_settable(L, -3);

#ifdef LOCAL_DEV
  lua_pushnumber(L, lua_objlen(L, -1) + 1);
  lua_pushcfunction(L, equus_local_load);
  lua_settable(L, -3);
  lua_settop(L, top);
#else

  lua_getglobal(L, "require");
  if (lua_type(L, -1) != LUA_TFUNCTION) {
    logErr("-1 is %d", lua_type(L, -1));
    abort();
  }

  lua_pushliteral(L, "http_loader");

  rv = lua_pcall(L, 1, 1, 0);
  if (rv != 0) {
    logErr("lua_pcall is %d", rv);
    logErr("lua error=%s", lua_tostring(L, -1));
    abort();
  }

  lua_getglobal(L, "package"); // -2
  lua_pushliteral(L, "loaders"); /* gets popped */
  lua_gettable(L, -2); /* pops loader */
  lua_pushnumber(L, lua_objlen(L, -1) + 1); /* -3 */
  lua_pushvalue (L, -4);
  lua_settable(L, -3);

  lua_settop(L, top);
#endif
  return 0;
}

static void equus_loader_atexit(void)
{
#ifdef _WIN32
  DeleteCriticalSection(&cachemtx);
#endif
}

void equus_loader_init()
{
#ifdef _WIN32
  InitializeCriticalSection(&cachemtx);
#endif
  atexit(equus_loader_atexit);
}
