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

#ifndef _equus_service_h_
#define _equus_service_h_

#ifdef _WIN32

int win32_service_install(void);
void win32_service_delete(void);
void win32_service_start(void);
void win32_service_status(void);
void win32_service_stop(void);

#endif

#endif