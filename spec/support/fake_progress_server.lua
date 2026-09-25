local JSON = require("json")
local ltn12 = require("ltn12")
local Server = {}
Server.__index = Server

function Server.new()
    local self = setmetatable({ owner = "4242", settings = {}, items = {}, version = 10,
        calls = {}, conflicts = 0, writes = 0, writable = true }, Server)
    self.request = function(request)
        local ok, result, code, headers = pcall(self.respond, self, request)
        if not ok then self.last_error = result; error(result) end
        return result, code, headers
    end
    return self
end

function Server:setting(value)
    self.version = self.version + 1
    self.settings.lastPageIndex_u_ATTACH01 = { value = value, version = self.version }
end

function Server:body(request)
    if not request.source then return end
    local chunks = {}
    ltn12.pump.all(request.source, (ltn12.sink.table(chunks)))
    return JSON.decode(table.concat(chunks))
end

function Server:dispatch(request)
    if self.error_code then return self.error_code, {}, { ["retry-after"] = "120" } end
    if request.url:match("/keys/current$") then
        return 200, { userID = tonumber(self.owner), access = { user = { library = true, write = self.writable } } }
    end
    local key = request.url:match("/items/([A-Z0-9]+)$")
    if key then return self.items[key] and 200 or 404, self.items[key], self.item_headers end
    local name = assert(request.url:match("/settings/(.+)$"), request.url)
    local setting = self.settings[name]
    if request.method == "GET" then return setting and 200 or 404, setting end
    assert(request.method == "PUT")
    if self.conflicts > 0 then self.conflicts = self.conflicts - 1; return 412 end
    if not self.writable then return 403 end
    if tonumber(request.headers["if-unmodified-since-version"]) ~= (setting and setting.version or 0) then return 412 end
    self.version, self.writes = self.version + 1, self.writes + 1
    self.settings[name] = { value = request.payload.value, version = self.version }
    if self.lose_write_response then return 0 end
    return 204
end

function Server:respond(request)
    if self.delay then require("ffi/util").usleep(self.delay) end
    request.payload = self:body(request)
    table.insert(self.calls, request)
    local code, body, headers = self:dispatch(request)
    if code == 0 then return nil, "timeout" end
    if request.sink then ltn12.pump.all(ltn12.source.string(body and JSON.encode(body) or ""), request.sink) end
    return 1, code, headers or {}
end

return Server
