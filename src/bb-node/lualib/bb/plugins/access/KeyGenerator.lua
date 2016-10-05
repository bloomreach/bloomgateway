--[[
Copyright 2016 BloomReach, Inc.
Copyright 2016 Ronak Kothari <ronak.kothari@gmail.com>.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
--]]
local _M = {}

function _M.generate_key(key, table)
  local new_key = key
  if(table["header_name"] ~= nil) then
    new_key = key.."_header_name".."_"..table["header_name"].."_"..table["header_value"]
  elseif(table["param_name"] ~= nil) then
    new_key =  key.."_param_name_"..table["param_name"].."_"..table["param_value"]
  end
  return new_key
end

return _M
