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

local cjson = cjson
local bb = require "bb.core.gatekeeper"

-- module level rules table : it holds the rules after reading from access.rule file
local _rules = {}

local function load_rules(rule_file)
  local filename = rule_file
  local file, err = io.open(filename, "r")

  local data = {}
  if file ~= nil then
    local contents = file:read("*a")
    if contents ~= nil and contents ~= '' then
      data = cjson.decode(contents)
    end
    file:close()
  end

  local rules = {}
  for _ , rule in pairs(data) do

    if not rules[rule.api] then
      rules[rule.api] = {}
      rules[rule.api].param = {}
      rules[rule.api].header = {}
    end

    local ref = nil
    if rule.type == "param" then
      ref = rules[rule.api].param
    elseif rule.type == "header" then
      ref = rules[rule.api].header
    end

    if ref[rule.key] == nil then
      ref[rule.key] = {}
    end

    ref[rule.key][rule.value] = rule.value

  end -- end of for loop

  return rules

end

local _M = {}

function _M.init(rule_file)
  _rules = load_rules(rule_file)
  --[[
  -- testing code
  -- print all param rules
  for _, api_rule in pairs(_rules) do
    for k, v in pairs(api_rule.param) do
      ngx.log(ngx.ERR, "param key:" .. k)
      for i, j in pairs(v) do
        ngx.log(ngx.ERR, "param values:" .. i .. ":" .. j)
      end
    end
  end

  -- print all header rules
  for _, api_rule in pairs(_rules) do
    for k, v in pairs(api_rule.header) do
      ngx.log(ngx.ERR, "header key:" .. k)
      for i, j in pairs(v) do
        ngx.log(ngx.ERR, "header values:" .. i .. ":" .. j)
      end
    end
  end
  --]]
end

function _M.exec()
  local headers = ngx.req.get_headers()
  local args = ngx.req.get_uri_args()

  local rule = _rules[ngx.var.uri]
  if rule then
    -- check all the param rules
    for rule_key, rule_values in pairs(rule.param) do
      local args_value = args[rule_key]
      local rule_value = rule_values[args[rule_key]]
      if args_value ~= nil and rule_value ~= nil and args_value == rule_value then
        ngx.status = ngx.HTTP_UNAUTHORIZED
        ngx.say("Access denied")
        ngx.exit(ngx.status)
      end
    end -- end of param for loop

    -- check all the header rules
    for rule_key, rule_values in pairs(rule.header) do
      if rule_key ~= "remote_addr" then
        local header_value = headers[rule_key]
        local rule_value = rule_values[headers[rule_key]]
        if header_value ~= nil and rule_value ~= nil and header_value == rule_value then
          ngx.status = ngx.HTTP_UNAUTHORIZED
          ngx.say("Access denied")
          ngx.exit(ngx.status)
        end
      end
    end -- end of header for loop

    -- check all the IP rules
    local client_ip = ngx.var.remote_addr
    local blocked_ip = nil
    if client_ip ~= nil and rule.header ~= nil and rule.header["remote_addr"] ~= nil then
      local blocked_ip = rule.header["remote_addr"][client_ip]
      if blocked_ip ~= nil then
        ngx.status = ngx.HTTP_UNAUTHORIZED
        ngx.say("Access denied")
        ngx.exit(ngx.status)
      end
    end

  end -- end of outer if
end

return _M
