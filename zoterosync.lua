local Sync = {}

--- Choose the version that cannot skip intervening changes. Example: API.earlierVersion("12", "13").
---@param api ZoteroAPI
---@param first string|number|nil
---@param second string|number|nil
---@return string|number|nil
function Sync.earlierVersion(api, first, second)
    local a, b = tonumber(first), tonumber(second)
    if not a then return second end
    if not b then return first end
    return a <= b and first or second
end

-- Every item field any module reads. Creators, relations and server links stay
-- out of items.json, which low-end readers parse whole on every start.
local CACHED_FIELDS = {
    meta = { creatorSummary = true, parsedDate = true },
    data = { itemType = true, title = true, parentItem = true, collections = true, tags = true, DOI = true,
        date = true, contentType = true, linkMode = true, filename = true, md5 = true, note = true, deleted = true },
}

---@param fields table|nil
---@param allowed table<string, boolean>
---@return boolean
local function onlyAllowed(fields, allowed)
    if type(fields) ~= "table" then return fields == nil end
    for name in pairs(fields) do
        if not allowed[name] then return false end
    end
    return true
end

---@param item ZoteroItem
---@return boolean
local function isCompact(item)
    for name in pairs(item) do
        if name ~= "key" and name ~= "version" and not CACHED_FIELDS[name] then return false end
    end
    return onlyAllowed(item.meta, CACHED_FIELDS.meta) and onlyAllowed(item.data, CACHED_FIELDS.data)
end

---@param fields table|nil
---@param allowed table<string, boolean>
---@return table|nil
local function pickFields(fields, allowed)
    if type(fields) ~= "table" then return nil end
    local kept = {}
    for name in pairs(allowed) do kept[name] = fields[name] end
    return next(kept) and kept or nil
end

-- Highlight sync fetches annotations per attachment, so the library cache never needs them.
---@param item ZoteroItem
---@return ZoteroItem|nil
local function compactItem(item)
    if item.data and item.data.itemType == "annotation" then return nil end
    if isCompact(item) then return item end
    return { key = item.key, version = item.version,
        meta = pickFields(item.meta, CACHED_FIELDS.meta), data = pickFields(item.data, CACHED_FIELDS.data) }
end

---@param entry ZoteroItem
---@return ZoteroItem
local function keepEntry(entry)
    return entry
end

---@class ZoteroDeltaSource
---@field endpoint string
---@field filter string Extra query parameters appended to the delta URL
---@field compact fun(entry: ZoteroItem): ZoteroItem|nil

---@type ZoteroDeltaSource
local ITEM_SOURCE = { endpoint = "items", filter = "&itemType=-annotation", compact = compactItem }
---@type ZoteroDeltaSource
local COLLECTION_SOURCE = { endpoint = "collections", filter = "", compact = keepEntry }

---@param existing table<string, ZoteroItem>
---@param compact fun(entry: ZoteroItem): ZoteroItem|nil
---@return table<string, ZoteroItem>
local function copyEntries(existing, compact)
    local entries = {}
    -- Caches written before trimming shrink on their next sync, without a full resync.
    for key, entry in pairs(existing) do entries[key] = compact(entry) end
    return entries
end

---@param entries table<string, ZoteroItem>
---@param page ZoteroItem[]
---@param compact fun(entry: ZoteroItem): ZoteroItem|nil
local function mergePage(entries, page, compact)
    for _, item in ipairs(page) do
        -- The server has used both true and 1 for trashed items.
        local deleted = item.data and (item.data.deleted == true or item.data.deleted == 1)
        entries[item.key] = not deleted and compact(item) or nil
    end
end

---@param api ZoteroAPI
---@param source ZoteroDeltaSource
---@param existing table<string, ZoteroItem>
---@return table|nil, string|nil, string|nil
local function fetchDelta(api, source, existing)
    local entries = copyEntries(existing, source.compact)
    local url = ("https://api.zotero.org/%s/%s?since=%s&includeTrashed=true%s")
        :format(api.getLibraryPrefix(), source.endpoint, api.getLibraryVersion(), source.filter)
    local version, err = api.fetchCollectionPaginated(url, api.getHeaders(api.getAPIKey()), function(page)
        mergePage(entries, page, source.compact)
    end)
    if err then return nil, err end
    return entries, nil, version
end

--- Sync read-only deltas and stamp successful completion. Example: API.syncAllItems().
---@param api ZoteroAPI
---@return string|nil
function Sync.syncAllItems(api)
    local err = api.ensureKeyAndID()
    if err then return err end
    local items, items_error, items_version = fetchDelta(api, ITEM_SOURCE, api.getItems())
    if items_error then return items_error end
    local collections, collections_error, collections_version = fetchDelta(api, COLLECTION_SOURCE, api.getCollections())
    if collections_error then return collections_error end
    api.setItems(items)
    api.setCollections(collections)
    -- Each fetch observes a potentially different version. The earlier one avoids
    -- skipping changes made between requests on the next sync.
    api.setLibraryVersion(api.earlierVersion(items_version, collections_version))
    api.setLastSync(os.time())
    api.saveModifiedItems()
end

--- Reset metadata while retaining documents and their sidecars. Example: API.resetSyncState().
---@param api ZoteroAPI
function Sync.resetSyncState(api)
    api.setItems({})
    api.setCollections({})
    api.setLibraryVersion(0)
    api.setLastSync(0)
    api.saveModifiedItems()
end

--- Decide whether an enabled automatic trigger is due. Example: API.shouldAutoSync("open", os.time()).
---@param api ZoteroAPI
---@param trigger string
---@param now number
---@return boolean
function Sync.shouldAutoSync(api, trigger, now)
    if api.operation or api.ensureKeyAndID() then return false end
    if trigger == "startup" then return api.getSyncOnStartup() == true end
    if trigger ~= "open" or api.getSyncOnOpen() ~= true then return false end
    local last = tonumber(api.getLastSync()) or 0
    return last == 0 or now - last > 24 * 60 * 60
end

--- Reserve one operation before scheduling it. Example: API.beginOperation("sync").
---@param api ZoteroAPI
---@param operation string
---@return boolean
function Sync.beginOperation(api, operation)
    if api.operation then return false end
    api.operation = operation
    return true
end

--- Release a completed operation. Example: API.endOperation().
---@param api ZoteroAPI
function Sync.endOperation(api)
    api.operation = nil
end

return Sync
