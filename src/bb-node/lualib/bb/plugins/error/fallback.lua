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

--[[
This component is part of an error phase/state. Whenever main requests failed with 5XX,
it executes this module and tries for configured fallback
--]]

local _M = {}

local _fallback_endpoints = {}

-- creates a new merged dictionary from both dictionaries
-- in case of collision, second dictionary's key's value will be taken
local function merge_dictionary(dict1, dict2)

  local dict = dict1
  if dict1 == nil then
    dict = dict2
    return dict
  end

  if(dict2 ~= nil) then
    for k,v in pairs(dict2) do
      dict[k] = v
    end
  end
  return dict
end

-- More deatils at http://lua-users.org/wiki/CsvUtils
-- Used to escape "'s by to_underscore_joined
local function escape (s)
  if string.find(s, '[,"]') then
    s = '"' .. string.gsub(s, '"', '""') .. '"'
  end
  return s
end

-- Convert from table to string joined using underscore
local function to_underscore_joined(table)
  local s = ""
  for _,p in ipairs(table) do
    s = s .. "_" .. escape(p)
  end
  return string.sub(s, 2) -- remove first comma
end

local function generate_key(api, errors)
  return api.."_"..to_underscore_joined(errors)
end

local function check_param(org_arg, api_endpoint_reg_params)
  -- return true if original request contains one of the configured params for fallback end point
  -- return false if original request doesn't contains none of the configured params for fallback end point
  -- org_arg : original arg list passed to request
  -- api_endpoint_reg_params : params registred for this endpoint
  -- TODO : provide a way for user to configure params to check
  local args = org_arg
  local reg_params = api_endpoint_reg_params
  if reg_params == nil then
    return false
  end

  -- todo : Enhancement feature, caputre which param to check
  for param_key, param_value in pairs(reg_params) do
    if args[param_key] ~= nil then -- registered param key already exists in original request
      local args_param_value = args[param_key]
      -- TOOD : move this to a new function if possible
      if type(args_param_value) == "table" then -- handles multi-valued params
        for _, value in pairs(args_param_value) do
          if value == param_value then
            return true
          end
        end
      elseif args_param_value == param_value then
        return true
      end
    end
  end
  return false
end

function _M.init(rule_file)
  ngx.log(ngx.INFO, "fallback init begin")

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

  for _, fallback_rule in pairs(data) do
    local api = fallback_rule["api"]
    if _fallback_endpoints[api] == nil then
      _fallback_endpoints[api]= {}
    end

    local key = generate_key(api, fallback_rule["errors"])
    _fallback_endpoints[api][key] = {}

    for _, error in pairs(fallback_rule["errors"]) do
      _fallback_endpoints[api][error] = key
    end

    local endpoints_list = fallback_rule["endpoints"]
    for index, endpoint_data in pairs(endpoints_list) do
      _fallback_endpoints[api][key][index] = endpoint_data
    end
  end
  ngx.log(ngx.INFO, "fallback init executed")
end

function _M.exec()
  ngx.log(ngx.ERR, "fallback exec begin")

  ngx.log(ngx.ERR, "ngx.status:"..ngx.status)
  local error = tostring(ngx.status)

  local api = ngx.var.uri
  if _fallback_endpoints[api] == nil or _fallback_endpoints[api][error] == nil then
    ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
    ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
  end

  local http = require "bb.thirdparty.resty.http"
  local httpc = http.new()
  httpc:set_timeout(2000)
  local headers = ngx.req.get_headers()
  local ok, res, err, key

  local key = _fallback_endpoints[api][error]
  for index, endpoint_data in pairs(_fallback_endpoints[api][key]) do
    -- check do we need to skip this fallback
    local args = ngx.req.get_uri_args(500)
    local ret = check_param(args, endpoint_data[tostring(index)]["params"])
    if ret == true then
      ngx.log(ngx.INFO, "Requests contains params which are configrued as additional params for this endpoint\n")
      ngx.log(ngx.INFO, "This endpoint will be skipped : " .. endpoint_data[tostring(index)]["name"] .. "\n")
    else
      -- this a valid endpoint, we will try for this
      local host, port = endpoint_data[tostring(index)]["name"]:match("([^,]+):([^,]+)")
      ok, err = httpc:connect(host, port)
      if not ok then
        ngx.log(ngx.ERR, "got some issue with connect for host"..host.." port .."..port.." error "..err)
      else
        ngx.log(ngx.INFO, "connected to fallback end point - host:" .. host .. " and port:" .. port)
        local merged_args = merge_dictionary(args, endpoint_data[tostring(index)]["params"])
        local params_table = {}
        params_table["query"] = merged_args
        params_table["path"] = ngx.var.uri
        params_table["method"] = ngx.req.get_method()
        params_table["headers"] = headers
        params_table["version"] = 1.1
        res, err = httpc:request(params_table)
        if not err then
          ngx.log(ngx.ERR, "fallback response from:".. host .. " and port:" ..port.. " and status:" .. tostring(res.status))
          if res.status == 200 then
            ngx.status = res.status
            ngx.say(httpc:proxy_response(res))
            ngx.exit(ngx.status)
          end
        else
          ngx.log(ngx.ERR, "got some error while serving request from fallback ["..host..":"..port.."] "..err)
        end
      end
    end
  end

  -- return the error from last endpoint or original error if we couldn't serve the request
  if res ~= nil then
    ngx.status = res.status
    ngx.say(httpc:proxy_response(res))
    ngx.exit(ngx.status)
  else
    ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
    ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
  end
end

return _M