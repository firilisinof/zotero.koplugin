local Position = {}

---@param view ZoteroBrowserView|nil
---@return ZoteroBrowserView
local function copyView(view)
    if type(view) ~= "table" then return { kind = "collection", page = 1 } end
    local page = tonumber(view.page) or 1
    if page < 1 or page ~= page or page == math.huge then page = 1 end
    local result = { kind = view.kind, page = math.floor(page) }
    if view.kind == "search" or view.kind == "device" then
        result.query = type(view.query) == "string" and view.query or ""
    else
        result.kind = "collection"
        result.key = type(view.key) == "string" and view.key or nil
    end
    return result
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

--- Persist navigation separately from metadata and documents. Example: API.saveBrowserPosition("users/42", position).
---@param api ZoteroAPI
---@param library string
---@param position ZoteroBrowserPosition
function Position.saveBrowserPosition(api, library, position)
    local positions = api.settings:readSetting("browser_positions")
    if type(positions) ~= "table" then positions = {} end
    positions[library] = copyPosition(position)
    api.settings:saveSetting("browser_positions", positions)
    api.settings:flush()
end

return Position
