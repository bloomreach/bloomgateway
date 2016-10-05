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

local const = {
    EXP_TIME = 60,
}

function _M.get(key)
    return ngx.shared.shared_mem:get(key)
end

function _M.set(key, value)
    ngx.shared.shared_mem:flush_expired() -- clear memory occupied by expired keys before taking more memory with set
    ngx.shared.shared_mem:set(key, value)
end

function _M.set_with_expiry(key, value)
    ngx.shared.shared_mem:set(key, value, const.EXP_TIME)
end

function _M.incr(key)
    ngx.shared.shared_mem:incr(key, 1)
end

function _M.flush_expired()
    ngx.shared.shared_mem:flush_expired()
end

function _M.get_all_keys()
    return ngx.shared.shared_mem:get_keys(0)
end

return _M

