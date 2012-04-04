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

#ifdef __linux__
#define _GNU_SOURCE
#endif
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <ctype.h>
#include "equus_portable.h"
#include "equus_util.h"

static void nuke_newlines(char *p)
{
  size_t i;
  size_t l = strlen(p);
  for (i = 0; i < l; i++) {
    if (p[i] == '\n') {
      p[i] = '\0';
    }
    if (p[i] == '\r') {
      p[i] = '\0';
    }
  }
}

static char *next_chunk(char **x_p)
{
  char *p = *x_p;

  while (isspace(p[0])) { p++;};

  nuke_newlines(p);

  *x_p = p;
  return strdup(p);
}

static int conf_parse(equus_conf_t *conf, FILE *fp)
{
  char buf[8096];
  char *p = NULL;
  while ((p = fgets(buf, sizeof(buf), fp)) != NULL) {
    /* comment lines */
    if (p[0] == '#') {
      continue;
    }

    while (isspace(p[0])) { p++;};

    if (strncmp("resources", p, 9) == 0) {
      p += 9;
      if (conf->resources) {
        free((char*)conf->resources);
      }
      conf->resources = next_chunk(&p);
      continue;
    }

  }

  return 0;
}

static const char* get_config_path()
{
  int i = 0;
  int argc = equus_get_argc();
  const char *arg = NULL;

  while (i < argc) {
    arg = equus_get_argv(i);

    if (strcmp(arg, "-c") == 0 || strcmp(arg, "--config") == 0) {
      const char *p = equus_get_argv(i+1);
      if (p) {
        return p;
      }
    }
    i++;
  }

  return "/etc/cloudkick.conf";
}

int equus_conf_init(equus_conf_t *conf)
{
  int rv;
  FILE *fp;
  /* TODO: respect prefix */
#ifdef _WIN32
  char *programfiles;
  char path[512];
#else
  const char *path;
#endif

#ifdef _WIN32
  programfiles = getenv("ProgramFiles");
  if (programfiles == NULL) {
    fprintf(stderr, "Unable to get environment variable: \"ProgramFiles\"\n");
    return -1;
  }
  sprintf(path, "%s\\Cloudkick Agent\\etc\\cloudkick.cfg", programfiles);
  fp = fopen(path, "r");
#else
  path = get_config_path();
  fp = fopen(path, "r");
#endif
  if (fp == NULL) {
    fprintf(stderr, "Unable to read configuration file: %s\n", path);
    fprintf(stderr, "If you want to see available options, run the agent with a --help\n"
                    "switch otherwise, please run cloudkick-config, or visit:\n"
                    "https://support.cloudkick.com/Agent/Installation\n");
    return -1;
  }

  rv = conf_parse(conf, fp);
  if (rv < 0) {
    return rv;
  }

  fclose(fp);

  if (!conf->resources) {
#ifdef EQUUS_BOOTSTRAP_URL
    conf->resources = strdup(EQUUS_BOOTSTRAP_URL);
#else
    conf->resources = strdup("");
#endif
  }
  else {
    int rv = 0;
    char *p = NULL;
    rv = asprintf(&p, "http://%s/%s/", conf->resources, EQUUS_PLATFORM);
    if (rv < 0) {
      fprintf(stderr, "asprintf failed. rv=%d\n"
                      "Please contact Cloudkick Support\n", rv);
      return -1;
    }
    if (conf->resources != NULL) {
      free((char*)conf->resources);
    }
    conf->resources = p;
  }

  return 0;
}

void equus_conf_free(equus_conf_t *conf)
{
  if (conf->resources != NULL) {
    free((char*)conf->resources);
  }
  free(conf);
}
