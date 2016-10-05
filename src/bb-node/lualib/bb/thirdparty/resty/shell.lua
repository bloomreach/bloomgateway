-- Copyright (C) 2014 Anton Jouline (juce)
--[[
The MIT License (MIT)

Copyright (c) 2014 juce

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
-- ]]
-- https://github.com/juce/lua-resty-shell

local format = string.format
local match = string.match
local tcp = ngx.socket.tcp
local tonumber = tonumber


local shell = {
    _VERSION = '0.01'
}

local sockproc_socket = "unix:/tmp/shell.sock"


function shell.execute(cmd, args)
    local timeout = args and args.timeout
    local input_data = args and args.data or ""
    local sock = tcp()
    local ok, err = sock:connect(sockproc_socket)
    if ok then
        sock:settimeout(timeout or 15000)
        sock:send(cmd .. "\r\n")
        sock:send(format("%d\r\n", #input_data))
        sock:send(input_data)

        -- status code
        local data, err, partial = sock:receive('*l')
        if err then
            return -1, nil, err
        end
        local code = match(data,"status:([-%d]+)") or -1

        -- output stream
        data, err, partial = sock:receive('*l')
        if err then
            return -1, nil, err
        end
        local n = tonumber(data) or 0
        local out_bytes = n > 0 and sock:receive(n) or nil

        -- error stream
        data, err, partial = sock:receive('*l')
        if err then
            return -1, nil, err
        end
        n = tonumber(data) or 0
        local err_bytes = n > 0 and sock:receive(n) or nil
        sock:close()

        return tonumber(code), out_bytes, err_bytes
    end
    return -2, nil, err
end


return shell
