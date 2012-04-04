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

#ifndef _equus_util_h_
#define _equus_util_h_

#ifdef USE_SIGAR
#include "sigar.h"
#endif

void equus_set_argv(int argc, char* argv[]);
int equus_get_argc();
const char* equus_get_argv(int offset);

int equus_util_init();
int equus_load_config();

/* Code Signing and Verification Methods */
int equus_verify(const char *input, int len,
                 const char *sigbuf, int siglen,
                 const char *keybuf, int keylen);

const char *equus_url();

typedef enum
{
  EQUUS_LOG_NOTHING,
  EQUUS_LOG_CRITICAL,
  EQUUS_LOG_ERRORS,
  EQUUS_LOG_WARNINGS,
  EQUUS_LOG_INFO,
  EQUUS_LOG_DEBUG,
  EQUUS_LOG_EVERYTHING
} equus_log_level_e;

void equus_log_level_set(equus_log_level_e level);
equus_log_level_e equus_log_level_get();
/* if NULL, sets logfile to stderr, */
int equus_log_set_path(const char *);

/* If not using stderr, Closes current log file, and re-opens same path. */
int equus_log_rotate();

void equus_log(equus_log_level_e level, const char *str);
/* Simple variants:
 *    - Prepends Timestamp, log level.
 *    - Appends a newline
 */
void equus_log_critical(const char *str);
void equus_log_error(const char *str);
void equus_log_warning(const char *str);
void equus_log_info(const char *str);
void equus_log_debug(const char *str);


/* SWIG has problems with va_list, there are hacks to make it work in python
 * but we are using Lua... This shouldn't be needed most of the time,
 * but we have it just in case.
 */
#ifndef SWIG
#include <stdarg.h>
void equus_log_fmtv(equus_log_level_e level, const char* fmt, va_list ap);
#endif

#if !defined(SWIG) && !defined(_MSC_VER)
#define FMT_FUNC(x,y) __attribute__((format(printf,x,y)));
#else
#define FMT_FUNC(x,y)
#endif

void equus_log_fmt(equus_log_level_e level, const char* fmt, ...) FMT_FUNC(2,3);
void equus_log_criticalf(const char *fmt, ...) FMT_FUNC(1,2);
void equus_log_errorf(const char *fmt, ...) FMT_FUNC(1,2);
void equus_log_warningf(const char *fmt, ...) FMT_FUNC(1,2);
void equus_log_infof(const char *fmt, ...) FMT_FUNC(1,2);
void equus_log_debugf(const char *fmt, ...) FMT_FUNC(1,2);

#ifndef logCrit
#define logCrit equus_log_criticalf
#endif

#ifndef logErr
#define logErr equus_log_errorf
#endif

#ifndef logWarn
#define logWarn equus_log_warningf
#endif

#ifndef logInfo
#define logInfo equus_log_infof
#endif

#ifndef logDbg
#define logDbg equus_log_debugf
#endif


/* helper for killing stdio via freopen() */
int equus_shutdown_stdio();


typedef struct equus_result_t {
  const char *data;
  int length;
} equus_result_t;

void equus_push_result(const char *data, int len);
equus_result_t *equus_pop_result();
void equus_free_result(equus_result_t *res);

/* returns name of platform as string */
const char* p_platform();
int p_is_windows();
int p_is_unix();
int p_is_darwin();
int p_is_freebsd();
int p_is_openbsd();
int p_is_netbsd();
int p_is_solaris();
int p_is_linux();

#ifdef _WIN32
#include "windows.h"
#define MTX_LOCK(x) EnterCriticalSection(&x)
#define MTX_UNLOCK(x) LeaveCriticalSection(&x)
#else
#include <pthread.h>
#define MTX_LOCK(x) pthread_mutex_lock(&x)
#define MTX_UNLOCK(x) pthread_mutex_unlock(&x)
#endif

#ifdef _WIN32
int pipe_win32(int filedes [2]);
/* #define pipe pipe_win32 */

#define INSTALL_PREVIOUSLY  0
#define INSTALL_INSTALLED   1
#define INSTALL_FAILURE     2
#endif

int equus_restart_get();
void equus_restart_set(int i);

extern int g_equus_run_count;
#ifdef _WIN32
extern int g_equus_win_service;
#endif

typedef struct equus_conf_t {
    const char *resources;
} equus_conf_t;

int equus_conf_init(equus_conf_t *conf);
void equus_conf_free(equus_conf_t *conf);

#ifdef USE_SIGAR
sigar_t * sigar_create(void);
int sigar_destroy(sigar_t *si);
#endif

#ifdef _WIN32
// Memory debugging
void win32_mem_checkpoint_init(void);
void win32_mem_checkpoint(void);
void win32_mem_difference(void);
void win32_dumpmemoryleaks(void);
int win32_mem_values(void);
unsigned win32_getprocmemory(void);
#endif

#endif
