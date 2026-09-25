-- The worker returns evidence; only the parent changes local progress state.
local Remote = {}
local origin = "https://api.zotero.org/"

-- Backoff on a successful response also forbids the next request in this exchange.
---@param api ZoteroAPI
---@param url string
---@param key string
---@param method string|nil
---@param payload table|nil
---@param headers table|nil
---@return table
local function exchangeJSON(api, url, key, method, payload, headers)
    local response = api.requestJSON(url, key, method, payload, headers)
    if (tonumber(response.headers.backoff) or 0) > 0 then
        response.error = "Zotero requested a pause; position remains pending"
    end
    return response
end

---@param response table
---@return table
local function failure(response)
    local code, headers = response.code, response.headers
    return { error = response.error or ("Zotero position request returned HTTP " .. code), code = code,
        paused = code == 401 or code == 403,
        delay = tonumber(headers["retry-after"]) or tonumber(headers["backoff"]) or 60 }
end

--- Resolve personal-settings ownership and write access. Example: Remote.authorize(api, key).
---@param api ZoteroAPI
---@param key string
---@return table
function Remote.authorize(api, key)
    local response = exchangeJSON(api, origin .. "keys/current", key)
    if response.error or response.code ~= 200 then return failure(response) end
    local body = response.body
    local access = body and body.access and body.access.user
    if not body or not tostring(body.userID):match("^%d+$") or not access or not access.library or not access.write then
        return { error = "Position sharing requires personal-library read and write permission", paused = true }
    end
    return { owner = tostring(body.userID) }
end

--- Build a setting path in the key owner's personal library, including group files.
---@param identity table
---@return string
function Remote.settingURL(identity)
    assert(tostring(identity.owner):match("^%d+$"), "Invalid position owner " .. tostring(identity.owner))
    local kind, identifier = identity.library:match("^(%a+)/(%d+)$")
    assert(kind == "users" or kind == "groups", "Invalid position library " .. tostring(identity.library))
    assert(identity.key:match("^[A-Z0-9]+$") and #identity.key == 8, "Invalid attachment key " .. tostring(identity.key))
    local library = kind == "groups" and ("g" .. identifier) or "u"
    assert(kind == "groups" or identifier == identity.owner, "Personal attachment does not belong to the key owner")
    return origin .. "users/" .. identity.owner .. "/settings/lastPageIndex_" .. library .. "_" .. identity.key
end

---@param response table
---@return table
local function setting(response)
    if response.error then return failure(response) end
    if response.code == 404 then return { version = 0 } end
    if response.code ~= 200 then return failure(response) end
    local body = response.body
    if type(body) ~= "table" or type(body.version) ~= "number" or body.version < 0 or body.version % 1 ~= 0
        or (type(body.value) ~= "number" and type(body.value) ~= "string") then
        return { error = "Zotero returned an invalid position setting" }
    end
    return { version = body.version, value = body.value }
end

--- Fetch the current setting without changing any local state. Example: Remote.read(api, key, identity).
---@param api ZoteroAPI
---@param key string
---@param identity table
---@return table
function Remote.read(api, key, identity)
    return setting(exchangeJSON(api, Remote.settingURL(identity), key))
end

---@param api ZoteroAPI
---@param key string
---@param identity table
---@return table|nil, table|nil
local function verifyAttachment(api, key, identity)
    local response = exchangeJSON(api, origin .. identity.library .. "/items/" .. identity.key, key)
    if response.error or response.code ~= 200 then return nil, failure(response) end
    local attachment = response.body and response.body.data
    if not attachment or attachment.deleted == true or attachment.deleted == 1
        or type(attachment.md5) ~= "string" or attachment.md5:lower() ~= identity.md5 then
        return nil, { error = "The local file does not match Zotero's attachment checksum" }
    end
    return attachment
end

--- Exchange one immutable snapshot; return conflicts to the parent for a fresh local checkpoint.
---@param api ZoteroAPI
---@param key string
---@param snapshot table
---@return table
function Remote.exchange(api, key, snapshot)
    local _, mismatch = verifyAttachment(api, key, snapshot.identity)
    if mismatch then return mismatch end
    local current = Remote.read(api, key, snapshot.identity)
    if current.error or (not snapshot.pending and current.value ~= nil) then return current end
    if current.value == snapshot.value then return { value = current.value, version = current.version, pushed = true } end
    local response = exchangeJSON(api, Remote.settingURL(snapshot.identity), key, "PUT", { value = snapshot.value },
        { ["if-unmodified-since-version"] = tostring(current.version) })
    if response.error then return failure(response) end
    -- Return to the parent before retrying: it owns any newer local navigation.
    if response.code == 412 then return { conflict = true } end
    if response.code ~= 204 then return failure(response) end
    local confirmed = Remote.read(api, key, snapshot.identity)
    if confirmed.error then return confirmed end
    if confirmed.value == snapshot.value then confirmed.pushed = true; return confirmed end
    return { error = "Position changed during confirmation; local progress remains pending", delay = 60 }
end

return Remote
