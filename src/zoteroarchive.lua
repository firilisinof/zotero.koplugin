local Archiver = require("ffi/archiver")
local Archive = {}

---@param reader table
---@return string|nil
local function firstFile(reader)
    for entry in reader:iterate() do
        if entry.mode == "file" then return entry.path end
    end
end

--- Extract one Zotero attachment to a staging path. Example: Archive.extract(zip, temporary).
---@param zip_path string
---@param target_path string
---@return string|nil
function Archive.extract(zip_path, target_path)
    -- libarchive avoids an external unzip binary and its overwrite prompt, which
    -- used to hang the reader forever (fixed in 4d718f1).
    local reader = Archiver.Reader:new()
    if not reader:open(zip_path) then
        return "Could not open the downloaded archive: " .. tostring(reader.err or "unknown error")
    end
    local entry_path = firstFile(reader)
    -- Use the recorded filename even if the archive entry is spelled differently.
    local extracted = entry_path and reader:extractToPath(entry_path, target_path)
    local err = reader.err
    reader:close()
    if not entry_path then return "The downloaded archive holds no file" end
    if not extracted then return "Could not unpack the archive: " .. tostring(err or "unknown error") end
end

return Archive
