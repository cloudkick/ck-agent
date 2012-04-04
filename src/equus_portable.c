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

#include "equus_portable.h"
#include "equus_util.h"

#ifdef WANT_ASPRINTF

int equus_vasprintf(char **outstr, const char *fmt, va_list args)
{
  size_t sz;
  sz = vsnprintf(NULL, 0, fmt, args);

  if (sz < 0) {
    return sz;
  }

  *outstr = malloc(sz + 1);
  if (*outstr == NULL) {
    return -1;
  }

  return vsnprintf(*outstr, sz + 1, fmt, args);
}

int equus_asprintf(char **outstr, const char *fmt, ...)
{
  int rv;
  va_list args;

  va_start(args, fmt);
  rv = equus_vasprintf(outstr, fmt, args);
  va_end(args);

  return rv;
}

#endif


#ifdef WANT_POPEN_CAPTURE
#include <string.h>

#ifdef _WIN32
#define popen _popen
#define pclose _pclose
#endif

int equus_popen_capture(lua_State *L)
{
  char psBuffer[4096];
  FILE *pPipe;
  int ret;

  const char * cmd=luaL_checkstring(L, 1);

  if( (pPipe = popen( cmd , "rt" )) == NULL ) {
    luaL_error(L, "error calling popen");
  }

  lua_pushlstring(L, "", 0);

  while(fgets(psBuffer, sizeof(psBuffer), pPipe) != NULL) {
    lua_pushlstring(L, psBuffer, strlen(psBuffer));
    lua_concat(L, 2);
  }

  ret = pclose(pPipe);

  if (ret==-1) {
    luaL_error(L, "error closing pipe");
  }

  lua_pushinteger(L, ret);
  return 2; /* number of return values */
}

#endif


#ifdef WANT_WIN32_EXEC_CALL

#include <windows.h>
char* format_err(int errcode, char *buf, size_t blen)
{
  /* Based on apr_os_strerror in apr/unix/errorcodes.c */
  size_t len = 0;
  size_t i = 0;
  LPTSTR msg = (LPTSTR) buf;

  len = FormatMessage(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
                     NULL,
                     errcode,
                     MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT), /* Default language */
                     msg,
                     (DWORD) (blen/sizeof(TCHAR)),
                     NULL);
  /* in-place convert to US-ASCII, substituting '?' for non ASCII   */
  for(i = 0; i <= len; i++) {
    if (msg[i] < 0x80 && msg[i] >= 0) {
      buf[i] = (char) msg[i];
    }
    else {
      buf[i] = '?';
    }
  }

  return buf;
}
/* expects one argument, the command line string */
int equus_exec_call_win32_core(lua_State *L)
{
  /* resources that have to be cleaned up */
  HANDLE hReadPipe = 0;
  HANDLE hWritePipe = 0;
  HANDLE hWritePipeErr = 0;
  PROCESS_INFORMATION pi={0}; /* contains handles */
  char * cmd = 0;
  char errbuf[128]; /* buffer for error messages */
  char * err=0; /* set on error */

  {
    const char * cmd_arg = luaL_checkstring(L, 1);
    cmd = strdup(cmd_arg); /* we need a mutable copy of the command line */

    if (!cmd) {
      err = "out of memory";
      goto cleanup;
    }

    /* create named pipe */
    {
      SECURITY_ATTRIBUTES sa = { sizeof(SECURITY_ATTRIBUTES) };
      // Set the bInheritHandle flag so pipe handles are inherited.
      sa.bInheritHandle = TRUE;
      sa.lpSecurityDescriptor = NULL;

      if (!CreatePipe(&hReadPipe, &hWritePipe, &sa, 0)) {
        err = "CreatePipe";
        goto cleanup;
      }

      /* don't inherit read handle */
      if (!SetHandleInformation(hReadPipe, HANDLE_FLAG_INHERIT, 0)) {
        err = "SetHandleInformation";
        goto cleanup;
      }
      if (!DuplicateHandle(
            GetCurrentProcess(), hWritePipe,
            GetCurrentProcess(), &hWritePipeErr,
            0, TRUE, DUPLICATE_SAME_ACCESS))
      {
        err = "DuplicateHandle";
        goto cleanup;
      }
    }

    {
      STARTUPINFOA si={sizeof(si)};

      si.dwFlags = STARTF_USESTDHANDLES;
      si.hStdOutput = hWritePipe;
      si.hStdError = hWritePipeErr;

      if (!CreateProcessA(
        0, /* lpApplicationName: we cannot use this parameter because
           it does not use the search path */
        cmd,
        0,
        0,
        TRUE, /* inherit handles for input redirection */
        0,
        0,
        0,
        &si,
        &pi))
      {
        char fmtbuf[128];
        DWORD nErr = GetLastError();
        format_err(nErr, fmtbuf, sizeof(fmtbuf));
        sprintf_s(errbuf, sizeof(errbuf), "CreateProcess: (%d) %s", nErr, fmtbuf);
        err=errbuf;
        goto cleanup;
      }
    }

    /* we need to close our handles to the write pipe here. */
    /* the child process still has its inherited handles */
    CloseHandle(hWritePipe);
    hWritePipe=0;
    CloseHandle(hWritePipeErr);
    hWritePipeErr=0;

    lua_pushlstring(L, "", 0);

    while (TRUE) {
      char buffer[1024] = {0};
      DWORD dwRead = 0;
      BOOL b = ReadFile(hReadPipe, buffer, sizeof(buffer)-1, &dwRead, NULL);

      /* DWORD nErr=GetLastError();  */
      if (!b) {
        /* assert(nErr==ERROR_BROKEN_PIPE); */
        break;
      }

      if (!dwRead) {
        /* assert(false); */
        break;
      }

      buffer[dwRead]=0;
      /* ATLTRACE(L"%hs", buffer); */
      lua_pushlstring(L, buffer, strlen(buffer));
      lua_concat(L, 2);
    }

    WaitForSingleObject(pi.hProcess, INFINITE);

    {
      DWORD dwExitCode=0;
      GetExitCodeProcess(pi.hProcess, &dwExitCode);
      lua_pushinteger(L, dwExitCode);
    }
  }

cleanup:
  CloseHandle(pi.hProcess);
  CloseHandle(pi.hThread);
  CloseHandle(hWritePipe);
  CloseHandle(hWritePipeErr);
  CloseHandle(hReadPipe);
  free(cmd);

  if (err) {
    luaL_error(L, err);
  }
  return 2; /* number of return values */
}

#endif

#ifdef WANT_UNIX_EXEC_CALL
#include <errno.h>
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/wait.h>

#ifndef EQUUS_MAX_ARGC
#define EQUUS_MAX_ARGC 64
#endif


static void pluaerror(lua_State *L, const char *function, int err, char **argv)
{
  int x;
  char buf[256];

  for (x = 0; argv[x] != NULL; x++) {
    free(argv[x]);
  }

  strerror_r(err, &buf[0], sizeof(buf));
  logCrit("Failed to call %s: (%d) %s)", function,
          err, &buf[0]);
  luaL_error(L, "Failed to call %s: (%d) %s)", function,
            err, &buf[0]);
}

static void
setnonblocking(int fd)
{
  int opts;
  opts = fcntl(fd, F_GETFL);
  opts = (opts | O_NONBLOCK);
  fcntl(fd, F_SETFL, opts);
}

/* expects one argument, a table to run */
int equus_exec_call_unix_core(lua_State *L)
{
  int rv;
  int pipes_stdout[2];
  int pipes_stderr[2];
  pid_t pid = 0;
  char *argv[EQUUS_MAX_ARGC];
  int i = 0;
  luaL_checktype(L, 1, LUA_TTABLE);

  lua_pushnil(L);
  while (lua_next(L, 1) != 0 && i < EQUUS_MAX_ARGC-1) {
    const char *arg = luaL_checkstring(L, -1);
    lua_pop(L, 1);
    argv[i] = strdup(arg);
    i++;
  }

  argv[i] = NULL;

  rv = pipe(pipes_stdout);
  if (rv == -1) {
    pluaerror(L, "pipe::stdout", errno, argv);
  }

  rv = pipe(pipes_stderr);
  if (rv == -1) {
    pluaerror(L, "pipe::stderr", errno, argv);
  }

  pid = fork();

  if (pid == 0) {
    close(STDIN_FILENO);

    close(pipes_stdout[0]);
    dup2(pipes_stdout[1], STDOUT_FILENO);
    close(pipes_stdout[1]);

    close(pipes_stderr[0]);
    dup2(pipes_stderr[1], STDERR_FILENO);
    close(pipes_stderr[1]);

    rv = execvp(argv[0], argv);

    if (rv == -1) {
      int err = errno;
      fprintf(stderr, "%s", strerror(err));
      fflush(stderr);
    }
    exit(EXIT_FAILURE);
  }
  else if (pid != -1) {
    int exit_rv;
    int exit_code = 0;
    pid_t waitstatus;

    close(pipes_stdout[1]);
    close(pipes_stderr[1]);
    setnonblocking(pipes_stdout[0]);
    setnonblocking(pipes_stderr[0]);

    lua_pushlstring(L, "", 0);

    while (1) {
      fd_set pipes;

      if (pipes_stdout[0] == -1 && pipes_stderr[0] == -1) {
        break;
      }

      FD_ZERO(&pipes);

      if (pipes_stdout[0] != -1) {
        FD_SET(pipes_stdout[0], &pipes);
      }

      if (pipes_stderr[0] != -1) {
        FD_SET(pipes_stderr[0], &pipes);
      }

      rv = select(FD_SETSIZE, &pipes, NULL, NULL, NULL);

      if (rv == -1) {
        if (errno != EINTR) {
          close(pipes_stderr[0]);
          close(pipes_stdout[0]);
          pluaerror(L, "select", errno, argv);
        }
      }
      else {
        if (pipes_stdout[0] != -1 && FD_ISSET(pipes_stdout[0], &pipes)) {
          char buffer[1024] = {0};
          ssize_t l = 0;
          l = read(pipes_stdout[0], &buffer[0], sizeof(buffer)-1);
          if (l == 0) {
            close(pipes_stdout[0]);
            pipes_stdout[0] = -1;
          }
          else if (l < 0) {
            int err = errno;
            if (err != EAGAIN) {
              close(pipes_stdout[0]);
              pluaerror(L, "child read stdout", err, argv);
            }
          }
          else {
            lua_pushlstring(L, buffer, l);
            lua_concat(L, 2);
          }
        }

        if (pipes_stderr[0] != -1 && FD_ISSET(pipes_stderr[0], &pipes)) {
          char buffer[1024] = {0};
          ssize_t l = 0;

          l = read(pipes_stderr[0], &buffer[0], sizeof(buffer)-1);

          if (l == 0) {
            close(pipes_stderr[0]);
            pipes_stderr[0] = -1;
          }
          else if (l < 0) {
            int err = errno;
            if (err != EAGAIN) {
              close(pipes_stderr[0]);
              pluaerror(L, "child read stderr", err, argv);
            }
          }
          else {
            lua_pushlstring(L, buffer, l);
            lua_concat(L, 2);
          }
        }
      }
    }

    do {
      waitstatus = waitpid(pid, &exit_rv, 0);

      if (waitstatus == -1) {
        pluaerror(L, "waitpid", errno, argv);
        break;
      }
      else if (waitstatus != pid) {
        /* If the child executed a child process, we want to wait until our child
         * process is actually done, not whatever child they started.
         */
        continue;
      }

      if (WIFEXITED(exit_rv)) {
        exit_code = WEXITSTATUS(exit_rv);
      }
      else {
        exit_code = 255;
      }

      lua_pushinteger(L, exit_code);
      break;
    } while (1);
  }
  else {
    pluaerror(L, "fork", errno, argv);
  }


  return 2;
}

#endif
