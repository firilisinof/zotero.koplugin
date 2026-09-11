local Store = {}
Store.__index = Store

--- Open the account-scoped outbox without loading executable sidecars. Example: Store.new(api).
---@param api ZoteroAPI
---@param filename string|nil
---@return table
function Store.new(api, filename)
    return setmetatable({ api = api, path = api.zotero_dir .. "/" .. (filename or "reading-progress.json") }, Store)
end

--- Reload before each transaction: reader and file manager have distinct plugin instances.
---@return table
function Store:load()
    local contents = self.api.util.read(self.path)
    if not contents then return { schema = 1, records = {} } end
    local ok, state = pcall(self.api.util.decode, contents)
    assert(ok and type(state) == "table" and state.schema == 1 and type(state.records) == "table",
        "Invalid progress store " .. self.path .. "; expected schema 1 and records")
    return state
end

--- Derive identity independently of filenames or publication parents. Example: Store.key(identity).
---@param identity table
---@return string
function Store.key(identity)
    return identity.owner .. "/" .. identity.library .. "/" .. identity.key
end

--- Read one independent document record. Example: store:get(identity).
---@param identity table
---@return table|nil
function Store:get(identity)
    return self:load().records[Store.key(identity)]
end

--- Atomically replace a record and preserve every other account. Example: store:put(record).
---@param record table
function Store:put(record)
    local state = self:load()
    state.records[Store.key(record.identity)] = record
    local err = self.api.util.write(self.path, self.api.util.encode(state), true)
    assert(not err, err)
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
