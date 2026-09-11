local Util = require("zoteroutil")

---@type ZoteroAPI
local API = {
    -- Specs replace only the HTTP transport. Files and archives remain real.
    http = require("socket.http"),
    util = Util,
    archive = require("zoteroarchive"),
}

---@param module table<string, function>
local function bind(module)
    for name, method in pairs(module) do
        API[name] = function(...) return method(API, ...) end
    end
end

bind(require("zoterosettings"))
bind(require("zoteroposition"))
bind(require("zoterotransport"))
bind(require("zoteroindex"))
bind(require("zoterodownload"))
bind(require("zoterosync"))

--- Open the local library and settings. Example: API.init("./zotero").
---@param zotero_dir string
function API.init(zotero_dir)
    API.zotero_dir = zotero_dir
    -- Drop anything parsed from a previously configured directory.
    API.items, API.collections, API.index = nil, nil, nil
    API.settings = Util.openSettings(zotero_dir .. "/meta.lua")
    API.reconcileLibrary()
end

--- Locate a live metadata cache file. Example: API.getCachePath("items").
---@param name string
---@return string
function API.getCachePath(name)
    return API.zotero_dir .. "/" .. name .. ".json"
end

---@param name string
---@return table<string, ZoteroItem>
local function readCache(name)
    local contents = Util.read(API.getCachePath(name))
    return contents and Util.decode(contents) or {}
end

---@param name string
---@param entries table<string, ZoteroItem>
local function writeCache(name, entries)
    local err = Util.write(API.getCachePath(name), Util.encode(entries))
    assert(not err, err)
    API[name], API.index = entries, nil
end

--- Replace a live cache with a file staged by the sync child. Example: API.adoptCache("items", stage).
---@param name string
---@param stage string
---@return string|nil error
function API.adoptCache(name, stage)
    local path = API.getCachePath(name)
    local ok, err = os.rename(stage, path)
    if not ok then return ("Could not replace %s with staged %s: %s"):format(path, stage, tostring(err)) end
    -- The next reader parses the adopted file. The parent never holds the child's tables.
    API[name], API.index = nil, nil
end

--- Read cached items lazily. Example: API.getItems()[key].
---@return table<string, ZoteroItem>
function API.getItems()
    if not API.items then API.items = readCache("items") end
    return API.items
end

--- Persist replacement items and invalidate lookups. Example: API.setItems(items).
---@param items table<string, ZoteroItem>
function API.setItems(items)
    writeCache("items", items)
end

--- Read cached collections lazily. Example: API.getCollections()[key].
---@return table<string, ZoteroItem>
function API.getCollections()
    if not API.collections then API.collections = readCache("collections") end
    return API.collections
end

--- Persist replacement collections. Example: API.setCollections(collections).
---@param collections table<string, ZoteroItem>
function API.setCollections(collections)
    writeCache("collections", collections)
end

--- Truncate a positive decimal value. Example: API.cutDecimalPlaces(1.234, 2).
---@param x number
---@param num_places integer
---@return number
function API.cutDecimalPlaces(x, num_places)
    local factor = 10^num_places
    return math.floor(x * factor) / factor
end

-- Output the timezone-agnostic timestamp, since KOReader uses timestamps with
-- local time. Example: API.addTimezone("2022-09-22 18:09:12").
---@param timestamp string
---@return string
function API.addTimezone(timestamp)
    local year, month, day, hour, minute, second = string.match(timestamp,
        "(%d%d%d%d)-(%d%d)-(%d%d) (%d%d):(%d%d):(%d%d)")
    local time = {
        ["year"] = year,
        ["month"] = month,
        ["day"] = day,
        ["hour"] = hour,
        ["min"] = minute,
        ["sec"] = second
    }

    return os.date("!%Y-%m-%dT%H:%M:%SZ", os.time(time))
end

--- Compare UTC and local timestamps. Example: API.compareTimestamps(utc, local_time).
---@param zoteroTimestamp string
---@param koreaderTimestamp string
---@return integer
function API.compareTimestamps(zoteroTimestamp, koreaderTimestamp)
    local a,b = zoteroTimestamp, API.addTimezone(koreaderTimestamp)

    if a == b then
       return 0
    elseif a < b then
        return -1
    else
        return 1
    end
end

return API
