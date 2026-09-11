local rapidjson = require("rapidjson")
local LuaSettings = require("luasettings")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local ffiutil = require("ffi/util")

local Util = {}

--- Read a complete file, or nil when absent. Example: Util.read(path).
---@param path string
---@return string|nil
function Util.read(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local contents = file:read("*all")
    file:close()
    return contents
end

--- Replace a small metadata file atomically. Example: Util.write(path, "12").
---@param path string
---@param contents string
---@param durable boolean|nil
---@return string|nil error
function Util.write(path, contents, durable)
    local temporary = path .. ".tmp"
    local file, err = io.open(temporary, "wb")
    if not file then return "Could not write " .. temporary .. ": " .. tostring(err) end
    local written, write_error = file:write(contents)
    if written and durable then
        local synced, sync_error = ffiutil.fsyncOpenedFile(file, true)
        if not synced then written, write_error = nil, sync_error end
    end
    local closed, close_error = file:close()
    if not written or not closed then
        os.remove(temporary)
        return "Could not finish " .. temporary .. ": " .. tostring(write_error or close_error)
    end
    local renamed, rename_error = os.rename(temporary, path)
    if renamed then
        if durable then
            local synced, sync_error = ffiutil.fsyncDirectory(path)
            if not synced then return "Could not flush progress directory: " .. tostring(sync_error) end
        end
        return nil
    end
    os.remove(temporary)
    return "Could not replace " .. path .. ": " .. tostring(rename_error)
end

--- Remove a file and any replacement Util.write left unfinished. Example: Util.discard(path).
---@param path string
function Util.discard(path)
    os.remove(path .. ".tmp")
    os.remove(path)
end

--- Test for a regular file. Example: Util.isFile(path).
---@param path string|nil
---@return boolean
function Util.isFile(path)
    return path ~= nil and lfs.attributes(path, "mode") == "file"
end

--- Create storage parents. Example: Util.mkdir(path).
---@param path string
---@return boolean|nil, string|nil
function Util.mkdir(path)
    return util.makePath(path)
end

--- Open KOReader settings. Example: Util.openSettings(path).
---@param path string
---@return LuaSettings
function Util.openSettings(path)
    return LuaSettings:open(path)
end

--- Decode JSON, raising on malformed input like LuaJSON did. Example: Util.decode("{}").
--- JSON null decodes to the truthy rapidjson.null. Arrays and objects keep their kind when re-encoded.
---@param contents string
---@return table
function Util.decode(contents)
    local decoded, err = rapidjson.decode(contents)
    -- Omit the contents themselves: a Zotero key response carries the API key.
    if decoded == nil then error(("Could not decode JSON: %s, expected a JSON document in %d bytes"):format(tostring(err), #contents), 2) end
    return decoded
end

--- Encode JSON. Example: Util.encode(items).
--- Only string keys and sequences survive: rapidjson silently drops sparse numeric keys.
---@param entries table
---@return string
function Util.encode(entries)
    return rapidjson.encode(entries)
end

--- Strip note markup and decode entities. Example: Util.plainText("<p>Read</p>").
---@param html string
---@return string
function Util.plainText(html)
    return util.htmlToPlainText(html)
end

return Util
