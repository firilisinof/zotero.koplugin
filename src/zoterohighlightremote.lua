local Remote = {}
local origin = "https://api.zotero.org/"

--- Make one bounded request, respecting Backoff even on successful replies.
---@param api ZoteroAPI
---@param key string
---@param path string
---@param method string|nil
---@param payload table|nil
---@param headers table|nil
---@return table
function Remote.request(api, key, path, method, payload, headers)
    local response = api.requestJSON(origin .. path, key, method, payload, headers)
    local delay = tonumber(response.headers["retry-after"]) or tonumber(response.headers.backoff)
    if response.error or (delay and delay > 0) or response.code == 401 or response.code == 403 then
        error({ error = response.error or "Zotero requested a highlight-sync pause", delay = delay or 60,
            paused = response.code == 401 or response.code == 403 })
    end
    return response
end

--- Authorize writes to the actual attachment library, independently of position settings.
---@param api ZoteroAPI
---@param key string
---@param library string
---@return table
function Remote.authorize(api, key, library)
    local response = Remote.request(api, key, "keys/current")
    assert(response.code == 200, "Highlight authorization returned HTTP " .. response.code)
    local body, permission = response.body
    assert(body and tostring(body.userID):match("^%d+$"), "Expected numeric Zotero API key owner")
    local kind, identifier = library:match("^(%a+)/(%d+)$")
    assert(kind == "users" or kind == "groups", "Invalid highlight library " .. tostring(library))
    if kind == "users" and tostring(body.userID) == identifier then permission = body.access and body.access.user end
    if kind == "groups" and body.access and body.access.groups then
        permission = body.access.groups[identifier] or body.access.groups.all
    end
    assert(permission and permission.library and permission.write, "Highlight sync requires read and write permission for " .. library)
    return { owner = tostring(body.userID), library = library }
end

--- Verify immutable attachment content before any annotation read or write.
---@param api ZoteroAPI
---@param key string
---@param identity table
function Remote.verify(api, key, identity)
    local response = Remote.request(api, key, identity.library .. "/items/" .. identity.key)
    local item = response.body and response.body.data
    assert(response.code == 200 and item and item.itemType == "attachment" and not (item.deleted == 1 or item.deleted == true)
        and item.contentType == identity.format and type(item.md5) == "string" and item.md5:lower() == identity.md5,
        "Attachment checksum or format differs from Zotero; highlight sync paused")
end

--- Read a consistent complete child snapshot; a partial listing never implies deletion.
---@param api ZoteroAPI
---@param key string
---@param identity table
---@return table
function Remote.list(api, key, identity)
    local items, start, version, total = {}, 0
    repeat
        local response = Remote.request(api, key, identity.library .. "/items/" .. identity.key ..
            "/children?format=json&includeTrashed=1&limit=100&start=" .. start)
        assert(response.code == 200 and type(response.body) == "table", "Expected complete Zotero annotation listing")
        local current = tonumber(response.headers["last-modified-version"])
        local count = tonumber(response.headers["total-results"])
        assert(current and count and count >= 0 and count % 1 == 0, "Missing annotation listing version or size")
        assert(not version or (version == current and total == count), "Zotero library changed during annotation pagination; retry")
        version, total = current, count
        for _, item in ipairs(response.body) do
            assert(item.key and item.data and item.data.parentItem == identity.key and not items[item.key], "Invalid or duplicate Zotero child item")
            items[item.key] = item
        end
        start = start + #response.body
        assert(start <= total and (#response.body > 0 or start == total), "Incomplete Zotero child page")
    until start >= total
    return items
end

--- Check an absent tracked key directly; a moved annotation is never a deletion.
---@param api ZoteroAPI
---@param key string
---@param identity table
---@param annotation_key string
---@return table|nil
function Remote.get(api, key, identity, annotation_key)
    assert(annotation_key:match("^[23456789A-NP-Z]+$") and #annotation_key == 8, "Invalid annotation key " .. tostring(annotation_key))
    local response = Remote.request(api, key, identity.library .. "/items/" .. annotation_key)
    if response.code == 404 then return end
    assert(response.code == 200 and response.body.data.parentItem == identity.key, "Tracked annotation moved or unavailable; expected original parent")
    return response.body
end

--- Write just the owned fields, or recoverably trash a tracked highlight, using its version.
---@param api ZoteroAPI
---@param secret string
---@param identity table
---@param entry table
---@param current table|nil
---@param fields table
---@return table
function Remote.write(api, secret, identity, entry, current, fields)
    local response
    if current then
        response = Remote.request(api, secret, identity.library .. "/items/" .. entry.key, "PATCH", fields,
            { ["if-unmodified-since-version"] = tostring(current.version) })
        assert(response.code == 204, "Conditional annotation update returned HTTP " .. response.code)
    else
        fields.key, fields.version, fields.itemType, fields.parentItem = entry.key, 0, "annotation", identity.key
        response = Remote.request(api, secret, identity.library .. "/items", "POST", { fields })
        assert(response.code == 200 and response.body and
            ((response.body.successful or {})["0"] or (response.body.unchanged or {})["0"]),
            "Conditional annotation creation failed; queued key retained")
    end
    api.index = nil
    return assert(Remote.get(api, secret, identity, entry.key), "Written annotation missing during confirmation")
end

return Remote
