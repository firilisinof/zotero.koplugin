local Download = {}

---@param component string|nil
---@return boolean
local function safeComponent(component)
    return type(component) == "string" and component ~= "" and component ~= "." and component ~= ".."
        and not component:find("[/\\%z]")
end

--- Resolve an attachment without moving existing documents. Example: API.getDirAndPath("ATTACH01").
---@param api ZoteroAPI
---@param key string
---@return string|nil, string|nil
function Download.getDirAndPath(api, key)
    local item = api.getItems()[key]
    local fields = item and item.data
    if not fields or not safeComponent(fields.filename) then return nil, nil end
    local parent = fields.parentItem or key
    if not safeComponent(parent) or not safeComponent(key) then return nil, nil end
    local directory = api.storage_dir .. "/" .. parent
    return directory, directory .. "/" .. fields.filename
end

--- Find an existing readable copy without checking credentials or versions. Example: API.getLocalAttachmentPath("ATTACH01").
---@param api ZoteroAPI
---@param key string
---@return string|nil
function Download.getLocalAttachmentPath(api, key)
    local item = api.getItems()[key]
    local fields = item and item.data
    if not fields or fields.itemType ~= "attachment" then return nil end
    if fields.contentType ~= "application/pdf" and fields.contentType ~= "application/epub+zip" then return nil end
    local _, path = api.getDirAndPath(key)
    return api.util.isFile(path) and path or nil
end

---@param api ZoteroAPI
---@param key string
---@return boolean
local function soleAttachment(api, key)
    local requested = api.getItems()[key].data
    local parent, count = requested.parentItem or key, 0
    for sibling_key, item in pairs(api.getItems()) do
        local fields = item.data or {}
        local readable = fields.contentType == "application/pdf" or fields.contentType == "application/epub+zip"
        if fields.itemType == "attachment" and readable and (fields.parentItem or sibling_key) == parent then
            count = count + 1
        end
    end
    return count == 1
end

--- Return the attachment-specific version marker. Example: API.getVersionPath("ATTACH01").
---@param api ZoteroAPI
---@param key string
---@return string|nil
function Download.getVersionPath(api, key)
    local directory = api.getDirAndPath(key)
    return directory and (directory .. "/.zotero-" .. key .. ".version")
end

--- Distinguish current files from merely present files. Example: API.isAttachmentCurrent("ATTACH01").
---@param api ZoteroAPI
---@param key string
---@return boolean
function Download.isAttachmentCurrent(api, key)
    local directory, path = api.getDirAndPath(key)
    if not api.util.isFile(path) then return false end
    local version = tonumber(api.util.read(api.getVersionPath(key)))
    -- Old versions were shared by every attachment under a parent. Trust them
    -- only when there is no sibling whose version could have produced the marker.
    if not version and soleAttachment(api, key) then version = tonumber(api.util.read(directory .. "/version")) end
    local remote = tonumber(api.getItems()[key].version)
    return version ~= nil and remote ~= nil and version >= remote
end

---@param api ZoteroAPI
---@param key string
---@return string|nil
local function attachmentError(api, key)
    local item = api.getItems()[key]
    if not item then return "Error: the requested file can not be found in the database: " .. tostring(key) end
    if not item.data or item.data.itemType ~= "attachment" then return "Error: this item is not an attachment: " .. key end
    local mode = item.data.linkMode
    if mode == "linked_file" then
        return "Error: this item is a linked attachment. Linked attachments are currently unsupported."
    end
    if mode ~= "imported_file" then return "Error: unsupported link mode '" .. tostring(mode) .. "'." end
    if not api.getDirAndPath(key) then
        return "Invalid filename '" .. tostring(item.data.filename) .. "' for " .. key .. ", expected a filename without directories"
    end
end

---@param api ZoteroAPI
---@param key string
---@param directory string
---@param stage string
---@return string|nil
local function fetchAttachment(api, key, directory, stage)
    if api.getWebDAVEnabled() then
        local _, err = api.downloadWebDAV(key, directory, stage)
        return err
    end
    local url = "https://api.zotero.org/" .. api.getLibraryPrefix() .. "/items/" .. key .. "/file"
    return api.fetchFile(url, api.getHeaders(api.getAPIKey()), stage)
end

---@param api ZoteroAPI
---@param key string
---@param path string
---@param stage string
---@return string|nil, string|nil
local function commitAttachment(api, key, path, stage)
    local ok, err = os.rename(stage, path)
    if not ok then
        os.remove(stage)
        return nil, "Could not replace " .. path .. ": " .. tostring(err)
    end
    err = api.util.write(api.getVersionPath(key), tostring(api.getItems()[key].version))
    if err then return nil, err end
    return path, nil
end

--- Download only when stale. Example: API.downloadAndGetPath("ATTACH01").
---@param api ZoteroAPI
---@param key string
---@param download_callback fun()|nil
---@return string|nil, string|nil
function Download.downloadAndGetPath(api, key, download_callback)
    local err = api.ensureKeyAndID() or attachmentError(api, key)
    if err then return nil, err end
    local directory, path = api.getDirAndPath(key)
    if api.isAttachmentCurrent(key) then return path, nil end
    local made, mkdir_error = api.util.mkdir(directory)
    if not made then return nil, "Could not create " .. directory .. ": " .. tostring(mkdir_error) end
    if download_callback then download_callback() end
    -- Stage beside the target. Neither an HTTP error page nor an interrupted
    -- archive extraction may replace a readable copy or touch its sidecar.
    local stage = path .. ".part"
    err = fetchAttachment(api, key, directory, stage)
    if err then os.remove(stage) return nil, err end
    return commitAttachment(api, key, path, stage)
end

--- Unpack WebDAV into the caller's staging file. Example: API.downloadWebDAV(key, dir, stage).
---@param api ZoteroAPI
---@param key string
---@param directory string
---@param target string
---@return string|nil, string|nil
function Download.downloadWebDAV(api, key, directory, target)
    local url = api.getWebDAVUrl()
    if not url or url == "" then return nil, "WebDAV url not set" end
    local archive = directory .. "/" .. key .. ".zip"
    local err = api.fetchFile(url .. "/" .. key .. ".zip", api.getWebDAVHeaders(), archive, true)
    if err then return nil, err end
    err = api.archive.extract(archive, target)
    os.remove(archive)
    if err then os.remove(target) return nil, err end
    return target, nil
end

---@param task fun(): string|nil, string|nil
---@return boolean, string|nil, string|nil
local function runInline(task)
    return true, task()
end

---@param api ZoteroAPI
---@param key string
---@return string|nil, string|nil
local function safeDownload(api, key)
    local ok, path, err = pcall(api.downloadAndGetPath, key)
    if not ok then return nil, tostring(path) end
    return path, err
end

---@param summary ZoteroDownloadSummary
---@param entry ZoteroRow
---@param path string|nil
---@param err string|nil
local function recordResult(summary, entry, path, err)
    if path then summary.downloaded = summary.downloaded + 1 return end
    summary.failed = summary.failed + 1
    table.insert(summary.errors, { key = entry.key, text = entry.text .. ": " .. tostring(err or "Download failed") })
end

---@param api ZoteroAPI
---@param entry ZoteroRow
---@param summary ZoteroDownloadSummary
---@param runner function
---@return boolean
local function downloadEntry(api, entry, summary, runner)
    if api.isAttachmentCurrent(entry.key) then summary.skipped = summary.skipped + 1 return true end
    local completed, path, err = runner(function() return safeDownload(api, entry.key) end)
    if not completed then return false end
    recordResult(summary, entry, path, err)
    return true
end

--- Download direct, filtered members and continue after failures. Example: API.downloadCollection("COLLAAA1").
---@param api ZoteroAPI
---@param key string
---@param progress_cb fun(summary: ZoteroDownloadSummary, entry: ZoteroRow): boolean|nil
---@param run_download fun(task: function): boolean, string|nil, string|nil
---@return ZoteroDownloadSummary
function Download.downloadCollection(api, key, progress_cb, run_download)
    local entries = api.getIndex().by_collection[key] or {}
    local summary = { total = #entries, downloaded = 0, skipped = 0, failed = 0, cancelled = 0, errors = {} }
    for index, entry in ipairs(entries) do
        local proceed = not progress_cb or progress_cb(summary, entry) ~= false
        if not proceed or not downloadEntry(api, entry, summary, run_download or runInline) then
            summary.cancelled = #entries - index + 1
            break
        end
    end
    return summary
end

return Download
