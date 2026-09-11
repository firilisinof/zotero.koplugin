local util = require("util")
local Store = {}
Store.__index = Store

-- Copies like the JSON round trip this replaces: two fields holding one table become two
-- independent tables. util.tableDeepCopy keeps that sharing, which would let capturing a
-- local edit into record.entries also rewrite record.delivery.before, the import baseline.
-- Records are JSON documents, so they never contain cycles.
---@param value any
---@return any
local function copyRecord(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in next, value do result[key] = copyRecord(item) end
    -- Decoded tables carry their array or object kind in a shared metatable.
    return setmetatable(result, getmetatable(value))
end

--- Open the account-scoped outbox without loading executable sidecars. Example: Store.new(api).
---@param api ZoteroAPI
---@param filename string|nil
---@return table
function Store.new(api, filename)
    return setmetatable({ api = api, path = api.zotero_dir .. "/" .. (filename or "reading-progress.json") }, Store)
end

--- Decode the file once per store, then keep memory and disk equal by writing through.
--- Reader and file manager have distinct plugin instances, but both share this store
--- through api.progress or api.highlights, and only the parent process writes the file.
--- Workers get copies and never write, so nothing can change it behind this cache.
---@return table
function Store:state()
    if self.cached then return self.cached end
    local contents = self.api.util.read(self.path)
    if not contents then self.cached = { schema = 1, records = {} } return self.cached end
    local ok, state = pcall(self.api.util.decode, contents)
    assert(ok and type(state) == "table" and state.schema == 1 and type(state.records) == "table",
        "Invalid progress store " .. self.path .. "; expected schema 1 and records")
    self.cached = state
    return state
end

--- Return an independent copy of every record for iteration. Example: store:load().records.
---@return table
function Store:load()
    return copyRecord(self:state())
end

--- Derive identity independently of filenames or publication parents. Example: Store.key(identity).
---@param identity table
---@return string
function Store.key(identity)
    return identity.owner .. "/" .. identity.library .. "/" .. identity.key
end

--- Read one independent document record. Example: store:get(identity).
--- Callers mutate records, and ack compares a worker snapshot's generation with the stored
--- one. A shared reference would move both together, so this is always a deep copy.
---@param identity table
---@return table|nil
function Store:get(identity)
    return copyRecord(self:state().records[Store.key(identity)])
end

---@return string|nil error
function Store:write()
    return self.api.util.write(self.path, self.api.util.encode(self:state()), true)
end

--- Atomically replace a record and preserve every other account. Example: store:put(record).
--- Stores a copy, skips unchanged records and rolls back memory when the write fails.
---@param record table
function Store:put(record)
    local records, key = self:state().records, Store.key(record.identity)
    local previous = records[key]
    if previous ~= nil and util.tableEquals(previous, record) then return end
    records[key] = record
    local ok, err = pcall(self.write, self)
    if not ok or err then
        records[key] = previous
        error(("Could not save record %s to %s: %s"):format(key, self.path, tostring(err)), 0)
    end
    -- Keep a copy, not the caller's table: callers keep mutating the record they handed over.
    records[key] = copyRecord(record)
end

--- Coalesce changes while retaining the generation needed to reject old acknowledgments.
---@param identity table
---@param native string|integer
---@param value string|integer|nil
---@param reason string|nil
---@return table
function Store:capture(identity, native, value, reason)
    local record = self:get(identity) or { identity = identity, generation = 0 }
    if record.identity.md5 ~= identity.md5 or record.identity.path ~= identity.path then
        record = { identity = identity, generation = record.generation + 1 }
    end
    if record.native ~= native or record.value ~= value or reason ~= record.reason then
        record.native, record.value, record.reason = native, value, reason
        record.generation, record.pending = record.generation + 1, true
        record.status = reason and "unavailable" or "pending"
        self:put(record)
    end
    return record
end

--- Acknowledge only the snapshot actually sent. Example: store:ack(snapshot, response).
---@param snapshot table
---@param response table
---@return boolean
function Store:ack(snapshot, response)
    local record = self:get(snapshot.identity)
    if not record or record.generation ~= snapshot.generation or record.identity.md5 ~= snapshot.identity.md5 then return false end
    record.version, record.ack_value = response.version, response.value
    record.pending, record.reason, record.sync_error, record.status = false, nil, nil, "shared"
    self:put(record)
    return true
end

return Store
