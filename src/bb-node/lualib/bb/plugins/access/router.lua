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

local _router_params_key_values = {}
local _router_headers_key_values = {}

local _exact_values = "exact_values"
local _regex_values = "regex_values"

local function update_rule(rule, rule_memory)
  rule_api = rule["api"]
  if rule_memory[rule_api] == nil then
    rule_memory[rule_api] = {}
  end

  rule_key = rule["key"]
  if rule_memory[rule_api][rule_key] == nil then
    rule_memory[rule_api][rule_key] = {}
  end

  if(rule["value"] ~= nil) then  -- either rule["value"] or rule["value_matches"] will be non-nil (ensured by input validation)
    if rule_memory[rule_api][rule_key][_exact_values] == nil then
      rule_memory[rule_api][rule_key][_exact_values] = {}
    end
    rule_memory[rule_api][rule_key][_exact_values][rule["value"]] = rule["endpoint"]
  else
    if rule_memory[rule_api][rule_key][_regex_values] == nil then
      rule_memory[rule_api][rule_key][_regex_values] = {}
    end
    rule_memory[rule_api][rule_key][_regex_values][rule["value_matches"]] = rule["endpoint"]
  end
end

local function update_rule_in_memory(rule)
  local rule_memory = nil
  local rule_type = rule["type"]
  if(rule_type == "param") then ---currently rule[type] can be either header/param so rule_memory won't stay nil
      rule_memory = _router_params_key_values
  elseif(rule_type == "header") then
      rule_memory = _router_headers_key_values
  end
  update_rule(rule, rule_memory)
end

local function check_rerouting_exact_matches(key_rules, value)
  if (key_rules[value] ~= nil) then
    rule_endpoint = key_rules[value]
    ngx.log(ngx.INFO, "setting endpoint.. ".. rule_endpoint)
    ngx.var.upstream_endpoint = rule_endpoint
  end
end

local function check_rerouting_regex_matches(key_rules, value)
  for rule_regex, rule_endpoint in pairs(key_rules) do
    local m, err = ngx.re.match(value, rule_regex)
    if m then
      ngx.log(ngx.INFO, "setting endpoint based on regex.. ".. rule_endpoint)
      ngx.var.upstream_endpoint = rule_endpoint
    end
  end
end

local function check_reroute(value, rule_values)
  for inner_rule_key, key_rules in pairs(rule_values) do
    if(inner_rule_key == _exact_values) then -- try exact match
      check_rerouting_exact_matches(key_rules, value)
    else                                     -- try regex match
      check_rerouting_regex_matches(key_rules, value)
    end
  end
end

local function perform_param_based_rerouting(args, api)
  local rules_api = _router_params_key_values[api]
  for rule_key, rule_values in pairs(rules_api) do
    if args[rule_key] ~= nil then
      check_reroute(args[rule_key], rule_values)
    end
  end
end

local function perform_header_based_rerouting(headers, api)
  local rules_api = _router_headers_key_values[api]
  for rule_key, rule_values in pairs(rules_api) do
    if headers[rule_key] ~= nil then
      check_reroute(headers[rule_key], rule_values)
    end
  end
end

-- expose module functionality

local _M = {}

function _M.init(rule_file)
  ngx.log(ngx.INFO, "router init begin")
  local file, err = io.open(rule_file, "r")
  if file ~= nil then
    ngx.log(ngx.INFO, "reading routing rules")
    local contents = file:read("*a")
    local rules = {}
    if contents ~= nil and contents ~= '' then
      rules = cjson.decode(contents)
    end

    for _, rule in pairs(rules) do
      update_rule_in_memory(rule)
    end
    file:close()
  end
  ngx.log(ngx.INFO, "router init complete")
end

function _M.exec()
  ngx.log(ngx.INFO, "router exec begin")
  local api = ngx.var.uri
  local args = ngx.req.get_uri_args()
  local headers = ngx.req.get_headers()

  --perform arg level rerouting for configured params
  if _router_params_key_values[api] ~= nil then
    perform_param_based_rerouting(args, api)
  end

  --perform header based rerouting for configured headers
  if _router_headers_key_values[api] ~= nil then
    perform_header_based_rerouting(headers, api)
  end

  ngx.log(ngx.INFO, "router exec complete")
end

return _M