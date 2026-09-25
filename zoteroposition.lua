local Position = {}

---@param view ZoteroBrowserView|nil
---@return ZoteroBrowserView
local function copyView(view)
    if type(view) ~= "table" then return { kind = "home", page = 1 } end
    local page = tonumber(view.page) or 1
    if page < 1 or page ~= page or page == math.huge then page = 1 end
    local result = { kind = view.kind, page = math.floor(page) }
    if view.kind == "search" or view.kind == "device" then
        result.query = type(view.query) == "string" and view.query or ""
    elseif view.kind == "collection" then
        result.key = type(view.key) == "string" and view.key or nil
    elseif view.kind ~= "home" and view.kind ~= "all" then
        result.kind = "home"
    end
    return result
end

--- Remember only successful plugin opens, separately for each library. Example: API.saveContinueReading(library, key, path).
---@param api ZoteroAPI
---@param library string
---@param key string
---@param path string
function Position.saveContinueReading(api, library, key, path)
    local recent = api.settings:readSetting("continue_reading")
    if type(recent) ~= "table" then recent = {} end
    recent[library] = { key = key, path = path }
    api.settings:saveSetting("continue_reading", recent)
    api.settings:flush()
end

--- Resolve a recent document against the active cache and actual file presence. Example: API.getContinueReading(library).
---@param api ZoteroAPI
---@param library string
---@return ZoteroRecentDocument|nil
function Position.getContinueReading(api, library)
    if library ~= (api.getLocalLibraryPrefix() or "local") then return end
    local recent = api.settings:readSetting("continue_reading")
    local entry = type(recent) == "table" and recent[library]
    if type(entry) ~= "table" or type(entry.key) ~= "string" or type(entry.path) ~= "string" then return end
    if api.getLocalAttachmentPath(entry.key) ~= entry.path then return end
    local item = api.getItems()[entry.key]
    local parent = api.getItems()[item.data.parentItem]
    local title = parent and parent.data and parent.data.title or item.data.title
    if type(title) ~= "string" or not title:find("%S") then title = item.data.filename end
    return { key = entry.key, path = entry.path, title = title }
end

---@param position ZoteroBrowserPosition|nil
---@return ZoteroBrowserPosition
local function copyPosition(position)
    if type(position) ~= "table" then position = {} end
    local result = { view = copyView(position.view), paths = {} }
    if type(position.paths) ~= "table" then return result end
    for _, view in ipairs(position.paths) do table.insert(result.paths, copyView(view)) end
    return result
end

--- Read an independent navigation snapshot for a library. Example: API.getBrowserPosition("users/42").
---@param api ZoteroAPI
---@param library string
---@return ZoteroBrowserPosition
function Position.getBrowserPosition(api, library)
    local positions = api.settings:readSetting("browser_positions")
    return copyPosition(type(positions) == "table" and positions[library] or nil)
end

--- Record navigation separately from metadata and documents. Example: API.saveBrowserPosition("users/42", position).
--- Every plugin instance shares api.settings, so this stays in memory. Rewriting meta.lua on each
--- page turn is slow on e-ink devices, so callers flush when the browser closes, opens a document or the device suspends.
---@param api ZoteroAPI
---@param library string
---@param position ZoteroBrowserPosition
function Position.saveBrowserPosition(api, library, position)
    local positions = api.settings:readSetting("browser_positions")
    if type(positions) ~= "table" then positions = {} end
    positions[library] = copyPosition(position)
    api.settings:saveSetting("browser_positions", positions)
end

return Position
