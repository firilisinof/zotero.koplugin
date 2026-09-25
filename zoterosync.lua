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
---@field endpoint string Web API endpoint, also the name of its cache file
---@field filter string Extra query parameters appended to the delta URL
---@field compact fun(entry: ZoteroItem): ZoteroItem|nil
---@field cached fun(api: ZoteroAPI): table<string, ZoteroItem>

-- Items come first. Their version is the earlier one when both fetches race a change.
---@type ZoteroDeltaSource[]
local SOURCES = {
    { endpoint = "items", filter = "&itemType=-annotation", compact = compactItem,
        cached = function(api) return api.getItems() end },
    { endpoint = "collections", filter = "", compact = keepEntry,
        cached = function(api) return api.getCollections() end },
}

---@param existing table<string, ZoteroItem>
---@param compact fun(entry: ZoteroItem): ZoteroItem|nil
---@return table<string, ZoteroItem>, boolean pruned
local function copyEntries(existing, compact)
    local entries, pruned = {}, false
    -- Caches written before trimming shrink on their next sync, without a full resync.
    for key, entry in pairs(existing) do
        entries[key] = compact(entry)
        pruned = pruned or entries[key] ~= entry
    end
    return entries, pruned
end

-- Zotero bumps an object's version on every modification, so equal versions mean equal content.
---@param current ZoteroItem|nil
---@param incoming ZoteroItem|nil
---@return boolean
local function sameVersion(current, incoming)
    if current == nil or incoming == nil then return current == incoming end
    return current.version == incoming.version
end

---@param entries table<string, ZoteroItem>
---@param page ZoteroItem[]
---@param compact fun(entry: ZoteroItem): ZoteroItem|nil
---@return boolean changed
local function mergePage(entries, page, compact)
    local changed = false
    for _, item in ipairs(page) do
        -- The server has used both true and 1 for trashed items.
        local deleted = item.data and (item.data.deleted == true or item.data.deleted == 1)
        local incoming = not deleted and compact(item) or nil
        changed = changed or not sameVersion(entries[item.key], incoming)
        entries[item.key] = incoming
    end
    return changed
end

---@class ZoteroDelta
---@field entries table<string, ZoteroItem>
---@field changed boolean Whether entries differ from the cache they were copied from
---@field version string|nil

---@param api ZoteroAPI
---@param source ZoteroDeltaSource
---@param since string|number
---@param rebuild boolean Start from an empty cache, so entries the server no longer lists disappear
---@return ZoteroDelta|nil, string|nil
local function fetchDelta(api, source, since, rebuild)
    local entries, changed = copyEntries(rebuild and {} or source.cached(api), source.compact)
    changed = changed or rebuild
    local url = ("https://api.zotero.org/%s/%s?since=%s&includeTrashed=true%s")
        :format(api.getLibraryPrefix(), source.endpoint, since, source.filter)
    local version, err = api.fetchCollectionPaginated(url, api.getHeaders(api.getAPIKey()), function(page)
        changed = mergePage(entries, page, source.compact) or changed
    end)
    if err then return nil, err end
    return { entries = entries, changed = changed, version = version }
end

---@class ZoteroStagedCache
---@field changed boolean Whether a staged file replaces the live cache
---@field version string|nil Library version the fetch observed

---@class ZoteroSyncResult
---@field items ZoteroStagedCache|nil
---@field collections ZoteroStagedCache|nil
---@field error string|nil

---@param api ZoteroAPI
---@param source ZoteroDeltaSource
---@param since string|number
---@param rebuild boolean
---@param path string
---@return ZoteroStagedCache|nil, string|nil
local function stageDelta(api, source, since, rebuild, path)
    local delta, err = fetchDelta(api, source, since, rebuild)
    if err then return nil, err end
    -- An unchanged cache would cost a full JSON encode and a rebuilt index for nothing.
    err = delta.changed and api.util.write(path, api.util.encode(delta.entries)) or nil
    if err then return nil, err end
    return { changed = delta.changed, version = delta.version }
end

--- Name the staged caches a sync writes beside the live ones. Example: API.getSyncStage().items.
---@param api ZoteroAPI
---@return table<string, string>
function Sync.getSyncStage(api)
    local stage = {}
    for _, source in ipairs(SOURCES) do stage[source.endpoint] = api.getCachePath(source.endpoint) .. ".sync" end
    return stage
end

--- Remove staged caches, including a killed child's unfinished writes. Example: API.discardSyncStage(stage).
---@param api ZoteroAPI
---@param stage table<string, string>
function Sync.discardSyncStage(api, stage)
    for _, path in pairs(stage) do api.util.discard(path) end
end

--- Fetch deltas into staged files, leaving live caches and settings untouched. Runs in the
--- sync child, so only the small result crosses the pipe. Example: API.stageLibrary(false, stage).
---@param api ZoteroAPI
---@param rebuild boolean Fetch from version 0 instead of patching the current cache
---@param stage table<string, string>
---@return ZoteroSyncResult
function Sync.stageLibrary(api, rebuild, stage)
    local err = api.ensureKeyAndID()
    if err then return { error = err } end
    local since, result = rebuild and 0 or api.getLibraryVersion(), {}
    for _, source in ipairs(SOURCES) do
        local staged, stage_error = stageDelta(api, source, since, rebuild, stage[source.endpoint])
        if stage_error then return { error = stage_error } end
        result[source.endpoint] = staged
    end
    return result
end

---@param result ZoteroSyncResult
---@return string|nil
local function resultError(result)
    for _, source in ipairs(SOURCES) do
        local staged = result[source.endpoint]
        if type(staged) ~= "table" or type(staged.changed) ~= "boolean" then
            return ("Invalid sync result for %s: %s, expected { changed = boolean, version = string|nil }")
                :format(source.endpoint, tostring(staged))
        end
    end
end

--- Adopt a finished child's staged caches and stamp success. Only the parent commits.
--- Example: API.commitLibrary(result, stage).
---@param api ZoteroAPI
---@param result ZoteroSyncResult
---@param stage table<string, string>
---@return string|nil error
function Sync.commitLibrary(api, result, stage)
    local err = resultError(result)
    if err then return err end
    for _, source in ipairs(SOURCES) do
        local name = source.endpoint
        -- A later failure leaves the version unchanged, so the next delta reapplies over this cache.
        err = result[name].changed and api.adoptCache(name, stage[name]) or nil
        if err then return err end
    end
    -- Each fetch observes a potentially different version. The earlier one avoids
    -- skipping changes made between requests on the next sync.
    api.setLibraryVersion(api.earlierVersion(result.items.version, result.collections.version))
    api.setLastSync(os.time())
    api.saveModifiedItems()
end

--- Sync in-process through the background job's stage and commit steps. Example: API.syncAllItems().
---@param api ZoteroAPI
---@return string|nil
function Sync.syncAllItems(api)
    local stage = api.getSyncStage()
    local result = api.stageLibrary(false, stage)
    local err = result.error or api.commitLibrary(result, stage)
    api.discardSyncStage(stage)
    return err
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
