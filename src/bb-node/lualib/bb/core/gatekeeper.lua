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

local base = require "bb.core.base"
local io = io
local os = os
local shell = require "bb.thirdparty.resty.shell"

local _conf = {}
local access_table = {
  access = "bb.plugins.access.",
  ratelimiter = "bb.plugins.access.",
  router = "bb.plugins.access."
}

local error_table = {
  fallback = "bb.plugins.error.",
}

local phase_table = {
  access = access_table,
  error = error_table,
}

local function load_conf(filename)
  local file, err = io.open(filename, "r")
  local data = nil
  if file ~= nil then
    local contents = file:read("*a")
    if contents ~= nil and contents ~= '' then
      data = cjson.decode(contents)
    end
    file:close()
  end

  if data == nil then
    return nil, "empty data found!"
  end
  return data
end

local function get_conf(name)
  return _conf[name]
end

local function is_pull_mode()
  if _conf["cluster_id"] ~= nil then
    return true
  end
  return false
end

local function get_modules()
  return phase_table
end

local function get_module_path(name, phase)
  local module_table = phase_table[phase]
  if not module_table then
    return nil
  end
  local path = module_table[name]
  path = base.path .. string.gsub(path, "%.", "/")
  return path
end

local function get_rule_file(name, phase)
  local path = get_module_path(name, phase)
  local filename = path .. name .. ".rules"
  return filename
end

local function get_version_file()
  local filename = ngx.config.prefix() .. "/conf/config.version"
  return filename
end

local function get_nginx_conf_file()
  local filename = ngx.config.prefix() .. "/conf/nginx.conf"
  return filename
end

local function phase_init(phase, phase_tb)
  for name, path in pairs(phase_tb) do
    local module_name = path .. name
    local ok, mod = pcall(require, module_name)
    if not ok then
      error("Failed to init module:" .. module_name.. " error..."..mod)
    else
      local filename = get_rule_file(name, phase)
      ngx.log(ngx.INFO, "module:" .. name .. " rule file:" .. filename)
      mod.init(filename)
    end -- if else ends here
  end -- for loop ends
end

local function phase_exec(phase, phase_tb)
  for name, path in pairs(phase_tb) do
    local module_name = path .. name
    local ok, mod = pcall(require, module_name)
    if not ok then
      error(ngx.ERR, "Failed to execute phase:" .. phase .. " module:" .. module_name.. " error ..." ..mod)
    else
      mod.exec()
    end -- if else ends here
  end -- for loop ends here
end

local function update_nginx_config()
  -- need to support later
  return { status = ngx.HTTP_BAD_REQUEST, msg =  "Thanks for using this method, under developement!!" }
end

local function update_plugin_config(name, phase)
  -- read json body as data param
  ngx.req.read_body()  -- explicitly read the req body
  local data = cjson.decode(ngx.req.get_body_data())

  -- write data to file after aquiring lock
  local path = get_module_path(name, phase)
  if not path then
    return { status = ngx.HTTP_BAD_REQUEST, msg =  "Un-supported module update!!" }
  end

  -- aquired lock here
  -- note :
  -- ideally this method should happen in sequence, and so lock not require.
  -- this is added for safety. There won't be waiting time here!!
  local lock = require "resty.lock"
  local lock = lock:new("config_locks", {exptime = 5})
  local elapsed, err = lock:lock("plugin")
  if not elapsed then
    ngx.log(ngx.ERR, err)
    return { status = ngx.HTTP_INTERNAL_SERVER_ERROR, msg = "failed to acquire the lock. try again!!" }
  end
  ngx.log(ngx.INFO, "elapsed time:" .. elapsed)

  -- write data to file
  local filename = path .. name .. ".rules"
  local file, err = io.open(filename, "w")
  if not file then
    ngx.log(ngx.ERR, err)
    return { status = ngx.HTTP_INTERNAL_SERVER_ERROR, msg =  "Runtime error, failed to update config" }
  end

  file:write(cjson.encode(data))
  file:close()

  -- release the lock
  local ok, err = lock:unlock()
  if not ok then
    ngx.log(ngx.ERR, "failed to unlock")
  end
  return { status = ngx.HTTP_OK, msg =  "Successfully updated the config!!" }
end

local function config_update_handler()
  -- check for POST method
  local method = ngx.req.get_method()
  if not method or method ~= "POST" then
    return { status = ngx.HTTP_BAD_REQUEST, msg =  "Un-supported Method, Expecting POST request!!" }
  end

  -- check for config type (nginx/plugin config)
  local args = ngx.req.get_uri_args()
  if not args.type then
    return { status = ngx.HTTP_BAD_REQUEST, msg =  "Request missing argument type of config!!" }
  end

  -- update appropriate config
  if args.type == "nginx" then
    -- return update_nginx_config()
    return { status = ngx.HTTP_NOT_ALLOWED, msg = "Update of config is not allowed in this version."}
  elseif args.type == "plugin" then
    if not args.name then
      return { status = ngx.HTTP_BAD_REQUEST, msg =  "Mising mandatory request params : name" }
    elseif not args.phase then
      return { status = ngx.HTTP_BAD_REQUEST, msg =  "Mising mandatory request param : phase" }
    end
    return update_plugin_config(args.name, args.phase)
  else
    return { status = ngx.HTTP_BAD_REQUEST, msg =  "Un-supported config typed requested!!" }
  end
end

function reload_config()
  local filename = "/var/run/bloomgateway.openresty.pid"
  local cmd = "cat " .. filename .. " | xargs kill -s HUP "
  local status, output, err = shell.execute(cmd)
  if status ~= 0 then
    ngx.log(ngx.ERR, err)
    return { status = ngx.HTTP_INTERNAL_SERVER_ERROR, msg = "Failed to uploaded new config!!" }
  end
  ngx.log(ngx.INFO, output)
  return { status = ngx.HTTP_OK, msg = "Successfully uploaded the config" }
end

-- expose functionality via this module
local _M = { version = base.version }

function _M.init()
  -- load gk.conf
  local filename = ngx.config.prefix() .. "/conf/gk.conf"
  ngx.log(ngx.INFO, "gk_conf:", filename)
  local data, err = load_conf(filename)
  if not data then
    ngx.log(ngx.ERR, "Failure in loading gatekeeper conf with err:", err)
    error "Failure in loading gatekeeper conf"
  end
  _conf = data

  -- init all the module for all the phases
  for phase, phase_tb in pairs(phase_table) do
    ngx.log(ngx.INFO, "initializing phase " .. phase)
    ok, err = pcall(phase_init, phase, phase_tb)
    if not ok then
      ngx.log(ngx.ERR, "init failure message: " .. tostring(err))
      error ("Failure in initializing the phase:" .. phase)
    end
  end
end

function _M.exec(phase)
  -- see if the supported phase
  local phase_tb = phase_table[phase]
  if phase_tb == nil then
    error ("Accessed non-supported phase:" .. phase)
  end
  -- execute the request phase
  ok, err = pcall(phase_exec, phase, phase_tb)
  if not ok then
    ngx.log(ngx.ERR, "exec failure message: " .. tostring(err))
    error ("Failed to execute the phase:" .. phase)
  end
end

function _M.get_ext_module_path(name, phase)
  -- need to be implemented
  return nil
end

function _M.handler()
  -- checks the service is running with PUSH mode
  if is_pull_mode() == true then
    ngx.status = ngx.HTTP_NOT_ALLOWED
    ngx.say("Service is running with PULL config update mode!!")
    ngx.exit(res.status)
  end

  -- update config to appropriate file
  local res = config_update_handler()
  if res.status ~= ngx.HTTP_OK then
    ngx.status = res.status
    ngx.say(res.msg)
    ngx.exit(res.status)
  end

  -- if no error reload the config
  local res = reload_config()
  ngx.status = res.status
  ngx.say(res.msg)
  ngx.exit(res.status)

end

_M.get_modules = get_modules
_M.get_version_file = get_version_file
_M.get_conf = get_conf
_M.get_nginx_conf_file = get_nginx_conf_file
_M.get_rule_file = get_rule_file
_M.is_pull_mode = is_pull_mode

return _M