/*                                                                                                                                                                              *  Copyright 2012 Rackspace
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


#include <stdlib.h>
#include <stdio.h>


#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
#include "sigar.h"

#include "equus_version.h"
#include "equus_loader.h"
#ifdef EQ_TEST_HARNESS
#include "equus_testbootstrap.h"
#else
#include "equus_bootstrap.h"
#endif
#include "equus_util.h"

#ifndef _WIN32
#include <signal.h>
#include "equus_service.h"
#endif

/* TODO: make this less stupid */
extern int luaopen_equus(lua_State* L); // declare the wrapped module

static lua_State* equus_lua_load_modules(lua_State *L)
{
  /* Equus Modules */
  luaopen_equus(L);

  /* Custom loader for runtime lua modules. */
  luaopen_equus_loader(L);

  return L;
}

lua_State*
equus_lua_vm()
{
  lua_State *L;
  L = lua_open();

  /* Standard Lua Modules */
  luaL_openlibs(L);

  return equus_lua_load_modules(L);
}

#ifndef _WIN32
static void hup_handler (int signum)
{
  equus_log_rotate();
}

static void usr1_handler (int signum)
{
  int rv;

  logInfo("Re-reading config file");
  rv = equus_load_config();
  if (rv < 0) {
    logCrit("Failed loading config file, exiting");
    exit(EXIT_FAILURE);
  }

  equus_restart_set(1);
}
#endif

int main_core(int argc,char* argv[]);

#ifdef _WIN32
static SERVICE_STATUS g_service_status={0};
static SERVICE_STATUS_HANDLE g_service_handle=NULL;

static HANDLE g_h_service_stop_event=NULL;

VOID WINAPI win32_service_handler(DWORD dwControl)
{

  if (dwControl == SERVICE_CONTROL_STOP) {
    /* stop lua interpreter */
    /* based on laction in lua.c */

    g_service_status.dwCurrentState = SERVICE_STOP_PENDING;
    SetEvent(g_h_service_stop_event);
  }
  SetServiceStatus(g_service_handle, &g_service_status);
}

static int g_argc=0;
static char ** g_argv=0;

#ifndef ARRAYSIZE
#define ARRAYSIZE(a) sizeof(a)/sizeof(a[0])
#endif

DWORD WINAPI win32_thread_proc(PVOID context)
{
  /*
    Create empty config file if none exists.
  */
  {
    CHAR buffer[MAX_PATH]={0};
    ExpandEnvironmentStrings("%ProgrmFiles%\\Cloudkick\\etc\\cloudkick.cfg", buffer, ARRAYSIZE(buffer));
    {
      HANDLE hfile=CreateFile(buffer, GENERIC_READ, FILE_SHARE_READ, 0, CREATE_NEW, 0, 0);
      if (hfile!= INVALID_HANDLE_VALUE)
        CloseHandle(hfile);
    }
  }

  g_equus_win_service = 1;
  return main_core(g_argc, g_argv);
}

VOID WINAPI win32_service_main(
                               DWORD dwArgc,
                               LPTSTR* lpszArgv
                               )
{
  g_service_handle=RegisterServiceCtrlHandler("", win32_service_handler);

  if (!g_service_handle) {
    return;
  }

  g_service_status.dwCurrentState = SERVICE_RUNNING;
  g_service_status.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
  g_service_status.dwControlsAccepted = SERVICE_ACCEPT_STOP;

  SetServiceStatus(g_service_handle, &g_service_status);

  g_h_service_stop_event=CreateEvent(NULL, TRUE, FALSE, NULL);
  if (!g_h_service_stop_event)
    goto error;

  {
    HANDLE h_thread=CreateThread(0, 0, win32_thread_proc, 0, 0, NULL);
    if (!h_thread)
      goto error;

    {
      HANDLE wait_objects[]={h_thread, g_h_service_stop_event};

      DWORD dwWait=WaitForMultipleObjects(ARRAYSIZE(wait_objects), wait_objects, FALSE, INFINITE);
      if (dwWait==WAIT_OBJECT_0) {
        /* if the thread ended, use the exit code */
        GetExitCodeThread(h_thread, &g_service_status.dwServiceSpecificExitCode);
      }
    }
  }

  if (0!=g_service_status.dwServiceSpecificExitCode) {
    g_service_status.dwWin32ExitCode = ERROR_SERVICE_SPECIFIC_ERROR;
    /* event log */
  }

  g_service_status.dwCurrentState = SERVICE_STOPPED;
  SetServiceStatus(g_service_handle, &g_service_status);
  return;

error:
  g_service_status.dwWin32ExitCode = GetLastError();
  g_service_status.dwCurrentState = SERVICE_STOPPED;
  SetServiceStatus(g_service_handle, &g_service_status);
}


int win32_run_service(int argc,char* argv[])
{
  SERVICE_TABLE_ENTRY ste[]={
    { "", win32_service_main },
    { NULL, NULL }
  };

  g_argc=argc;
  g_argv=argv;

  if (!StartServiceCtrlDispatcher(ste)) {
    equus_log(EQUUS_LOG_CRITICAL, "StartServiceCtrlDispatcher: failed");
    return EXIT_FAILURE;
  }


  /*
  The agent thread may still be running.
  This is a clean way to make everything go away.
  */
  TerminateProcess(GetCurrentProcess(), EXIT_SUCCESS);

  return 0; /* never reached */
}
#endif /* _WIN32 */


int main(int argc,char* argv[])
{
#ifdef _WIN32
  int i=0;

  for (i=1; i<argc; i++) {
    char * arg=argv[i];
    if (0==stricmp(arg, "--install")) {
      win32_service_install();
      return 0;
    }
    if (0==stricmp(arg, "--delete")) {
      win32_service_delete();
      return 0;
    }
    if (0==stricmp(arg, "--start")) {
      win32_service_start();
      return 0;
    }
    if (0==stricmp(arg, "--status")) {
      win32_service_status();
      return 0;
    }
    if (0==stricmp(arg, "--stop")) {
      win32_service_stop();
      return 0;
    }
    if (0==stricmp(arg, "--noservice")) {
      return main_core(argc, argv);
    }
  }

  if (argc == 1) {
    return win32_run_service(argc, argv); /* this call never returns */
  }
  else
    return main_core(argc, argv);

#else

  return main_core(argc, argv);

#endif
}


int main_core(int argc,char* argv[])
{
  const char *lua_err;
  int status;
  const char *p = NULL;
  size_t sz = 0;
  int rv = 0;
#ifdef EQ_TEST_HARNESS
#define BOOTSTRAP_MODULE "bootstrap-test"
#else
#ifndef LOCAL_DEV
#define BOOTSTRAP_MODULE "bootstrap-http"
#else
#define BOOTSTRAP_MODULE "bootstrap-local"
#endif
#endif
  equus_set_argv(argc, argv);

  rv = equus_util_init();
  if (rv < 0) {
    return EXIT_FAILURE;
  }

#ifndef _WIN32
  if (signal (SIGHUP, hup_handler) == SIG_IGN) {
    signal (SIGHUP, SIG_IGN);
  }

  if (signal (SIGUSR1, usr1_handler) == SIG_IGN) {
    signal (SIGUSR1, SIG_IGN);
  }
#endif

  status = equus_bootstrap_get_module(BOOTSTRAP_MODULE, &p, &sz);
  if (status != 0) {
    logCrit("Errorcode: bootstrap broken.\n");
    return EXIT_FAILURE;
  }

  do {
    lua_State* L;
    equus_restart_set(0);
    g_equus_run_count++;

    L = equus_lua_vm();

    status = luaL_loadbuffer(L, p, sz, "bootstrap.lua");
    if (status != 0) {
      lua_err = lua_tostring(L, -1);
      logCrit("Load Buffer Error: %s\n\n", lua_err);
      return EXIT_FAILURE;
    }

    status = lua_pcall(L, 0, 0, 0);
    if (status != 0) {
      lua_err = lua_tostring(L, -1);
      logCrit("Runtime Error: %s", lua_err);
      return EXIT_FAILURE;
    }

    lua_close(L);

    equus_local_cache_clear();

  } while (equus_restart_get() == 1);

  return 0;
}

/* These exports are needed for calls from lua through alien.default */
#ifdef _WIN32
#pragma comment (linker, "/EXPORT:RAND_pseudo_bytes=_RAND_pseudo_bytes")
#pragma comment (linker, "/EXPORT:malloc=_malloc")
#pragma comment (linker, "/EXPORT:free=_free")
#pragma comment (linker, "/EXPORT:strcpy=_strcpy")
#pragma comment (linker, "/EXPORT:strcat=_strcat")
#pragma comment (linker, "/EXPORT:puts=_puts")
#pragma comment (linker, "/EXPORT:getpid=_getpid")
#pragma comment (linker, "/EXPORT:write=_write")
#pragma comment (linker, "/EXPORT:pipe=_pipe_win32")
#endif



