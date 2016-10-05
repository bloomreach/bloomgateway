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

local io = require 'io'
local os = require 'os'
local shmem = require "bb.core.shmem"
local bb = require "bb.core.gatekeeper"

local _rate_limit_node = {}
local _rate_limit_api = {}
local _rate_limit_param = {}
local _rate_limit_params_key_values = {}
local _rate_limit_header = {}
local _rate_limit_headers_key_values = {}


local function build_threshold_key(api, field_type, field_name, field_value)
  return api .. field_type .. field_name .. field_value
end

local function process_node_rule(rule)
  _rate_limit_node["node"] = tonumber(rule["threshold"])
end

local function process_api_rule(rule)
  _rate_limit_api[rule["api"]] = tonumber(rule["threshold"])
end

local function process_param_rule(rule)
  local api_param_rule_key = build_threshold_key(rule["api"], "param", rule["key"], rule["value"])
  _rate_limit_param[api_param_rule_key] = tonumber(rule["threshold"])

  if _rate_limit_params_key_values[rule["api"]] == nil then
    _rate_limit_params_key_values[rule["api"]] = {}
  end

  if _rate_limit_params_key_values[rule["api"]][rule["key"]] == nil then
    _rate_limit_params_key_values[rule["api"]][rule["key"]] = {}
  end

  _rate_limit_params_key_values[rule["api"]][rule["key"]][rule["value"]] = true
end

local function process_header_rule(rule)
  local api_header_rule_key = build_threshold_key(rule["api"], "header", rule["key"], rule["value"])
  _rate_limit_header[api_header_rule_key] = tonumber(rule["threshold"])

  if _rate_limit_headers_key_values[rule["api"]] == nil then
    _rate_limit_headers_key_values[rule["api"]] = {}
  end

  if _rate_limit_headers_key_values[rule["api"]][rule["key"]] == nil then
    _rate_limit_headers_key_values[rule["api"]][rule["key"]] = {}
  end

  _rate_limit_headers_key_values[rule["api"]][rule["key"]][rule["value"]] = true
end

local function process_rule(rule)
  local rule_type = rule["type"]

  if(rule_type == "node") then
    process_node_rule(rule)
  elseif(rule_type == "api") then
    process_api_rule(rule)
  elseif(rule_type == "param") then
    process_param_rule(rule)
  elseif(rule_type == "header") then
    process_header_rule(rule)
  end
end

local function check_for_rate_limiting_rule(rule_key, threshold)

  if threshold == nil then -- no threshold defined
    return
  end

  if(shmem.get(rule_key) == nil) then
    shmem.set_with_expiry(rule_key, 1)
  elseif(shmem.get(rule_key) >= threshold) then
    ngx.status = ngx.HTTP_TOO_MANY_REQUESTS
    ngx.say("Request threshold reached, please try again later")
    ngx.exit(ngx.status)
  else
    shmem.incr(rule_key, 1)
  end
end

local function get_key_for_node_rule(hour, min)
  return hour .. min
end

local function get_key_for_api_rule(api, hour, min)
  return api .. hour .. min
end

local function get_key_for_param_rule(api, name, value, hour, min)
  return build_threshold_key(api, 'param', name, value) .. hour .. min
end

local function get_key_for_header_rule(api, name, value, hour, min)
  return build_threshold_key(api, 'header', name, value) .. hour .. min
end

local function perform_node_level_rate_limit(hour, min)
  local threshold_key = "node"
  local rule_key = get_key_for_node_rule(hour, min)
  local threshold = _rate_limit_node[threshold_key]
  check_for_rate_limiting_rule(rule_key, threshold)
end

local function perform_api_level_rate_limit(api, hour, min)
  local threshold_key = api
  local rule_key = get_key_for_api_rule(api, hour, min)
  local threshold = _rate_limit_api[threshold_key]
  check_for_rate_limiting_rule(rule_key, threshold)
end

local function perform_param_based_rate_limiting(api, name, value, hour, min, threshold)
  local rule_key = get_key_for_param_rule(api, name, value, hour, min)
  check_for_rate_limiting_rule(rule_key, threshold)
end

local function perform_header_based_rate_limiting(api, name, value, hour, min, threshold)
  local rule_key = get_key_for_header_rule(api, name, value, hour, min)
  check_for_rate_limiting_rule(rule_key, threshold)
end

local function begin_params_rate_limiting(name, value, api, hour, min)
  local threshold = _rate_limit_param[build_threshold_key(api, "param", name, value)]
  if threshold ~= nil then
    perform_param_based_rate_limiting(api, name, value, hour, min, threshold)
  else
    threshold = _rate_limit_param[build_threshold_key(api, "param", name, "*")] -- check base rule if any
    if threshold ~= nil then
      perform_param_based_rate_limiting(api, name, value, hour, min, threshold)
    end
  end
end

local function begin_headers_rate_limiting(name, value, api, hour, min)
  local threshold = _rate_limit_header[build_threshold_key(api, "header", name, value)]
  if threshold ~= nil then
    perform_header_based_rate_limiting(api, name, value, hour, min, threshold)
  else
    threshold = _rate_limit_header[build_threshold_key(api, "header", name, "*")] -- check base rule if any
    if threshold ~= nil then
      perform_header_based_rate_limiting(api, name, value, hour, min, threshold)
    end
  end
end

local function has_multiple_values(arg_value)
  return type(arg_value) == "table"
end

local function does_value_exists(values, value)
  for _, scalar_value in pairs(values) do
    if scalar_value == value then
      return true
    end
  end
  return false
end


-- exponse module functionality
local _M = {}

function _M.init(rule_file)
  ngx.log(ngx.INFO, "rate limiter init begin")
  local io = io
  local rule_file = rule_file
  local file, err = io.open(rule_file, "r")

  if file ~= nil then
    local contents = file:read("*a")
    local value = {}

    if contents ~= nil and contents ~= '' then
      value = cjson.decode(contents)
    end

    for _, rule in pairs(value) do
      process_rule(rule)
    end

    file:close()
  end
  ngx.log(ngx.INFO, "rate limiter init complete")
end

function _M.exec()
  ngx.log(ngx.INFO, "rate limiter execute begin")

  local hour = os.date("%H")
  local min = os.date("%M")

  local api = ngx.var.uri
  local args = ngx.req.get_uri_args()
  local headers = ngx.req.get_headers()

  --perform node level rate limiting--
  perform_node_level_rate_limit(hour, min)

  --perform api level rate limiting--
  local threshold = _rate_limit_api[api]
  if threshold ~= nil then
    perform_api_level_rate_limit(api, hour, min)
  end

  --perform arg level rate limiting for configured params
  if _rate_limit_params_key_values[api] ~= nil then
    local rules_api = _rate_limit_params_key_values[api]
    for rule_key, rule_values in pairs(rules_api) do
      if args[rule_key] ~= nil then
        local arg_value = args[rule_key]
        local defined_param_rule_applied = false
        local apply_generic_rule_param = false
        for rule_value, _ in pairs(rule_values) do
          if has_multiple_values(arg_value) then
            if does_value_exists(arg_value, rule_value) then
              begin_params_rate_limiting(rule_key, rule_value, api, hour, min)
            end
          else
            if arg_value == rule_value then
              defined_param_rule_applied = true
              begin_params_rate_limiting(rule_key, rule_value, api, hour, min)
            elseif rule_value == '*' then
              apply_generic_rule_param = true
            end
          end
        end
        --TODO only handling the case for single value for param, need to handle the case for multiple values sent for some param separately
        if(has_multiple_values(arg_value) == false and apply_generic_rule_param and (defined_param_rule_applied == false)) then
          begin_params_rate_limiting(rule_key, arg_value, api, hour, min)
        end
      end
    end
  end

  --perform header level rate limiting for configured headers
  if _rate_limit_headers_key_values[api] ~= nil then
    for rule_key, rule_values in pairs(_rate_limit_headers_key_values[api]) do
      if headers[rule_key] ~= nil then
        local header_value = headers[rule_key]
        local defined_header_rule_applied = false
        local apply_generic_rule_header = false
        for rule_value, _ in pairs(rule_values) do
          if rule_value == header_value then
            defined_header_rule_applied = true
            begin_headers_rate_limiting(rule_key, header_value, api, hour, min)
          elseif rule_value == "*" then
            apply_generic_rule_header = true
          end
        end
        if(apply_generic_rule_header and (defined_header_rule_applied == false)) then
          begin_headers_rate_limiting(rule_key, header_value, api, hour, min)
        end
      end
    end
  end

  --perform specific IP level rate limiting--
  local client_ip = ngx.var.remote_addr
  local threshold = _rate_limit_header[build_threshold_key(api, "header", "remote_addr", client_ip)]
  if threshold ~= nil then
    perform_header_based_rate_limiting(api, "remote_addr", client_ip, hour, min, threshold)
  end
  ngx.log(ngx.INFO, "rate limiter execute complete")
end

return _M
