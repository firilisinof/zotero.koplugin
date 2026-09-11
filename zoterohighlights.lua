local Store = require("zoteroprogressstore")
local Identity = require("zoteroprogressidentity")
local Helpers = require("zoterohighlightutil")
local Local = require("zoterohighlightlocal")
local Remote = require("zoterohighlightremote")
local Exchange = require("zoterohighlightexchange")
local Highlights = {}
Highlights.__index = Highlights

--- Create a shared coordinator with its own durable, account-scoped journal.
---@param api ZoteroAPI
---@param runtime table
---@return table
function Highlights.new(api, runtime)
    local retry = api.settings:readSetting("highlight_retry", {})
    local valid = retry.key_hash == Identity.keyHash(api.getAPIKey() or "")
    return setmetatable({ api = api, runtime = runtime, store = Store.new(api, "highlights.json"),
        next_try = valid and retry.at or 0, paused = valid and retry.paused or nil }, Highlights)
end

--- Contain errors at lifecycle boundaries. Example: highlights:safe("checkpoint").
---@param method string
---@return unknown
function Highlights:safe(method, ...)
    local ok, result = pcall(self[method], self, ...)
    if ok then return result end
    self.status = "Highlight sync unavailable: " .. tostring(result)
    if self.api.operation == "highlights" and not self.cancel then self.api.endOperation() end
end

--- Highlight sharing is independent and off by default. Example: highlights:enabled().
---@return boolean
function Highlights:enabled() return self.api.settings:readSetting("share_highlights", false) == true end

---@param identity table|nil
---@return boolean
function Highlights:authorized(identity)
    local auth = self.api.settings:readSetting("highlight_authorization")
    return self:enabled() and auth and auth.key_hash == Identity.keyHash(self.api.getAPIKey() or "")
        and auth.library == self.api.getLocalLibraryPrefix()
        and (not identity or (identity.owner == auth.owner and identity.library == auth.library and identity.key_hash == auth.key_hash))
end

--- Apply authorization only to the account that requested it. Example: highlights:enable(result, key, library).
---@param result table
---@param key string
---@param library string
function Highlights:enable(result, key, library)
    self.cancel = nil; self.api.endOperation()
    if key ~= self.api.getAPIKey() or library ~= self.api.getLocalLibraryPrefix() then return end
    if result.error then self.status = result.error; self.runtime:message(result.error, 5); return end
    result.key_hash = Identity.keyHash(key)
    self.api.settings:saveSetting("highlight_authorization", result)
    self.api.settings:saveSetting("share_highlights", true)
    self.api.settings:delSetting("highlight_retry"); self.api.saveModifiedItems()
    self.next_try, self.paused = 0, nil
    if self.reader then self:attach(self.reader, self.origin) end
end

--- Check actual library write access before enabling. Example: highlights:toggle().
function Highlights:toggle()
    if self:enabled() then
        self:checkpoint(); self.api.settings:saveSetting("share_highlights", false); self.api.saveModifiedItems()
        if self.cancel then self.cancel() end
        self.status = "Highlight sync is off"; return
    end
    if not self.runtime:isOnline() then self.runtime:message("Connect to Wi-Fi to enable highlight sync.", 4); return end
    if not self.api.beginOperation("highlights") then self.runtime:message("A Zotero operation is already running.", 3); return end
    local key, library = self.api.getAPIKey(), self.api.getLocalLibraryPrefix()
    self.cancel = self.runtime:background(function()
        local ok, result = pcall(Remote.authorize, self.api, key, library)
        return ok and result or { error = type(result) == "table" and result.error or tostring(result) }
    end, function(result) self:enable(result, key, library) end)
end

--- Refuse changed files and invalidate stale DOM deliveries. Example: highlights:enroll(identity).
---@param identity table
---@return boolean
function Highlights:enroll(identity)
    local record = self.store:get(identity)
    if record and (record.identity.md5 ~= identity.md5 or record.identity.path ~= identity.path) then
        self.status = "Attachment changed since highlight enrollment; sync paused"; return false
    end
    local reader = self.reader
    record = record or { identity = identity, entries = {}, generation = 0, pending = true }
    record.identity = identity
    local dom_version = reader.rolling and (reader.doc_settings:readSetting("cre_dom_version") or reader.document:getLatestDomVersion()) or nil
    if record.dom_version ~= dom_version then
        record.dom_version, record.delivery, record.pending = dom_version, nil, true
        record.generation = record.generation + 1
    end
    self.store:put(record)
    return true
end

--- Bind plugin-opened documents and their reloads. Example: highlights:attach(reader, context).
---@param reader table
---@param context table
function Highlights:attach(reader, context)
    self.reader, self.origin, self.identity = reader, context, nil
    if not context then return end
    require("zoterohighlightpdfview").bind(reader)
    reader.zotero_highlights_rebind = function(reopened) self:safe("attach", reopened, context) end
    if not self:authorized() or context.library ~= self.api.getLocalLibraryPrefix() then return end
    local identity, reason = Identity.capture(self.api, context.key, context.path, "highlight_authorization")
    if not identity then self.status = reason; return end
    if not self:enroll(identity) then return end
    self.identity = identity
    self:checkpoint()
    self.runtime:later(0.3, function() self:safe("sync", false) end)
end

---@return boolean
function Highlights:active()
    return self.identity and self:authorized(self.identity) and self.reader and self.reader.document
        and self.reader.document.file == self.identity.path and self.reader.annotation
end

--- Replay only an unchanged journal source or target. Example: highlights:deliver(record).
---@param record table
function Highlights:deliver(record)
    local delivery = record.delivery
    if Local.matches(record.entries, delivery.before) or Local.matches(record.entries, delivery.after) then
        self.applying = true
        local ok, err = pcall(Local.apply, self.reader, delivery.before, delivery.after, self.runtime)
        self.applying = false
        if not ok then error(err) end
        record.entries = delivery.after
    end
    -- A local edit after the worker snapshot invalidates the pull; retain the
    -- old baseline so the next exchange detects concurrent changes.
    record.delivery = nil
end

--- Persist edits/deletions before lifecycle boundaries. Example: highlights:checkpoint().
function Highlights:checkpoint()
    if not self:active() or self.applying then return end
    if Identity.checksum(self.identity.path) ~= self.identity.md5 then self.status = "Attachment contents changed; highlight sync paused"; return end
    local record = self.store:get(self.identity)
    local changed = Local.capture(self.reader, record)
    if record.delivery then self:deliver(record); changed = true end
    if changed then
        record.generation, record.pending = record.generation + 1, true
        self.store:put(record)
        Local.save(self.reader)
    end
end

--- Save immediately for offline durability and coalesce automatic network exchanges.
function Highlights:changed()
    if not self:active() or self.applying then return end
    self:checkpoint()
    if self.push_task then self.runtime:unschedule(self.push_task) end
    self.push_task = function() self:safe("sync", false) end
    self.runtime:later(10, self.push_task)
end

---@return table|nil
function Highlights:snapshot()
    if self:active() then return self.store:get(self.identity) end
    for _, record in pairs(self.store:load().records) do
        if self:authorized(record.identity) and record.pending and not record.delivery then return record end
    end
end

---@param result table
function Highlights:failure(result)
    self.status = result.error
    self.next_try, self.paused = self.runtime:now() + (result.delay or 60), result.paused
    self.api.settings:saveSetting("highlight_retry", { key_hash = Identity.keyHash(self.api.getAPIKey()),
        at = self.next_try, paused = self.paused })
    self.api.saveModifiedItems()
end

---@param snapshot table
---@param result table
function Highlights:accept(snapshot, result)
    if not self:authorized(snapshot.identity) then return end
    self:checkpoint()
    local record = self.store:get(snapshot.identity)
    if result.entries and record.generation == snapshot.generation
        and Identity.checksum(snapshot.identity.path, true) == snapshot.identity.md5 then
        record.delivery = { before = record.entries, after = result.entries }
        record.warnings, record.pdf_matrices = result.warnings, result.pdf_matrices
        record.pending = result.error ~= nil
        for _, entry in pairs(result.entries) do
            if entry.error or entry.conflict then record.pending = true end
        end
        if Local.matches(record.entries, result.entries) then record.entries, record.delivery = result.entries, nil end
        self.store:put(record)
        self:checkpoint()
        self.api.index = nil
    end
    if result.error then self:failure(result) else self.status = "Highlights synchronized" end
end

--- Run one cancellable worker and release its scratch file. Example: highlights:launch(snapshot, true).
---@param snapshot table
---@param manual boolean|nil
function Highlights:launch(snapshot, manual)
    -- The parent owns cleanup too, including a killed or timed-out PDF worker.
    snapshot.scratch = os.tmpname()
    self.cancel = self.runtime:background(function() return Exchange.run(self.api, self.api.getAPIKey(), snapshot) end, function(result)
        os.remove(snapshot.scratch)
        self.cancel = nil; self.api.endOperation()
        self:safe("accept", snapshot, result)
        if manual then self.runtime:message(self:statusText(), 5) end
        if not result.error then self:drain(snapshot.identity) end
    end)
end

--- Sync using the shared operation lock. Example: highlights:sync(true).
---@param manual boolean|nil
---@param queued table|nil
function Highlights:sync(manual, queued)
    if not self:enabled() then return end
    self:checkpoint()
    if not self:authorized() then self.status = "Re-enable highlight sync to check library permissions"; return end
    if not self.runtime:isOnline() then self.status = "Highlights pending (offline)"; return end
    if self.paused or self.runtime:now() < self.next_try then return end
    local snapshot = queued and self.store:get(queued) or self:snapshot()
    if not snapshot or snapshot.delivery or not self:authorized(snapshot.identity) then return end
    if Identity.checksum(snapshot.identity.path, true) ~= snapshot.identity.md5 then
        self.status = "Queued attachment changed; highlight sync paused"; return
    end
    if not self.api.beginOperation("highlights") then
        self.runtime:later(1, function() self:safe("sync", false, queued) end); return
    end
    self:launch(snapshot, manual)
end

---@param previous table
function Highlights:drain(previous)
    for _, record in pairs(self.store:load().records) do
        if record.pending and not record.delivery and self:authorized(record.identity)
            and Store.key(previous) ~= Store.key(record.identity) then
            -- Do not spin on conversion failures or conflicts; retry on the next trigger.
            local retryable = true
            for _, entry in pairs(record.entries) do if entry.error or entry.conflict then retryable = false end end
            if retryable then self.runtime:later(0.3, function() self:safe("sync", false, record.identity) end); return end
        end
    end
end

--- Retain pending imports until the same document is reopened; never edit a closed sidecar.
---@param reader table
function Highlights:close(reader)
    if reader ~= self.reader then return end
    self:checkpoint()
    require("zoterohighlightpdfview").unbind(reader)
    if self.push_task then self.runtime:unschedule(self.push_task) end
    self.reader, self.identity, self.origin = nil, nil, nil
    self.runtime:later(0.3, function() self:safe("sync", false) end)
end

--- Cancel HTTP without waiting, retaining the durable outbox. Example: highlights:suspend().
function Highlights:suspend()
    self:checkpoint()
    if self.cancel then self.cancel() end
end

--- Resolve one reviewed conflict; subsequent edits invalidate this choice.
---@param id string
---@param side string
function Highlights:resolve(id, side)
    assert(side == "local" or side == "remote", "Expected local or remote conflict choice")
    if not self:active() then return end
    local record = self.store:get(self.identity)
    local entry = record.entries[id]
    if not entry or not entry.conflict then return end
    entry.resolution = { side = side, remote = entry.conflict.remote, local_value = entry.conflict.local_value }
    self.store:put(record); self:sync(true)
end

--- Describe pending conflicts/errors without exposing keys or coordinates.
---@return string
function Highlights:statusText()
    if not self:enabled() then return "Highlight sync is off" end
    local record = self:active() and self.store:get(self.identity)
    local conflicts, failures = 0, 0
    for _, entry in pairs(record and record.entries or {}) do
        if entry.conflict then conflicts = conflicts + 1 end
        if entry.error then failures = failures + 1 end
    end
    if conflicts > 0 then return conflicts .. " highlight conflicts; open Resolve highlight conflicts" end
    if failures > 0 then return failures .. " highlights pending: " .. self:firstError(record) end
    if record and record.warnings and #record.warnings > 0 then
        return #record.warnings .. " Zotero highlights preserved: " .. record.warnings[1]
    end
    return self.status or "Highlights pending"
end

---@param record table
---@return string
function Highlights:firstError(record)
    for _, entry in pairs(record.entries) do if entry.error then return entry.error end end
    return "Conversion unavailable"
end

return Highlights
