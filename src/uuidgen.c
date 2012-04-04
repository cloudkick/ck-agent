/*
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
#define _OLEAUT32_

#include <stdio.h>
#include <unknwn.h>

#pragma comment(lib, "ole32.lib")

GUID guid;
WORD* wstrGUID[100];
char strGUID[100];
int count, i;

int main (int argc, char* argv[]) {
  if (argc != 2) {
    fprintf (stderr, "SYNTAX: UUIDGEN <number-of-GUIDs-to-generate>\n");
    return 1;
    }
  count = atoi (argv[1]);
  for (i = 0; i < count; i++) {
    CoCreateGuid (&guid);
    StringFromCLSID (&guid, wstrGUID);
    WideCharToMultiByte (CP_ACP, 0, *wstrGUID, -1, strGUID, MAX_PATH, NULL, NULL);
    printf ("%s\n", strGUID);
    }
  return 0;
}
