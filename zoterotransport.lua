local ltn12 = require("ltn12")
local socketutil = require("socketutil")
local sha2 = require("ffi/sha2")
local Transport = {}

---@param api ZoteroAPI
---@param request table
---@param file_transfer boolean|nil
---@return number|nil, number|string, table|nil
local function request(api, request, file_transfer)
    local block = file_transfer and socketutil.FILE_BLOCK_TIMEOUT or socketutil.LARGE_BLOCK_TIMEOUT
    local total = file_transfer and socketutil.FILE_TOTAL_TIMEOUT or socketutil.LARGE_TOTAL_TIMEOUT
    socketutil:set_timeout(block, total)
    local ok, result, code, headers = pcall(api.http.request, request)
    socketutil:reset_timeout()
    if not ok then return nil, tostring(result) end
    return result, code, headers
end

--- Translate HTTP failures. Example: API.verifyResponse(1, 403).
---@param api ZoteroAPI
---@param result number|nil
---@param code number|string
---@return string|nil
function Transport.verifyResponse(api, result, code)
    if result ~= 1 then return "Error: " .. tostring(code) end
    if code ~= 200 then return "Error: API responded with status code " .. tostring(code) end
end

--- Build read API headers. Example: API.getHeaders(key).
---@param api ZoteroAPI
---@param api_key string
---@return table<string, string>
function Transport.getHeaders(api, api_key)
    return { ["zotero-api-key"] = api_key, ["zotero-api-version"] = "3" }
end

--- Exchange a JSON object, retaining HTTP status for conditional writes. Example: API.requestJSON(url, key).
---@param api ZoteroAPI
---@param url string
---@param key string
---@param method string|nil
---@param payload table|nil
---@param extra table|nil
---@return table
function Transport.requestJSON(api, url, key, method, payload, extra)
    local headers, chunks = api.getHeaders(key), {}
    for name, value in pairs(extra or {}) do headers[name] = value end
    local encoded = payload and api.util.encode(payload)
    if encoded then headers["content-type"], headers["content-length"] = "application/json", tostring(#encoded) end
    local result, code, response = request(api, { method = method or "GET", url = url, headers = headers,
        source = encoded and ltn12.source.string(encoded), sink = ltn12.sink.table(chunks) })
    if result ~= 1 then return { code = 0, error = "Could not reach Zotero", headers = {} } end
    local body = table.concat(chunks)
    local ok, decoded = pcall(api.util.decode, body)
    return { code = tonumber(code) or 0, body = ok and decoded or nil, headers = response or {} }
end

--- Build personal WebDAV authorization. Example: API.getWebDAVHeaders().
---@param api ZoteroAPI
---@return table<string, string>
function Transport.getWebDAVHeaders(api)
    local credentials = (api.getWebDAVUser() or "") .. ":" .. (api.getWebDAVPassword() or "")
    return { Authorization = "Basic " .. sha2.bin_to_base64(credentials) }
end

---@param api ZoteroAPI
---@param url string
---@param headers table<string, string>
---@return table|nil, string|nil, table|nil
local function fetchPage(api, url, headers)
    local chunks = {}
    local result, code, response_headers = request(api, {
        method = "GET", url = url, headers = headers, sink = ltn12.sink.table(chunks),
    })
    -- Check before touching headers, absent when the request never reached the server.
    local err = api.verifyResponse(result, code)
    if err then return nil, err end
    local ok, entries = pcall(api.util.decode, table.concat(chunks))
    if not ok or type(entries) ~= "table" then return nil, "Error: failed to parse JSON in response" end
    return entries, nil, response_headers or {}
end

---@param api ZoteroAPI
---@param url string
---@param headers table<string, string>
---@param start integer
---@return table|nil, string|nil, number|nil, string|nil
local function collectionPage(api, url, headers, start)
    local entries, err, response = fetchPage(api, ("%s&limit=100&start=%i"):format(url, start), headers)
    if err then return nil, err end
    local total = tonumber(response["total-results"])
    if not total or total < 0 then return nil, "Error: could not determine number of items in library" end
    return entries, nil, total, response["last-modified-version"]
end

--- Fetch every page, optionally consuming each page. Example: API.fetchCollectionPaginated(url, headers).
---@param api ZoteroAPI
---@param url string
---@param headers table<string, string>
---@param callback fun(entries: ZoteroItem[])|nil
---@return table|string|nil, string|nil
function Transport.fetchCollectionPaginated(api, url, headers, callback)
    local items, start, total, version = {}, 0, 0, nil
    repeat
        local entries, err, count, page_version = collectionPage(api, url, headers, start)
        if err then return nil, err end
        total, version = count, page_version
        if callback then
            callback(entries)
        else
            table.move(entries, 1, #entries, #items + 1, items)
        end
        start = start + 100
    until start >= total
    if callback then return version, nil end
    return items, nil
end

--- Stream a response to a staging file. Example: API.fetchFile(url, headers, path).
---@param api ZoteroAPI
---@param url string
---@param headers table<string, string>
---@param path string
---@param webdav boolean|nil
---@return string|nil
function Transport.fetchFile(api, url, headers, path, webdav)
    local file, err = io.open(path, "wb")
    if not file then return "Error: could not open " .. path .. " for writing: " .. tostring(err) end
    local result, code = request(api, {
        method = "GET", url = url, headers = headers, redirect = true, sink = ltn12.sink.file(file),
    }, true)
    -- A transport failure may never finish its sink.
    if io.type(file) == "file" then file:close() end
    err = api.verifyResponse(result, code)
    if not err then return nil end
    os.remove(path)
    if webdav then return "Download failed with status code " .. tostring(code) end
    return err
end

---@param result number|nil
---@param code number|string
---@return string|nil
local function webdavError(result, code)
    if result ~= 1 then return "Could not reach the server: " .. tostring(code) end
    if code == 200 or code == 207 then return nil end
    if code == 400 or code == 401 or code == 403 then
        return "Reached server, but access forbidden. Check username and password."
    end
    if code == 404 then return "Reached server, but the folder was not found. Check the WebDAV URL." end
    return "Unexpected response from server: status code " .. tostring(code)
end

--- Check WebDAV with PROPFIND. Example: API.checkWebDAV().
---@param api ZoteroAPI
---@return string|nil
function Transport.checkWebDAV(api)
    if api.getLibraryType() == "group" then return "Group libraries use Zotero file storage." end
    local url = api.getWebDAVUrl()
    if not url or url == "" then return "No WebDAV URL provided" end
    local result, code = request(api, { url = url, method = "PROPFIND", headers = api.getWebDAVHeaders() })
    return webdavError(result, code)
end

return Transport
