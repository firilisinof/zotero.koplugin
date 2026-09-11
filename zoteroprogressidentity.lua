local sha2 = require("ffi/sha2")
local lfs = require("libs/libkoreader-lfs")
local Identity = {}
local checksums = {}

---@param path string
---@return string|nil
local function fileStamp(path)
    local stat = lfs.attributes(path)
    if not stat or stat.mode ~= "file" then return end
    return table.concat({ stat.size, stat.modification, stat.change, stat.ino or 0 }, ":")
end

--- Bind permission evidence to a key without persisting the secret. Example: Identity.keyHash(key).
---@param key string
---@return string
function Identity.keyHash(key)
    return sha2.sha256(key)
end

--- Hash the complete attachment, invalidating on file replacement or modification.
---@param path string
---@param force boolean|nil
---@return string|nil, string|nil
function Identity.checksum(path, force)
    local stamp = fileStamp(path)
    if not stamp then return nil, "Attachment file is missing: " .. tostring(path) end
    if not force and checksums[path] and checksums[path].stamp == stamp then return checksums[path].md5 end
    local file, err = io.open(path, "rb")
    if not file then return nil, err end
    local digest = sha2.md5()
    while true do
        local chunk, read_error = file:read(65536)
        if read_error then file:close(); return nil, "Could not read attachment: " .. tostring(read_error) end
        if not chunk then break end
        digest(chunk)
    end
    file:close()
    if fileStamp(path) ~= stamp then return nil, "Attachment changed while computing its checksum" end
    local hash = digest()
    checksums[path] = { stamp = stamp, md5 = hash }
    return hash
end

--- Capture immutable attachment identity before a reader opens. Example: Identity.capture(api, key, path).
---@param api ZoteroAPI
---@param key string
---@param path string
---@param authorization string|nil
---@return table|nil, string|nil
function Identity.capture(api, key, path, authorization)
    local auth = api.settings:readSetting(authorization or "progress_authorization")
    if not auth or auth.key_hash ~= Identity.keyHash(api.getAPIKey() or "") then return nil, "Check position-sharing permissions in Settings" end
    local item = api.getItems()[key]
    if not item or api.getLocalAttachmentPath(key) ~= path then return nil, "Attachment identity or path is unavailable" end
    local md5, err = Identity.checksum(path, true)
    if not md5 then return nil, err end
    if type(item.data.md5) ~= "string" or item.data.md5:lower() ~= md5 then return nil, "The local file has no matching Zotero checksum; synchronize library metadata" end
    return { owner = auth.owner, library = api.getLocalLibraryPrefix(), key = key, path = path,
        md5 = md5, format = item.data.contentType, key_hash = auth.key_hash }
end

return Identity
