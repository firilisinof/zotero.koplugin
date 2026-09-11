local Base = require("spec.support.fake_progress_server")
local Helpers = require("zoterohighlightutil")
local Server = {}
Server.__index = Server
setmetatable(Server, { __index = Base })

function Server.new()
    local self = Base.new()
    self.annotations, self.library = {}, "users/4242"
    return setmetatable(self, Server)
end

function Server:insert(key, fields)
    self.version = self.version + 1
    self.annotations[key] = { key = key, version = self.version, data = Helpers.copy(fields) }
    return self.annotations[key]
end

function Server:dispatch(request)
    if self.error_code then return self.error_code, {}, { ["retry-after"] = "120" } end
    if request.url:match("/keys/current$") then
        return 200, { userID = 4242, access = { user = { library = true, write = self.writable },
            groups = { ["99"] = { library = true, write = self.group_writable } } } }
    end
    local parent, start = request.url:match("/items/([A-Z0-9]+)/children%?.*start=(%d+)$")
    if parent then
        local children = {}
        for _, item in pairs(self.annotations) do if item.data.parentItem == parent then children[#children + 1] = item end end
        table.sort(children, function(a, b) return a.key < b.key end)
        local batch, offset = {}, tonumber(start)
        for i = offset + 1, math.min(#children, offset + (self.page_size or 100)) do batch[#batch + 1] = children[i] end
        return 200, batch, { ["total-results"] = tostring(self.incomplete and (#children + 1) or #children),
            ["last-modified-version"] = tostring(self.version + (self.moving_pages and offset or 0)) }
    end
    local key = request.url:match("/items/([A-Z0-9]+)$")
    if request.method == "GET" and key then
        local item = self.items[key] or self.annotations[key]
        return item and 200 or 404, item, self.item_headers
    end
    if self.conflicts > 0 then self.conflicts = self.conflicts - 1; return 412 end
    if request.method == "POST" then
        local fields = request.payload[1]
        if self.annotations[fields.key] then return 200, { failed = { ["0"] = { code = 412 } } } end
        local created = self:insert(fields.key, fields)
        self.writes = self.writes + 1
        if self.lose_write_response then return 0 end
        return 200, { successful = { ["0"] = created } }
    end
    assert(request.method == "PATCH", "Unexpected highlight request " .. request.method .. " " .. request.url)
    local current = assert(self.annotations[key])
    if tonumber(request.headers["if-unmodified-since-version"]) ~= current.version then return 412 end
    local fields = Helpers.copy(current.data)
    for field, value in pairs(request.payload) do fields[field] = value end
    self:insert(key, fields); self.writes = self.writes + 1
    if self.lose_write_response then return 0 end
    return 204
end

return Server
