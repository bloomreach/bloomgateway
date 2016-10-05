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

-- all the system specifc global modules
cjson = require "cjson"

-- all bb specific global modules
shmem = require "bb.core.shmem"


-- return code version
-- <major version number>.<minior version number>.<sub version number>

local _M = {}

_M.version = "0.10.4"
_M.path = ngx.config.prefix() .. "../bb/lualib/"

return _M
