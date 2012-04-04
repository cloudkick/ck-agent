/*
 * The *hackish* Lua Debugger in this file is based on the one Included
 * in MojoSetup: <http://icculus.org/mojosetup/>
 *
 * We have modified it to use our own logger, and to fit in our
 * Lua Module loading structure, but at its core it is the same.
 *
 * Later we added more debugger like thigns, breakpoints and a code trace
 * function.
 */

/**
 * Origianl License from <mojosetup/LICENSE.txt>
 
 Copyright (c) 2006-2009 Ryan C. Gordon and others.
 
 This software is provided 'as-is', without any express or implied warranty.
 In no event will the authors be held liable for any damages arising from
 the use of this software.
 
 Permission is granted to anyone to use this software for any purpose,
 including commercial applications, and to alter it and redistribute it
 freely, subject to the following restrictions:
 
 1. The origin of this software must not be misrepresented; you must not
 claim that you wrote the original software. If you use this software in a
 product, an acknowledgment in the product documentation would be
 appreciated but is not required.
 
 2. Altered source versions must be plainly marked as such, and must not be
 misrepresented as being the original software.
 
 3. This notice may not be removed or altered from any source distribution.
 
 Ryan C. Gordon <icculus@icculus.org>

*/

#include "lua.h"
#include "lauxlib.h"
#include <stdlib.h>
#include <string.h>

#include "equus_util.h"

char scratchbuf_128k[128 * 1024];

static int retvalString(lua_State *L, const char *str)
{
  if (str != NULL)
    lua_pushstring(L, str);
  else
    lua_pushnil(L);
  return 1;
} // retvalString

static int snprintfcat(char **ptr, size_t *len, const char *fmt, ...)
{
  int bw = 0;
  va_list ap;
  va_start(ap, fmt);
  bw = vsnprintf(*ptr, *len, fmt, ap);
  va_end(ap);
  *ptr += bw;
  *len -= bw;
  return bw;
} // snprintfcat

#ifndef logDebug
#define logDebug logDbg
#endif

static int luahook_stackwalk(lua_State *L)
{
  const char *errstr = lua_tostring(L, 1);
  lua_Debug ldbg;
  int i = 0;
  
  if (errstr != NULL) {
    logDebug("%s", errstr);
  }
  logDebug("Lua stack backtrace:");
  
  // start at 1 to skip this function.
  for (i = 1; lua_getstack(L, i, &ldbg); i++)
  {
    char *ptr = (char *) scratchbuf_128k;
    size_t len = sizeof (scratchbuf_128k);
    int bw = snprintfcat(&ptr, &len, "#%d", i-1);
    const int maxspacing = 4;
    int spacing = maxspacing - bw;
    while (spacing-- > 0)
      snprintfcat(&ptr, &len, " ");
    
    if (!lua_getinfo(L, "nSl", &ldbg))
    {
      snprintfcat(&ptr, &len, "???\n");
      logDebug("%s", (const char *) scratchbuf_128k);
      continue;
    } // if
    
    if (ldbg.namewhat[0])
      snprintfcat(&ptr, &len, "%s ", ldbg.namewhat);
    
    if ((ldbg.name) && (ldbg.name[0]))
      snprintfcat(&ptr, &len, "function %s ()", ldbg.name);
    else
    {
      if (strcmp(ldbg.what, "main") == 0)
        snprintfcat(&ptr, &len, "mainline of chunk");
      else if (strcmp(ldbg.what, "tail") == 0)
        snprintfcat(&ptr, &len, "tail call");
      else
        snprintfcat(&ptr, &len, "unidentifiable function");
    } // if
    
    //logDebug("%0", (const char *) scratchbuf_128k);
    ptr = (char *) scratchbuf_128k;
    len = sizeof (scratchbuf_128k);
    
    for (spacing = 0; spacing < maxspacing; spacing++)
      snprintfcat(&ptr, &len, " ");
    
    if (strcmp(ldbg.what, "C") == 0)
      snprintfcat(&ptr, &len, "in native code");
    else if (strcmp(ldbg.what, "tail") == 0)
      snprintfcat(&ptr, &len, "in Lua code");
    else if ( (strcmp(ldbg.source, "=?") == 0) && (ldbg.currentline == 0) )
      snprintfcat(&ptr, &len, "in Lua code (debug info stripped)");
    else
    {
      snprintfcat(&ptr, &len, "in Lua code at %s", ldbg.short_src);
      if (ldbg.currentline != -1)
        snprintfcat(&ptr, &len, ":%d", ldbg.currentline);
      snprintfcat(&ptr, &len, " %s()", ldbg.name);
    } // else
    logDebug("%s", (const char *) scratchbuf_128k);
  } // for
  
  return retvalString(L, errstr ? errstr : "");
} // luahook_stackwalk

/* Start new lua debugger hackers by pquerna */

typedef struct breakpoint_t breakpoint_t;

struct breakpoint_t {
  const char *name;
  int line;
  breakpoint_t *next;
};

static breakpoint_t* breakpoint_head = NULL;

static void breakpoint_add(const char *name, int line)
{
  breakpoint_t *n = calloc(1, sizeof(breakpoint_t));
  n->name = strdup(name);
  n->line = line;
  n->next = breakpoint_head;
  breakpoint_head = n;
}

static void breakpoint_clear(const char *name, int line)
{
  breakpoint_t *prev = NULL;
  breakpoint_t *tmp = breakpoint_head;
  while (tmp != NULL) {
    breakpoint_t *t = tmp;
    if (t->line == line && strcmp(t->name, name) == 0) {
      if (prev != NULL) {
        /* unlink me from the slave chains of a linked list */
        prev->next = t->next;
      }
      else {
        breakpoint_head = NULL;
      }
      free((void*)t->name);
      free(t);
      tmp =  prev;
    }
    prev = tmp;
    tmp = tmp->next;
  }
}

static void breakpoint_clearall()
{
  breakpoint_t *tmp = breakpoint_head;
  while (tmp != NULL) {
    breakpoint_t *t = tmp;
    tmp = tmp->next;
    free((void*)t->name);
    free(t);
  }
  breakpoint_head = NULL;
}

static int luahook_debugger(lua_State *L);
static void debugger_breakpoint (lua_State *L, lua_Debug *ar)
{
  if (ar->event == LUA_HOOKLINE) {
    lua_getinfo(L, "nSl", ar);
    if (ar->currentline != -1 && strcmp(ar->what, "Lua") == 0) {
      breakpoint_t *tmp = breakpoint_head;
      while (tmp != NULL) {
        if (tmp->line == ar->currentline || tmp->line == 0) {
          if (strcmp(ar->source, tmp->name)) {
            fprintf(stderr, "Breakpoint hit at %s:%d\n\n", tmp->name, tmp->line);
            luahook_debugger(L);
            return;
          }
        }
        tmp = tmp->next;
      }
    }
  }
  return;
}

static int debugger_trace_enabled = 0;

static void debugger_trace (lua_State *L, lua_Debug *ar)
{
  if (ar->event == LUA_HOOKLINE) {
    lua_getinfo(L, "Sl", ar);
    if (strcmp(ar->what, "Lua") == 0) {
      fprintf(stderr, "L[%s:%d]\n", ar->source, ar->currentline);
    }
  }
  return;
}


/* end new debugger */
// This just lets you punch in one-liners and Lua will run them as individual
//  chunks, but you can completely access all Lua state, including calling C
//  functions and altering tables. At this time, it's more of a "console"
//  than a debugger. You can do "p MojoLua_debugger()" from gdb to launch this
//  from a breakpoint in native code, or call MojoSetup.debugger() to launch
//  it from Lua code (with stacktrace intact, too: type 'bt' to see it).
static int luahook_debugger(lua_State *L)
{
#if DISABLE_LUA_PARSER
  logError("Lua debugger is disabled in this build (no parser).");
#else
  int origtop;
  const equus_log_level_e origloglevel = equus_log_level_get();
  
  lua_pushcfunction(L, luahook_stackwalk);
  origtop = lua_gettop(L);
  
  printf("Quick and dirty Lua debugger. Type 'exit' to quit.\n");
  
  while (1)
  {
    char *buf = (char *) scratchbuf_128k;
    int len = 0;
    printf("> ");
    fflush(stdout);
    if (fgets(buf, sizeof (scratchbuf_128k), stdin) == NULL)
    {
      printf("\n\n  fgets() on stdin failed: ");
      break;
    } // if
    
    len = (int) (strlen(buf) - 1);
    while ( (len >= 0) && ((buf[len] == '\n') || (buf[len] == '\r')) )
      buf[len--] = '\0';
    
    if (strcmp(buf, "q") == 0)
      break;
    else if (strcmp(buf, "quit") == 0)
      break;
    else if (strcmp(buf, "exit") == 0)
      break;
    else if (strncmp(buf, "break ", 6) == 0) {
      int lineno = 0;
      char *p = strrchr(buf, ':');
      if (p != NULL) {
        lineno = atoi(p+1);
        *p = '\0';
      }
      breakpoint_add(buf+6, lineno);
      printf("Adding breakpoing to %s at line %d\n", buf+6, lineno);
      lua_sethook(L, debugger_breakpoint, LUA_MASKLINE, 0);
      continue;
    }
    else if (strncmp(buf, "clear ", 6) == 0) {
      int lineno = 0;
      char *p = strrchr(buf, ':');
      if (p != NULL) {
        lineno = atoi(p+1);
        *p = '\0';
      }
      breakpoint_clear(buf+6, lineno);
      printf("Clearing breakpoing to %s at line %d\n", buf+6, lineno);
      lua_sethook(L, debugger_breakpoint, 0, 0);
      continue;
    }
    else if (strcmp(buf, "clearall") == 0) {
      breakpoint_clearall();
      lua_sethook(L, debugger_breakpoint, 0, 0);
      printf("All breakpoints cleared\n");
      continue;
    }
    else if (strcmp(buf, "trace") == 0) {
      if (debugger_trace_enabled == 0) {
        lua_sethook(L, debugger_trace, LUA_MASKLINE, 0);
        debugger_trace_enabled = 1;
        printf("Tracing enabled!\n");
      }
      else {
        lua_sethook(L, debugger_trace, 0, 0);
        debugger_trace_enabled = 0;
        printf("Tracing disabled!\n");
      }
      continue;
    }
    else if (strcmp(buf, "bt") == 0)
    {
      //MojoLog_logLevel = MOJOSETUP_LOG_EVERYTHING;
      equus_log_level_set(EQUUS_LOG_EVERYTHING);
      strcpy(buf, "equus_stackwalk()");
    } // else if
    
    if ( (luaL_loadstring(L, buf) != 0) ||
        (lua_pcall(L, 0, LUA_MULTRET, -2) != 0) )
    {
      printf("%s\n", lua_tostring(L, -1));
      lua_pop(L, 1);
    } // if
    else
    {
      printf("Returned %d values.\n", lua_gettop(L) - origtop);
      while (lua_gettop(L) != origtop)
      {
        // !!! FIXME: dump details of values to stdout here.
        lua_pop(L, 1);
      } // while
      printf("\n");
    } // else
    
    //MojoLog_logLevel = origloglevel;
    equus_log_level_set(origloglevel);
  } // while
  
  lua_pop(L, 1);
  printf("exiting debugger...\n");
#endif
  
  return 0;
} // luahook_debugger

int
luaopen_equus_debugger(lua_State *L) 
{
  lua_register(L,"equus_debugger", luahook_debugger);
  lua_register(L,"equus_stackwalk", luahook_stackwalk);
  return 0;
}

