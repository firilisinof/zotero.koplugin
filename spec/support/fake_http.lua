--[[--
A scriptable stand-in for LuaSocket's `socket.http`, used to run the Zotero
sync and download code paths offline.

Assign an instance to `ZoteroAPI.http` and register the responses a test needs:

    local fake = FakeHttp.new()
    fake:on("HEAD", "/items%?", { headers = { ["total-results"] = "2" } })
    fake:on("GET",  "/items%?", { body = Fixtures.raw("items_page1.json") })
    ZoteroAPI.http = fake

It mirrors the two call shapes `zoteroapi.lua` actually uses: a HEAD request read
for its headers, and a GET request drained into an ltn12 sink (a table sink for
paginated JSON, a file sink for attachment downloads).
]]

local ltn12 = require("ltn12")

local FakeHttp = {}
FakeHttp.__index = FakeHttp

function FakeHttp.new()
    local self = setmetatable({ routes = {}, calls = {} }, FakeHttp)
    -- Production code calls `API.http.request{...}`, so this has to be a plain
    -- field holding a function rather than a method.
    self.request = function(reqt)
        return self:_handle(reqt)
    end
    return self
end

--- Registers a response.
-- @param method HTTP method to match, e.g. "GET"
-- @param pattern Lua pattern matched against the request URL
-- @param response table with optional `code` (default 200), `headers`, `body`,
--                 or `error` to simulate a transport failure
function FakeHttp:on(method, pattern, response)
    table.insert(self.routes, {
        method = method,
        pattern = pattern,
        response = response or {},
    })
    return self
end

function FakeHttp:_match(method, url)
    for _, route in ipairs(self.routes) do
        if route.method == method and string.find(url, route.pattern) ~= nil then
            return route
        end
    end
    return nil
end

function FakeHttp:_handle(reqt)
    local method = reqt.method or "GET"

    table.insert(self.calls, {
        method = method,
        url = reqt.url,
        headers = reqt.headers,
    })

    local route = self:_match(method, reqt.url)
    if route == nil then
        error(("FakeHttp: no response registered for %s %s"):format(method, reqt.url), 2)
    end

    local response = route.response

    if response.error ~= nil then
        -- LuaSocket signals transport failures as (nil, message).
        return nil, response.error
    end

    if reqt.sink ~= nil and method ~= "HEAD" then
        ltn12.pump.all(ltn12.source.string(response.body or ""), reqt.sink)
    end

    return 1, response.code or 200, response.headers or {}
end

--- Number of requests received, optionally filtered by a URL pattern.
function FakeHttp:callCount(pattern)
    if pattern == nil then
        return #self.calls
    end

    local count = 0
    for _, call in ipairs(self.calls) do
        if string.find(call.url, pattern) ~= nil then
            count = count + 1
        end
    end
    return count
end

--- The URLs of every request received, in order.
function FakeHttp:urls()
    local urls = {}
    for i, call in ipairs(self.calls) do
        urls[i] = call.url
    end
    return urls
end

return FakeHttp
