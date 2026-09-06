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

---@param existing table<string, ZoteroItem>
---@return table<string, ZoteroItem>
local function copyEntries(existing)
    local entries = {}
    for key, item in pairs(existing) do entries[key] = item end
    return entries
end

---@param entries table<string, ZoteroItem>
---@param page ZoteroItem[]
local function mergePage(entries, page)
    for _, item in ipairs(page) do
        -- The server has used both true and 1 for trashed items.
        local deleted = item.data and (item.data.deleted == true or item.data.deleted == 1)
        entries[item.key] = not deleted and item or nil
    end
end

---@param api ZoteroAPI
---@param endpoint string
---@param existing table<string, ZoteroItem>
---@return table|nil, string|nil, string|nil
local function fetchDelta(api, endpoint, existing)
    local entries = copyEntries(existing)
    local url = ("https://api.zotero.org/%s/%s?since=%s&includeTrashed=true")
        :format(api.getLibraryPrefix(), endpoint, api.getLibraryVersion())
    local version, err = api.fetchCollectionPaginated(url, api.getHeaders(api.getAPIKey()), function(page)
        mergePage(entries, page)
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
    local items, items_error, items_version = fetchDelta(api, "items", api.getItems())
    if items_error then return items_error end
    local collections, collections_error, collections_version = fetchDelta(api, "collections", api.getCollections())
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
