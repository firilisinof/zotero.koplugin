local util = require("util")
local Helpers = {}

--- Compare nested values independent of JSON object ordering. Example: Helpers.equal(a, b).
---@param first unknown
---@param second unknown
---@return boolean
function Helpers.equal(first, second)
    if type(first) ~= type(second) then return false end
    if type(first) ~= "table" then return first == second end
    for key, value in pairs(first) do if not Helpers.equal(value, second[key]) then return false end end
    for key in pairs(second) do if first[key] == nil then return false end end
    return true
end

--- Generate collision-resistant keys before any network request. Example: Helpers.key().
---@return string
function Helpers.key()
    local source = assert(io.open("/dev/urandom", "rb"), "Expected OS random source /dev/urandom")
    local bytes = source:read(8); source:close()
    assert(bytes and #bytes == 8, "Expected eight random bytes")
    local alphabet, key = "23456789ABCDEFGHIJKLMNPQRSTUVWXYZ", {}
    for i = 1, 8 do key[i] = alphabet:sub(bytes:byte(i) % 32 + 1, bytes:byte(i) % 32 + 1) end
    return table.concat(key)
end

-- KOReader keys multi-page PDF parts by page number. rapidjson drops such sparse
-- numeric keys, so journals key them by string and preparePDF restores numbers.
---@param ext table<integer|string, table>
---@return table<string, table>
local function pagesByString(ext)
    local pages = {}
    for page, part in pairs(ext) do pages[tostring(page)] = util.tableDeepCopy(part) end
    return pages
end

--- Snapshot only editable annotation fields, excluding layout and modification clocks.
---@param item table
---@return table
function Helpers.native(item)
    local snapshot = {}
    for _, field in ipairs({ "pos0", "pos1", "pboxes", "drawer", "color", "text", "note", "note_format" }) do
        if item[field] ~= nil then snapshot[field] = util.tableDeepCopy(item[field]) end
    end
    if item.ext ~= nil then snapshot.ext = pagesByString(item.ext) end
    return snapshot
end

--- Identify native text markup; bookmarks and drawings remain unrelated.
---@param item table
---@return boolean
function Helpers.supported(item)
    return item.pos0 ~= nil and item.pos1 ~= nil and
        (item.drawer == "lighten" or item.drawer == "underscore" or item.drawer == "invert")
end

return Helpers
