--                                                                                                                                                                            
--  Copyright 2012 Rackspace
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
--


module(..., package.seeall);

local http = require 'socket.http'

local function load(modulename)
  local url = equus.equus_url()
  url = url .. modulename
  local luaurl = url .. ".lua"
  local mod = luaurl:gmatch(".*/(.*)")()
  
  local rv,data = pcall(equus_local_cache_get, mod);
  if rv == true then
    return data
  end

  local sigurl = url .. ".sig"
  --equus.equus_log(equus.EQUUS_LOG_DEBUG, "loading package url: "..luaurl)
  data,datac,h =  http.request(luaurl)
  sig,sigc,h = http.request(sigurl)

  assert(sig ~= nil, "Signature is null")
  assert(sigc ~= "200", "Signature http code is not 200")
  assert(data ~= nil, "Data is null")
  assert(datac ~= "200", "Data http code is not 200")

  local rc = equus.equus_verify(data, data:len(), sig, sig:len(), "", 0)
  assert(rc == 0,"module "..modulename.." (from '"..luaurl.."')"
            .." signature does not verify")
  equus_local_cache_add(mod, data);
  return equus_local_cache_get(mod);
end

return load