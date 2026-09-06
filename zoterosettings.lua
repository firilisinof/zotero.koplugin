local Settings = {}

---@param api ZoteroAPI
---@param key string
---@param default string|number|boolean|nil
---@return string|number|boolean|nil
local function read(api, key, default)
    return api.settings:readSetting(key, default)
end

--- Return the selected library type. Example: API.getLibraryType().
---@param api ZoteroAPI
---@return string
function Settings.getLibraryType(api)
    return read(api, "library_type", "user")
end

--- Return the active library ID. Example: API.getLibraryID().
---@param api ZoteroAPI
---@return string|nil
function Settings.getLibraryID(api)
    return read(api, api.getLibraryType() == "group" and "group_id" or "user_id")
end

--- Centralize the Web API library path. Example: API.getLibraryPrefix().
---@param api ZoteroAPI
---@return string|nil
function Settings.getLibraryPrefix(api)
    local identifier = api.getLibraryID()
    if not identifier or tostring(identifier) == "" then return nil end
    return (api.getLibraryType() == "group" and "groups/" or "users/") .. tostring(identifier)
end

--- Retain cache ownership when credentials are removed. Example: API.getLocalLibraryPrefix().
---@param api ZoteroAPI
---@return string|nil
function Settings.getLocalLibraryPrefix(api)
    return api.getLibraryPrefix() or read(api, "cache_library")
end

--- Reconcile manually edited settings and isolate storage. Example: API.reconcileLibrary().
---@param api ZoteroAPI
function Settings.reconcileLibrary(api)
    local prefix = api.getLocalLibraryPrefix()
    local previous = read(api, "cache_library")
    local legacy = read(api, "legacy_storage_library")
    if prefix and not previous and not legacy and api.getLibraryType() == "user" then
        legacy = prefix
        api.settings:saveSetting("legacy_storage_library", legacy)
    end
    if previous and previous ~= prefix then api.resetSyncState() end
    if prefix then api.settings:saveSetting("cache_library", prefix) end
    api.storage_dir = api.zotero_dir .. "/storage"
    if prefix and prefix ~= legacy then api.storage_dir = api.storage_dir .. "/" .. prefix end
    local ok, err = api.util.mkdir(api.storage_dir)
    assert(ok, "Expected storage directory " .. api.storage_dir .. ": " .. tostring(err))
    api.settings:flush()
end

---@param library_type string
---@param identifier string
---@return string|nil
local function accountError(library_type, identifier)
    if library_type ~= "user" and library_type ~= "group" then
        return "Invalid library type '" .. tostring(library_type) .. "', expected user or group"
    end
    if not tostring(identifier):match("^%d+$") or tonumber(identifier) <= 0 then
        return "Invalid library ID '" .. tostring(identifier) .. "', expected a positive integer"
    end
end

--- Apply account fields together. Example: API.setAccount("group", "123", key).
---@param api ZoteroAPI
---@param library_type string
---@param identifier string
---@param api_key string
---@return string|nil error
function Settings.setAccount(api, library_type, identifier, api_key)
    if api.operation then return "Wait for the current Zotero operation to finish." end
    local err = accountError(library_type, identifier)
    if err then return err end
    api.settings:saveSetting("library_type", library_type)
    api.settings:saveSetting(library_type == "group" and "group_id" or "user_id", tostring(identifier))
    api.settings:saveSetting("api_key", api_key)
    api.reconcileLibrary()
end

--- Check credentials before network I/O. Example: API.ensureKeyAndID().
---@param api ZoteroAPI
---@return string|nil, string|nil, string|nil
function Settings.ensureKeyAndID(api)
    local identifier = tostring(api.getLibraryID() or "")
    local label = api.getLibraryType() == "group" and "Group" or "User"
    if identifier == "" then return "Error: must set " .. label .. " ID" end
    local err = accountError(api.getLibraryType(), identifier)
    if err then return err end
    local api_key = api.getAPIKey() or ""
    if api_key == "" then return "Error: must set API Key" end
    return nil, api_key, identifier
end

---@param api ZoteroAPI
---@param library_type string
---@param identifier string
---@return string|nil
local function setIdentifier(api, library_type, identifier)
    local err = accountError(library_type, identifier)
    if err then return err end
    if api.getLibraryType() == library_type then
        return api.setAccount(library_type, identifier, api.getAPIKey())
    end
    api.settings:saveSetting(library_type == "group" and "group_id" or "user_id", tostring(identifier))
    api.settings:flush()
end

--- Update the personal ID, preserving the original setter. Example: API.setUserID("123").
---@param api ZoteroAPI
---@param identifier string
function Settings.setUserID(api, identifier)
    return setIdentifier(api, "user", identifier)
end

--- Update the group ID and reset its active cache when needed. Example: API.setGroupID("123").
---@param api ZoteroAPI
---@param identifier string
---@return string|nil
function Settings.setGroupID(api, identifier)
    return setIdentifier(api, "group", identifier)
end

--- Use WebDAV only for personal libraries. Example: API.getWebDAVEnabled().
---@param api ZoteroAPI
---@return boolean
function Settings.getWebDAVEnabled(api)
    return api.getLibraryType() == "user" and api.settings:isTrue("webdav_enabled")
end

--- Toggle the saved personal WebDAV preference. Example: API.toggleWebDAVEnabled().
---@param api ZoteroAPI
function Settings.toggleWebDAVEnabled(api)
    api.settings:toggle("webdav_enabled")
    api.settings:flush()
end

--- Invalidate filtered lookups immediately. Example: API.setFilterTag("to-read").
---@param api ZoteroAPI
---@param tag string
function Settings.setFilterTag(api, tag)
    api.settings:saveSetting("filter_tag", tag)
    api.index = nil
    api.settings:flush()
end

--- Expose KOReader settings for existing callers. Example: API.getSettings().
---@param api ZoteroAPI
---@return LuaSettings
function Settings.getSettings(api)
    return api.settings
end

--- Flush local settings without writing to Zotero. Example: API.saveModifiedItems().
---@param api ZoteroAPI
function Settings.saveModifiedItems(api)
    api.settings:flush()
end

-- These accessors share one implementation so adding a setting cannot accidentally
-- change its storage key between reading and writing.
local fields = {
    APIKey = { "api_key" }, UserID = { "user_id" }, GroupID = { "group_id" },
    WebDAVUser = { "webdav_user" }, WebDAVPassword = { "webdav_password" },
    WebDAVUrl = { "webdav_url" }, LibraryVersion = { "library_version_nr", "0" },
    FilterTag = { "filter_tag", "" }, LastSync = { "last_sync", 0 },
    SyncOnStartup = { "sync_on_startup", false }, SyncOnOpen = { "sync_on_open", false },
}

---@param key string
---@param default string|number|boolean|nil
---@return function, function
local function accessors(key, default)
    return function(api) return read(api, key, default) end,
        function(api, value) api.settings:saveSetting(key, value) end
end

for name, field in pairs(fields) do
    local getter, setter = accessors(field[1], field[2])
    Settings["get" .. name] = Settings["get" .. name] or getter
    Settings["set" .. name] = Settings["set" .. name] or setter
end

return Settings
