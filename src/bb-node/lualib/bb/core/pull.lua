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

local cjson = require "cjson"
local shmem = require "bb.core.shmem"
local gk = require "bb.core.gatekeeper"
local shell = require "bb.thirdparty.resty.shell"
local string = string
local log = ngx.log
local ERR = ngx.ERR
local INFO = ngx.INFO

local PULL_ID = "pull_id"
local DELAY = 5
local NGINX = "nginx"
local types = {CONF="nginx_conf", VERSION="version", MODULES="modules"}
local VERSION_FILE = "version.json"
local NGINX_CONF_FILE = "nginx.conf"

local _config_version = {}

local function set_config_version(data)
  _config_version = data
end

local function get_nginx_conf_version()
  return _config_version[types.CONF]
end

local function get_modules_version()
  return _config_version[types.MODULES]
end

local function set_timer(delay, func)
  local timer = ngx.timer.at
  local ok, err = timer(delay, func)
  if not ok then
    log(ERR, "failed to create timer: ", err)
  end
end

local function get_version(filename)
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
    return nil, "Failed to get version information!"
  end
  return data
end

local function get_s3_path(type, name, phase, version)
  local s3file = nil
  local cluster_id = gk.get_conf("cluster_id")
  local s3basepath = gk.get_conf("s3basepath")

  if type == types.CONF and name == NGINX then
    s3file = string.format("%s/%s/conf/%s/%s", s3basepath, cluster_id, version, NGINX_CONF_FILE)
  elseif type == types.MODULES then
    s3file = string.format("%s/%s/modules/%s/%s/%s/%s.rules", s3basepath, cluster_id, phase, name, version, name)
  elseif type == types.VERSION then
    s3file = string.format("%s/%s/%s", s3basepath, cluster_id, VERSION_FILE)
  end

  log(INFO, "s3file:", s3file)
  return s3file
end

local function fetch_from_s3(s3file, localfile)
  local cmd = string.format("s3cmd get %s /tmp/%s -f", s3file, localfile)
  local status, output, err = shell.execute(cmd)
  if status ~= 0 then
    log(ERR, err)
    error (string.format("cmd:%s failed with error code:%d", cmd, status))
  end
  log(INFO, output)
  return
end

local function copy_config(src, dest)
  local cmd = string.format("cp /tmp/%s %s", src, dest)
  local status, output, err = shell.execute(cmd)
  if status ~= 0 then
    log(ERR, err)
    error (string.format("cmd:%s failed with error code:%d", cmd, status))
  end
  log(INFO, output)
  return
end

local function is_changed(type, name, phase, data)
  local cur_ver = nil
  local new_ver = nil

  if type == types.CONF and name == NGINX then
    cur_ver = _config_version[types.CONF]
    new_ver = data[types.CONF]
  elseif type == types.MODULES then
    cur_ver = _config_version.modules[phase][name]
    new_ver = data.modules[phase][name]
  end

  if new_ver ~= nil and cur_ver ~= nil and cur_ver ~= new_ver then
    return true, new_ver
  end
  return false, cur_ver
end

local function get_changed(modules, data)
  local changed = nil
  -- check for nginx conf
  local ok, version = is_changed(types.CONF, NGINX, nil, data)
  if ok then
    if changed == nil then changed = {} end
    changed[types.CONF] = version
  end

  -- check for registered module
  for phase, phase_table in pairs(modules) do
    for name, path in pairs(phase_table) do
      local ok, version = is_changed(types.MODULES, name, phase, data)
      if ok then
        if changed == nil then changed = {} end
        if changed[types.MODULES] == nil then changed[types.MODULES] = {} end
        if changed.modules[phase] == nil then changed.modules[phase] = {} end
        changed.modules[phase][name] = version
      end
    end -- inner loop
  end -- outer most loop ends here

  return changed
end

local function fetch_changed(changed)
  -- fetch nginx
  if changed[types.CONF] ~= nil then
    local s3file = get_s3_path(types.CONF, NGINX, nil, changed[types.CONF])
    fetch_from_s3(s3file, NGINX_CONF_FILE)
  end
  -- fetch modules
  if changed.modules ~= nil then
    for phase, phase_table in pairs(changed.modules) do
      for name, version in pairs(phase_table) do
        local s3file = get_s3_path(types.MODULES, name, phase, version)
        local localfile = string.format("%s_%s", name, phase)
        fetch_from_s3(s3file, localfile)
      end
    end
  end
end

local function update_changed(changed)
  log(INFO, "calling update_changed!")
  -- update nginx
  if changed[types.CONF] ~= nil then
    copy_config(NGINX_CONF_FILE, gk.get_nginx_conf_file())
  end
  -- update modules files
  if changed.modules ~= nil then
    for phase, phase_table in pairs(changed.modules) do
      for name, version in pairs(phase_table) do
        local localfile = string.format("%s_%s", name, phase)
        copy_config(localfile, gk.get_rule_file(name, phase))
      end
    end
  end
  -- update version file
  copy_config(VERSION_FILE, gk.get_version_file())
end

local function reload_changed()
  log(INFO, "calling reload_changed!!")
  -- read the pid
  -- local filename = ngx.config.prefix() .. "/logs/nginx.pid"
  local filename = "/var/run/bloomgateway.openresty.pid"
  local cmd = "cat " .. filename .. " | xargs kill -s HUP "
  log(INFO, cmd)
  local status, output, err = shell.execute(cmd)
  if status ~= 0 then
    log(ERR, err)
    error "Failed to reload config!!"
  end
  log(INFO, output)
  return
end

local function check(pid)
  -- fetch version file (s3cmd get s3path/version.json /tmp/version.json)
  local s3file = get_s3_path(types.VERSION)
  fetch_from_s3(s3file, VERSION_FILE)

  -- load fetched version data
  local version_file = string.format("/tmp/%s", VERSION_FILE)
  local data = get_version(version_file)
  local changed = get_changed(gk.get_modules(), data)
  if changed ~= nil then
    fetch_changed(changed)
    update_changed(changed)
    reload_changed()
  end
  log(INFO, "Nothing has changed!!")
end

local function validate(premature, pid)
  if premature then
    return nil, "premature timer!"
  end

  local pull_id = shmem.get(PULL_ID)
  if pull_id == nil then
    shmem.set(PULL_ID, pid)
  end

  if pull_id ~= pid then
    return nil, "I am not the responsible for pull job!"
  end

  return pid, nil
end

local function handler(premature)
  local pid = ngx.worker.pid()

  -- validate
  local ok, err = validate(premature, pid)
  if not ok then
    log(ngx.ERR, "pid=", pid, " msg:", err)
    set_timer(DELAY, handler)
    return
  end

  -- handle version check
  local ok, err = pcall(check)
  if not ok then
    log(ngx.ERR, "Failed to do version check with err ", err)
  end

  -- reset the timer
  set_timer(DELAY, handler)

end

local function load_config_version()
  filename = gk.get_version_file()
  return get_version(filename)
end

local function init()
  if gk.is_pull_mode() == false then
    log(INFO, "Service is running with PUSH config update mode!!")
    return
  end

  shmem.set(PULL_ID, nil)

  local data, err = load_config_version()
  if not data then
    log(ERR, "Failure:", err)
    return
  end

  set_config_version(data)
  set_timer(DELAY, handler)
end

local function get_config()
  if gk.is_pull_mode() == false then
    log(INFO, "Service is running with PUSH config update mode, return an empty object!!")
  end
  return cjson.encode(_config_version)
end

-- pull module's exponsed methods
local _M = {}
_M.init = init
_M.config = get_config
return _M
