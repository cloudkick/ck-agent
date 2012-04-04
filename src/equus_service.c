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

#ifdef _WIN32

#include <windows.h>
#include <stdlib.h>
#include <stdio.h>

#include "equus_util.h"

#define SVCNAME "Cloudkick Agent Service"

#pragma comment(lib, "advapi32.lib")

/*
  Check if installed, yes: just return. No: install as service.
  Report errors.
*/
int win32_service_install(void)
{
  SC_HANDLE schSCManager;
  SC_HANDLE schService;
  char szPath[MAX_PATH];
  SERVICE_STATUS ssStatus;
  SERVICE_DESCRIPTION sd;
  LPTSTR szDesc = TEXT("Provides Cloudkick-Agent on-machine monitoring for this server. The agent can record disk, bandwidth, CPU usage, and more. Data collected from the agent goes into Cloudkick's graphing engine, making it easy to visualize what's happening to a server.");
  char msgBuf[256];
  SC_ACTION sa[1];
  SERVICE_FAILURE_ACTIONS sfa;

  if( !GetModuleFileName( NULL, szPath, MAX_PATH ) ) {
    sprintf(msgBuf, "Cannot get module file name (%d)\n", GetLastError());
    equus_log(EQUUS_LOG_CRITICAL, msgBuf);
    return INSTALL_FAILURE;
  }

  // Get a handle to the SCM database.
  schSCManager = OpenSCManager(
      NULL,                    // local computer
      NULL,                    // ServicesActive database
      SC_MANAGER_ALL_ACCESS);  // full access rights
  if (NULL == schSCManager) {
    sprintf(msgBuf, "OpenSCManager failed (%d)\n", GetLastError());
    equus_log(EQUUS_LOG_CRITICAL, msgBuf);
    return INSTALL_FAILURE;
  }

  // Check if already installed:
  // Get a handle to the service.
  schService = OpenService(
      schSCManager,         // SCM database
      SVCNAME,              // name of service
      SC_MANAGER_CONNECT);  // need delete access
  if (schService != NULL) {
    // service already is installed
    CloseServiceHandle(schService);
    CloseServiceHandle(schSCManager);
    return INSTALL_PREVIOUSLY;
  }

  // Create the service
  schService = CreateService(
      schSCManager,              // SCM database
      SVCNAME,                   // name of service
      SVCNAME,                   // service name to display
      SERVICE_ALL_ACCESS,        // desired access
      SERVICE_WIN32_OWN_PROCESS, // service type
      SERVICE_AUTO_START,        // start type
      SERVICE_ERROR_NORMAL,      // error control type
//      SERVICE_ERROR_CRITICAL,    // error control type
      szPath,                    // path to service's binary
      NULL,                      // no load ordering group
      NULL,                      // no tag identifier
      NULL,                      // no dependencies
      NULL,                      // LocalSystem account
      NULL);                     // no password
  if (schService == NULL) {
    CloseServiceHandle(schSCManager);
    sprintf(msgBuf, "CreateService failed (%d)\n", GetLastError());
    equus_log(EQUUS_LOG_CRITICAL, msgBuf);
    return INSTALL_FAILURE;
  } else {
    sprintf(msgBuf, "Service installed successfully\n");
    equus_log(EQUUS_LOG_INFO, msgBuf);
  }

  sd.lpDescription = szDesc;
  if( !ChangeServiceConfig2(
      schService,                 // handle to service
      SERVICE_CONFIG_DESCRIPTION, // change: description
      &sd) )                      // new description
  {
    sprintf(msgBuf, "ChangeServiceConfig2 error: %d\n", GetLastError());
    equus_log(EQUUS_LOG_ERRORS, msgBuf);
  } else {
    sprintf(msgBuf, "Service description updated successfully.\n");
    equus_log(EQUUS_LOG_INFO, msgBuf);
  }

  sfa.dwResetPeriod = 0;
  sfa.lpRebootMsg = NULL;
  sfa.lpCommand = NULL;
  sfa.cActions = 1;
  sa[0].Type = SC_ACTION_RESTART;
  sa[0].Delay = 0;
  sfa.lpsaActions = sa;
  sfa.dwResetPeriod = 0;
  if( !ChangeServiceConfig2(
      schService,                     // handle to service
      SERVICE_CONFIG_FAILURE_ACTIONS, // change: failure actions
      &sfa) )                         // failure actions
  {
    sprintf(msgBuf, "ChangeServiceConfig2 error: %d\n", GetLastError());
    equus_log(EQUUS_LOG_ERRORS, msgBuf);
  } else {
    sprintf(msgBuf, "Service failure actions updated successfully.\n");
    equus_log(EQUUS_LOG_INFO, msgBuf);
  }

  CloseServiceHandle(schService);
  CloseServiceHandle(schSCManager);
  return INSTALL_INSTALLED;
}

void win32_service_delete(void)
{
  SC_HANDLE schSCManager;
  SC_HANDLE schService;

  // Get a handle to the SCM database.
  schSCManager = OpenSCManager(
      NULL,                    // local computer
      NULL,                    // ServicesActive database
      SC_MANAGER_ALL_ACCESS);  // full access rights
  if (NULL == schSCManager) {
      printf("OpenSCManager failed (%d)\n", GetLastError());
      return;
  }

  // Get a handle to the service.
  schService = OpenService(
      schSCManager,            // SCM database
      SVCNAME,                 // name of service
      DELETE);                 // need delete access
  if (schService == NULL) {
    printf("OpenService failed (%d)\n", GetLastError());
    CloseServiceHandle(schSCManager);
    return;
  }

  // Delete the service.
  if (! DeleteService(schService) ) {
    printf("DeleteService failed (%d)\n", GetLastError());
  } else
    printf("Service deleted successfully\n");

  CloseServiceHandle(schService);
  CloseServiceHandle(schSCManager);
}

void win32_service_start(void)
{
  SC_HANDLE schSCManager;
  SC_HANDLE schService;
  SERVICE_STATUS_PROCESS ssStatus;
  DWORD dwOldCheckPoint;
  DWORD dwStartTickCount;
  DWORD dwWaitTime;
  DWORD dwBytesNeeded;

  // Get a handle to the SCM database.
  schSCManager = OpenSCManager(
        NULL,                    // local computer
        NULL,                    // servicesActive database
        SC_MANAGER_ALL_ACCESS);  // full access rights
  if (NULL == schSCManager) {
    printf("OpenSCManager failed (%d)\n", GetLastError());
    return;
  }

  // Get a handle to the service.
  schService = OpenService(
        schSCManager,         // SCM database
        SVCNAME,              // name of service
        SERVICE_ALL_ACCESS);  // full access
  if (schService == NULL) {
    printf("OpenService failed (%d)\n", GetLastError());
    CloseServiceHandle(schSCManager);
    return;
  }

  // Check the status in case the service is not stopped.
  if (!QueryServiceStatusEx(
        schService,                     // handle to service
        SC_STATUS_PROCESS_INFO,         // information level
        (LPBYTE) &ssStatus,             // address of structure
        sizeof(SERVICE_STATUS_PROCESS), // size of structure
        &dwBytesNeeded ) )              // size needed if buffer is too small
  {
    printf("QueryServiceStatusEx failed (%d)\n", GetLastError());
    CloseServiceHandle(schService);
    CloseServiceHandle(schSCManager);
    return;
  }

  // Check if the service is already running. It would be possible
  // to stop the service here, but for simplicity this just returns.
  if (ssStatus.dwCurrentState != SERVICE_STOPPED &&
      ssStatus.dwCurrentState != SERVICE_STOP_PENDING) {
    printf("Cannot start the service because it is already running\n");
    CloseServiceHandle(schService);
    CloseServiceHandle(schSCManager);
    return;
  }

  // Save the tick count and initial checkpoint.
  dwStartTickCount = GetTickCount();
  dwOldCheckPoint = ssStatus.dwCheckPoint;

  // Wait for the service to stop before attempting to start it.
  while (ssStatus.dwCurrentState == SERVICE_STOP_PENDING) {
    // Do not wait longer than the wait hint. A good interval is
    // one-tenth of the wait hint but not less than 1 second
    // and not more than 10 seconds.

    dwWaitTime = ssStatus.dwWaitHint / 10;

    if( dwWaitTime < 1000 )
      dwWaitTime = 1000;
    else if ( dwWaitTime > 10000 )
      dwWaitTime = 10000;

    Sleep( dwWaitTime );

    // Check the status until the service is no longer stop pending.
    if (!QueryServiceStatusEx(
            schService,                     // handle to service
            SC_STATUS_PROCESS_INFO,         // information level
            (LPBYTE) &ssStatus,             // address of structure
            sizeof(SERVICE_STATUS_PROCESS), // size of structure
            &dwBytesNeeded ) )              // size needed if buffer is too small
    {
      printf("QueryServiceStatusEx failed (%d)\n", GetLastError());
      CloseServiceHandle(schService);
      CloseServiceHandle(schSCManager);
      return;
    }

    if ( ssStatus.dwCheckPoint > dwOldCheckPoint ) {
      // Continue to wait and check.
      dwStartTickCount = GetTickCount();
      dwOldCheckPoint = ssStatus.dwCheckPoint;
    } else {
      if(GetTickCount()-dwStartTickCount > ssStatus.dwWaitHint) {
        printf("Timeout waiting for service to stop\n");
        CloseServiceHandle(schService);
        CloseServiceHandle(schSCManager);
        return;
      }
    }
  }

  // Attempt to start the service.
  if (!StartService(
          schService,  // handle to service
          0,           // number of arguments
          NULL) )      // no arguments
  {
    printf("StartService failed (%d)\n", GetLastError());
    CloseServiceHandle(schService);
    CloseServiceHandle(schSCManager);
    return;
  } else
    printf("Service start pending...\n");

  // Check the status until the service is no longer start pending.
  if (!QueryServiceStatusEx(
          schService,                     // handle to service
          SC_STATUS_PROCESS_INFO,         // info level
          (LPBYTE) &ssStatus,             // address of structure
          sizeof(SERVICE_STATUS_PROCESS), // size of structure
          &dwBytesNeeded ) )              // if buffer too small
  {
    printf("QueryServiceStatusEx failed (%d)\n", GetLastError());
    CloseServiceHandle(schService);
    CloseServiceHandle(schSCManager);
    return;
  }

  // Save the tick count and initial checkpoint.
  dwStartTickCount = GetTickCount();
  dwOldCheckPoint = ssStatus.dwCheckPoint;

  while (ssStatus.dwCurrentState == SERVICE_START_PENDING) {
    // Do not wait longer than the wait hint. A good interval is
    // one-tenth the wait hint, but no less than 1 second and no
    // more than 10 seconds.

    dwWaitTime = ssStatus.dwWaitHint / 10;
    if( dwWaitTime < 1000 )
        dwWaitTime = 1000;
    else if ( dwWaitTime > 10000 )
        dwWaitTime = 10000;

    Sleep( dwWaitTime );

    // Check the status again.
    if (!QueryServiceStatusEx(
        schService,             // handle to service
        SC_STATUS_PROCESS_INFO, // info level
        (LPBYTE) &ssStatus,             // address of structure
        sizeof(SERVICE_STATUS_PROCESS), // size of structure
        &dwBytesNeeded ) )              // if buffer too small
    {
      printf("QueryServiceStatusEx failed (%d)\n", GetLastError());
      break;
    }

    if ( ssStatus.dwCheckPoint > dwOldCheckPoint ) {
        // Continue to wait and check.
        dwStartTickCount = GetTickCount();
        dwOldCheckPoint = ssStatus.dwCheckPoint;
    } else {
      if(GetTickCount()-dwStartTickCount > ssStatus.dwWaitHint) {
        // No progress made within the wait hint.
        break;
      }
    }
  }

  // Determine whether the service is running.

  if (ssStatus.dwCurrentState == SERVICE_RUNNING)
  {
    printf("Service started successfully.\n");
  } else {
    printf("Service not started. \n");
    printf("  Current State: %d\n", ssStatus.dwCurrentState);
    printf("  Exit Code: %d\n", ssStatus.dwWin32ExitCode);
    printf("  Check Point: %d\n", ssStatus.dwCheckPoint);
    printf("  Wait Hint: %d\n", ssStatus.dwWaitHint);
  }

  CloseServiceHandle(schService);
  CloseServiceHandle(schSCManager);
}

void win32_service_status(void)
{
  SC_HANDLE schSCManager;
  SC_HANDLE schService;
  SERVICE_STATUS_PROCESS ssStatus;
  DWORD dwBytesNeeded;

  // Get a handle to the SCM database.
  schSCManager = OpenSCManager(
        NULL,                    // local computer
        NULL,                    // servicesActive database
        SC_MANAGER_ALL_ACCESS);  // full access rights
  if (NULL == schSCManager) {
    printf("OpenSCManager failed (%d)\n", GetLastError());
    return;
  }

  // Get a handle to the service.
  schService = OpenService(
        schSCManager,         // SCM database
        SVCNAME,              // name of service
        SERVICE_ALL_ACCESS);  // full access
  if (schService == NULL) {
    printf("OpenService failed (%d)\n", GetLastError());
    CloseServiceHandle(schSCManager);
    return;
  }

  // Check the status in case the service is not stopped.
  if (!QueryServiceStatusEx(
        schService,                     // handle to service
        SC_STATUS_PROCESS_INFO,         // information level
        (LPBYTE) &ssStatus,             // address of structure
        sizeof(SERVICE_STATUS_PROCESS), // size of structure
        &dwBytesNeeded ) )              // size needed if buffer is too small
  {
    printf("QueryServiceStatusEx failed (%d)\n", GetLastError());
    CloseServiceHandle(schService);
    CloseServiceHandle(schSCManager);
    return;
  }

  switch (ssStatus.dwCurrentState) {
  case SERVICE_CONTINUE_PENDING:
    printf("  Current State: Continue Pending\n");
    break;
  case SERVICE_PAUSE_PENDING:
    printf("  Current State: Pause Pending\n");
    break;
  case SERVICE_PAUSED:
    printf("  Current State: Paused\n");
    break;
  case SERVICE_RUNNING:
    printf("  Current State: Running\n");
    break;
  case SERVICE_START_PENDING:
    printf("  Current State: Start Pending\n");
    break;
  case SERVICE_STOP_PENDING:
    printf("  Current State: Stop Pending\n");
    break;
  case SERVICE_STOPPED:
    printf("  Current State: Stopped\n");
    break;
  default:
    printf("  Current State: %d\n", ssStatus.dwCurrentState);
    break;
  }

  printf("  Exit Code: %d\n", ssStatus.dwWin32ExitCode);
  printf("  Check Point: %d\n", ssStatus.dwCheckPoint);
  printf("  Wait Hint: %d\n", ssStatus.dwWaitHint);

  CloseServiceHandle(schService);
  CloseServiceHandle(schSCManager);
}

void win32_service_stop(void)
{
  SC_HANDLE schSCManager;
  SC_HANDLE schService;
  SERVICE_STATUS_PROCESS ssp;
  DWORD dwStartTime = GetTickCount();
  DWORD dwBytesNeeded;
  DWORD dwTimeout = 30000; // 30-second time-out
  DWORD dwWaitTime;

  // Get a handle to the SCM database.
  schSCManager = OpenSCManager(
      NULL,                    // local computer
      NULL,                    // ServicesActive database
      SC_MANAGER_ALL_ACCESS);  // full access rights
  if (NULL == schSCManager) {
    printf("OpenSCManager failed (%d)\n", GetLastError());
    return;
  }

  // Get a handle to the service.
  schService = OpenService(
      schSCManager,         // SCM database
      SVCNAME,              // name of service
      SERVICE_STOP |
      SERVICE_QUERY_STATUS |
      SERVICE_ENUMERATE_DEPENDENTS);
  if (schService == NULL) {
    printf("OpenService failed (%d)\n", GetLastError());
    CloseServiceHandle(schSCManager);
    return;
  }

  // Make sure the service is not already stopped.
  if ( !QueryServiceStatusEx(
          schService,
          SC_STATUS_PROCESS_INFO,
          (LPBYTE)&ssp,
          sizeof(SERVICE_STATUS_PROCESS),
          &dwBytesNeeded ) )
  {
    printf("QueryServiceStatusEx failed (%d)\n", GetLastError());
    goto stop_cleanup;
  }

  if ( ssp.dwCurrentState == SERVICE_STOPPED ) {
      printf("Service is already stopped.\n");
      goto stop_cleanup;
  }

  // If a stop is pending, wait for it.
  while ( ssp.dwCurrentState == SERVICE_STOP_PENDING ) {
    printf("Service stop pending...\n");

    // Do not wait longer than the wait hint. A good interval is
    // one-tenth of the wait hint but not less than 1 second
    // and not more than 10 seconds.
    dwWaitTime = ssp.dwWaitHint / 10;
    if( dwWaitTime < 1000 )
      dwWaitTime = 1000;
    else if ( dwWaitTime > 10000 )
      dwWaitTime = 10000;

    Sleep( dwWaitTime );

    if ( !QueryServiceStatusEx(
             schService,
             SC_STATUS_PROCESS_INFO,
             (LPBYTE)&ssp,
             sizeof(SERVICE_STATUS_PROCESS),
             &dwBytesNeeded ) ) {
      printf("QueryServiceStatusEx failed (%d)\n", GetLastError());
      goto stop_cleanup;
    }
    if ( ssp.dwCurrentState == SERVICE_STOPPED ) {
        printf("Service stopped successfully.\n");
        goto stop_cleanup;
    }

    if ( GetTickCount() - dwStartTime > dwTimeout ) {
        printf("Service stop timed out.\n");
        goto stop_cleanup;
    }
  }

  // Send a stop code to the service.
  if ( !ControlService(
          schService,
          SERVICE_CONTROL_STOP,
          (LPSERVICE_STATUS) &ssp ) ) {
    printf( "ControlService failed (%d)\n", GetLastError() );
    goto stop_cleanup;
  }

  // Wait for the service to stop.
  while ( ssp.dwCurrentState != SERVICE_STOPPED ) {

    Sleep( ssp.dwWaitHint );

    if ( !QueryServiceStatusEx(
            schService,
            SC_STATUS_PROCESS_INFO,
            (LPBYTE)&ssp,
            sizeof(SERVICE_STATUS_PROCESS),
            &dwBytesNeeded ) ) {
      printf( "QueryServiceStatusEx failed (%d)\n", GetLastError() );
      goto stop_cleanup;
    }
    if ( ssp.dwCurrentState == SERVICE_STOPPED )
        break;

    if ( GetTickCount() - dwStartTime > dwTimeout ) {
        printf( "Wait timed out\n" );
        goto stop_cleanup;
    }
  }
  printf("Service stopped successfully\n");

stop_cleanup:
  CloseServiceHandle(schService);
  CloseServiceHandle(schSCManager);
}

#endif /* _WIN32 */
