--                                                                                                                                                                            --  Copyright 2012 Rackspace
--
--  Licensed under the Apache License, Version 2.0 (the "License");
--  you may not use this file except in compliance with the License.
--  You may obtain a copy of the License at
--
--      http://www.apache.org/licenses/LICENSE-2.0
--
--  Unless required by applicable law or agreed to in writing, software
--  distributed under the License is distributed on an "AS IS" BASIS,
--  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
--  See the License for the specific language governing permissions and
--  limitations under the License.
--

module(..., package.seeall);
local alien = require 'alien'
local util = require 'util'
local Check = util.Check
local log = util.log
local os = require 'os'
local struct = require 'alien.struct'

local stats = {
  {"GetCpuReservationMHz","ref uint","cpu_reservation_mhz",Check.enum.uint32},
  {"GetCpuLimitMHz","ref uint","cpu_limit_mhz",Check.enum.uint32},
  {"GetCpuShares","ref uint","cpu_shares",Check.enum.uint32},
  {"GetCpuUsedMs","pointer","cpu_used_ms",Check.enum.gauge},
  {"GetHostProcessorSpeed","ref uint","host_processor_speed",Check.enum.uint32},
  {"GetMemReservationMB","ref uint","mem_reservation_mb",Check.enum.uint32},
  {"GetMemLimitMB","ref uint","mem_limit_mb",Check.enum.uint32},
  {"GetMemShares","ref uint","mem_shares",Check.enum.uint32},
  {"GetMemMappedMB","ref uint","mem_mapped_mb",Check.enum.uint32},
  {"GetMemActiveMB","ref uint","mem_active_mb",Check.enum.uint32},
  {"GetMemOverheadMB","ref uint","mem_overhead_mb",Check.enum.uint32},
  {"GetMemBalloonedMB","ref uint","mem_ballooned_mb",Check.enum.uint32},
  {"GetMemSwappedMB","ref uint","mem_swapped_mb",Check.enum.uint32},
  {"GetMemSharedMB","ref uint","mem_shared_mb",Check.enum.uint32},
  {"GetMemSharedSavedMB","ref uint","mem_shared_saved_mb",Check.enum.uint32},
  {"GetMemUsedMB","ref uint","mem_used_mb",Check.enum.uint32},
  {"GetElapsedMs","pointer","elapsed_ms",Check.enum.gauge},
  {"GetCpuStolenMs","pointer","cpu_stolen_ms",Check.enum.gauge},
  {"GetMemTargetSizeMB","pointer","mem_target_size_mb",Check.enum.uint64},
  {"GetHostNumCpuCores","pointer","host_numcpu_cores",Check.enum.uint64},
  {"GetHostCpuUsedMs","pointer","host_cpuused_ms",Check.enum.gauge},
  {"GetHostMemSwappedMB","pointer","host_memswapped_mb",Check.enum.uint64},
  {"GetHostMemSharedMB","pointer","host_memshared_mb",Check.enum.uint64},
  {"GetHostMemUsedMB","pointer","host_memused_mb",Check.enum.uint64},
  {"GetHostMemPhysMB","pointer","host_memphys_mb",Check.enum.uint64},
  {"GetHostMemPhysFreeMB","pointer","host_memphys_free_mb",Check.enum.uint64},
  {"GetHostMemKernOvhdMB","pointer","host_memkern_ovhd_mb",Check.enum.uint64},
  {"GetHostMemMappedMB","pointer","host_memmapped_mb",Check.enum.uint64},
  {"GetHostMemUnmappedMB","pointer","host_memunmapped_mb",Check.enum.uint64},
}

local ptrptr = alien.defstruct{
  { "ptr", "pointer" },
}

local ulongptr = alien.defstruct{
  { "val", "ulong" },
}

local uintptr = alien.defstruct{
  { "val", "uint" },
}

local VMGUESTLIB_ERROR_SUCCESS = 0                 -- No error
local VMGUESTLIB_ERROR_OTHER = 1                   -- Other error
local VMGUESTLIB_ERROR_NOT_RUNNING_IN_VM = 2       -- Not running in a VM
local VMGUESTLIB_ERROR_NOT_ENABLED = 3             -- GuestLib not enabled on the host.
local VMGUESTLIB_ERROR_NOT_AVAILABLE = 4           -- This stat not available on this host.
local VMGUESTLIB_ERROR_NO_INFO = 5                 -- UpdateInfo() has never been called.
local VMGUESTLIB_ERROR_MEMORY = 6                  -- Not enough memory
local VMGUESTLIB_ERROR_BUFFER_TOO_SMALL = 7        -- Buffer too small
local VMGUESTLIB_ERROR_INVALID_HANDLE = 8          -- Handle is invalid
local VMGUESTLIB_ERROR_INVALID_ARG = 9             -- One or more arguments were invalid
local VMGUESTLIB_ERROR_UNSUPPORTED_VERSION = 10    -- The host doesnt support this request

local function get_vmware(path)
  local vmware = alien.load(path .. "/vmGuestLib")
  local err

  -- Open Handle
  --VMGuestLibError VMGuestLib_OpenHandle(VMGuestLibHandle *handle); // OUT
  --VMGuestLibError VMGuestLib_CloseHandle(VMGuestLibHandle handle); // IN

  vmware.VMGuestLib_OpenHandle:types("int", "pointer")
  vmware.VMGuestLib_CloseHandle:types("int", "pointer")
  -- Update info
  -- VMGuestLibError VMGuestLib_UpdateInfo(VMGuestLibHandle handle); // IN
  vmware.VMGuestLib_UpdateInfo:types("int", "pointer")
  -- VMGuestLibError VMGuestLib_GetSessionId(VMGuestLibHandle handle,  // IN
  --                                      VMSessionId *id);         // OUT
  vmware.VMGuestLib_GetSessionId:types("int", "pointer", "pointer")
  -- char const * VMGuestLib_GetErrorText(VMGuestLibError error); // IN
  vmware.VMGuestLib_GetErrorText:types("string", "int")

  -- Iterate over all the VM Guest lib
  for key, value in pairs(stats) do
    vmware["VMGuestLib_" .. value[1]]:types("int", "pointer", value[2])

  end

  return vmware
end

function vm_err_out(vmware, msg, err)
    local fmt = msg .. ": " .. vmware.VMGuestLib_GetErrorText(err)
    return fmt
end

function record_stat(rcheck, vmware, vmgl_handle, func, alien_type,
    metric, metric_type, args)
  local value, err

  -- Since most all are ref types, pass the value back
  if alien_type == "pointer" then
    -- Allocate the right buffer
    local ptr
    if metric_type == Check.enum.uint64 then
      ptr = ulongptr:new() 
    else
      ptr = uintptr:new()
    end
    err = vmware["VMGuestLib_" .. func](vmgl_handle, ptr())
    -- Unpack the value?
    value = ptr.val
  else
    err, value = vmware["VMGuestLib_" .. func](vmgl_handle, value)
  end

  -- Check the error code
  if err ~= VMGUESTLIB_ERROR_SUCCESS then
    -- Don't record it
    --rcheck:set_error("unable to get " .. metric)
    return err
  end
  -- Record the actual metric
  rcheck:add_metric(metric, value, metric_type)
  return err
end

function run(rcheck, args)

  if equus.p_is_windows() == 1 then
    rcheck:set_error("vmware guest API check is not supported on windows")
    return rcheck
  end

  if args.path == nil then
    args.path = '/usr/lib'
  else
    args.path = args.path[1]
  end

  local vmgl_handle
  local vmware = get_vmware(args.path)

  -- TODO: The right way to allocate a pointer of a pointer?
  vmgl_handle = ptrptr:new()

  -- Open the handle to the new session
  err = vmware.VMGuestLib_OpenHandle(vmgl_handle())
  if err ~= VMGUESTLIB_ERROR_SUCCESS then
    rcheck:set_error(vm_err_out(vmware, "unable to open handle", err))
    return rcheck
  end

  run_check(vmware, args, rcheck, vmgl_handle)

  err = vmware.VMGuestLib_CloseHandle(vmgl_handle.ptr)
  if err ~= VMGUESTLIB_ERROR_SUCCESS then
    rcheck:set_error(vm_err_out(vmware, "unable to close handle", err))
    return rcheck
  end

end

function run_check(vmware, args, rcheck, vmgl_handle)

  local vmgl_session, err, test
  local i = 0

  vmgl_session = ulongptr:new()

  -- Attempt to retrieve the session info 
  err = vmware.VMGuestLib_UpdateInfo(vmgl_handle.ptr)
  if err ~= VMGUESTLIB_ERROR_SUCCESS then
    rcheck:set_error(vm_err_out(vmware, "update info failed", err))
    return rcheck
  end
  
  -- Open the session
  err = vmware.VMGuestLib_GetSessionId(vmgl_handle.ptr, vmgl_session())
  if err ~= VMGUESTLIB_ERROR_SUCCESS then
    rcheck:set_error(vm_err_out(vmware, "failed to get the session id", err))
    return rcheck
  end

  if vmgl_session.val == VMGUESTLIB_ERROR_SUCCESS then
    rcheck:set_error("error: session id returned 0")
    return rcheck
  end


  -- Ready to start collecting some data
  for key, value in pairs(stats) do
    err = record_stat(rcheck, vmware, vmgl_handle.ptr, value[1],
        value[2], value[3], value[4], args)
    if err ~= VMGUESTLIB_ERROR_SUCCESS then
      if err == VMGUESTLIB_ERROR_UNSUPPORTED_VERSION or
          err == VMGUESTLIB_ERROR_NOT_AVAILABLE then
        -- Don't do anything
      else
        rcheck:set_error("error retrieving %s", value[1])
        return rcheck
      end
    else
      i = i + 1
    end
  end

  -- Set the status
  rcheck:set_status("tracking %d metrics successfully", i)
  return rcheck
end
