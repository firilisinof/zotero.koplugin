local Store = require("zoteroprogressstore")
local Identity = require("zoteroprogressidentity")
local Remote = require("zoteroprogressremote")
local Codec = require("zoteroprogresscodec")
local Progress = {}
Progress.__index = Progress

--- Create one coordinator shared by file-manager and reader plugin instances.
---@param api ZoteroAPI
---@param runtime table
---@return table
function Progress.new(api, runtime)
    local retry = api.settings:readSetting("progress_retry", {})
    local valid = retry.key_hash == Identity.keyHash(api.getAPIKey() or "")
    return setmetatable({ api = api, runtime = runtime, store = Store.new(api), last_push = 0,
        next_try = valid and retry.at or 0, paused = valid and retry.paused or nil,
        status = valid and retry.reason or nil }, Progress)
end

--- Contain disk/codec failures at UI and lifecycle boundaries. Example: progress:safe("checkpoint").
---@param method string
---@return table|boolean|string|nil
function Progress:safe(method, ...)
    local ok, result = pcall(self[method], self, ...)
    if ok then return result end
    if self.api.operation == "position" and not self.cancel then self.api.endOperation() end
    self.status = "Position sharing unavailable: " .. tostring(result)
end

--- Sharing remains opt-in. Example: progress:enabled().
---@return boolean
function Progress:enabled()
    return self.api.settings:readSetting("share_reading_position", false) == true
end

---@return boolean
function Progress:credentialsMatch()
    local auth = self.api.settings:readSetting("progress_authorization")
    return auth and auth.key_hash == Identity.keyHash(self.api.getAPIKey() or "")
end

--- Check permissions before enabling, without turning on Wi-Fi. Example: progress:toggle().
function Progress:toggle()
    if self:enabled() then
        self:checkpoint()
        self.api.settings:saveSetting("share_reading_position", false)
        self.api.saveModifiedItems()
        if self.cancel then self.cancel() end
        self.status = "Position sharing is off"
        return
    end
    if not self.runtime:isOnline() then self.runtime:message("Connect to Wi-Fi to enable position sharing.", 4); return end
    if not self.api.beginOperation("position") then self.runtime:message("A Zotero operation is already running.", 3); return end
    local key = self.api.getAPIKey() or ""
    self.cancel = self.runtime:background(function() return Remote.authorize(self.api, key) end, function(result)
        self.cancel = nil; self.api.endOperation()
        if key ~= self.api.getAPIKey() then return end
        if result.error then self.status = result.error; self.runtime:message(result.error, 5); return end
        self.api.settings:saveSetting("progress_authorization", { owner = result.owner, key_hash = Identity.keyHash(key) })
        self.api.settings:saveSetting("share_reading_position", true)
        self.api.settings:delSetting("progress_retry")
        self.api.saveModifiedItems()
        self.paused, self.next_try = nil, 0
        if self.reader and self.origin then self:attach(self.reader, self.origin, true) end
        self:sync(true)
    end)
end

--- Capture enrollment evidence before ReaderUI writes default progress.
---@param key string
---@param path string
---@return table
function Progress:prepare(key, path)
    local context = { key = key, path = path, library = self.api.getLocalLibraryPrefix() }
    if not self:enabled() then return context end
    context.existing = self.runtime:readProgress(path)
    return context
end

---@param reader table
---@param context table|nil
---@param already_open boolean|nil
function Progress:attach(reader, context, already_open)
    self.reader, self.origin, self.session = reader, context, nil
    if not context then return end
    reader.zotero_progress_rebind = function(reopened) self:safe("attach", reopened, context, true) end
    if not self:enabled() then return end
    if context.library ~= self.api.getLocalLibraryPrefix() then self.status = "Reading account changed"; return end
    local identity, err = Identity.capture(self.api, context.key, context.path)
    if not identity then self.status = err; return end
    local codec, codec_error = Codec.new(reader, identity)
    if not codec then self.status = codec_error; return end
    self.session = { identity = identity, codec = codec, revision = 0 }
    local record = self.store:get(identity)
    if record and record.identity.md5 ~= identity.md5 then
        self.session = nil
        self.status = "Attachment contents changed since enrollment; sharing is paused"
        return
    end
    if not record then
        local native = codec:capture()
        local value, reason = codec:encode(native)
        record = { identity = identity, generation = 1, native = native, value = value, reason = reason,
            pending = context.existing ~= nil or already_open == true, status = reason and "unavailable" or "pending" }
        self.store:put(record)
    end
    self.status = record.reason or record.sync_error or record.status
    self.runtime:later(0.1, function() self:safe("sync", false) end)
end

---@return boolean
function Progress:active()
    local session = self.session
    return self:enabled() and session and self.reader and self.reader.document
        and self.reader.document.file == session.identity.path
        and session.identity.library == self.api.getLocalLibraryPrefix()
        and session.identity.key_hash == Identity.keyHash(self.api.getAPIKey() or "")
end

--- Persist the latest native point even if it cannot be converted yet.
function Progress:checkpoint()
    if not self:active() or self.applying then return end
    local session = self.session
    local md5, err = Identity.checksum(session.identity.path)
    if md5 ~= session.identity.md5 then
        self.status = err or "Attachment changed; sharing is paused"
        self.store:capture(session.identity, session.codec:capture(), nil, self.status)
        return
    end
    local native = session.codec:capture()
    local value, reason = session.codec:encode(native)
    local record = self.store:get(session.identity)
    if record and record.identity.path == session.identity.path and value ~= nil
        and value == record.value and not reason and not record.reason then
        record.native = native; self.store:put(record)
    else record = self.store:capture(session.identity, native, value, reason) end
    self.status = record.reason or record.sync_error or record.status
end

--- Coalesce page/scroll notifications; a response cannot jump over newer navigation.
function Progress:changed()
    if not self:active() or self.applying then return end
    self.session.revision = self.session.revision + 1
    if self.save_task then self.runtime:unschedule(self.save_task) end
    self.save_task = function() self:safe("checkpoint") end
    self.runtime:later(2, self.save_task)
    if self.push_task then self.runtime:unschedule(self.push_task) end
    self.push_task = function() self:safe("sync", false) end
    self.runtime:later(math.max(10, self.last_push + 60 - self.runtime:now()), self.push_task)
end

---@param identity table
---@return boolean
function Progress:matchesAccount(identity)
    local auth = self.api.settings:readSetting("progress_authorization")
    return self:enabled() and self:credentialsMatch() and auth.owner == identity.owner
        and identity.library == self.api.getLocalLibraryPrefix()
end

---@return table|nil
function Progress:snapshot()
    if self:active() then
        local current = self.store:get(self.session.identity)
        if current and current.value ~= nil and not current.reason then return current end
    end
    for _, record in pairs(self.store:load().records) do
        if record.pending and record.value ~= nil and not record.reason and self:matchesAccount(record.identity) then return record end
    end
end

---@param snapshot table
---@param result table
---@param session table|nil
---@param revision integer|nil
function Progress:accept(snapshot, result, session, revision)
    if not self:matchesAccount(snapshot.identity) then return end
    if result.error then self:rememberFailure(snapshot, result); return end
    if result.pushed then
        self:checkpoint()
        self.store:ack(snapshot, result)
        self.status = (self.store:get(snapshot.identity) or {}).status
        return
    end
    if session ~= self.session or not self:active() or revision ~= session.revision then self:checkpoint(); return end
    if Identity.checksum(snapshot.identity.path, true) ~= snapshot.identity.md5 then
        self.status = "Attachment changed while retrieving position"; return
    end
    if session.codec:capture() ~= snapshot.native then self:checkpoint(); return end
    if result.value == nil then
        local record = self.store:get(snapshot.identity)
        record.pending = true; self.store:put(record)
        return
    end
    self:importPosition(snapshot, result, session)
end

---@param snapshot table
---@param result table
function Progress:rememberFailure(snapshot, result)
    self.status = result.error
    local record = self.store:get(snapshot.identity)
    if record then record.sync_error = result.error; self.store:put(record) end
    self.next_try = self.runtime:now() + (result.delay or 60)
    self.paused = result.paused and Identity.keyHash(self.api.getAPIKey()) or nil
    self.api.settings:saveSetting("progress_retry", { key_hash = Identity.keyHash(self.api.getAPIKey()),
        at = self.next_try, paused = self.paused, reason = result.error })
    self.api.saveModifiedItems()
end

---@param snapshot table
---@param result table
---@param session table
function Progress:importPosition(snapshot, result, session)
    local native, err = session.codec:decode(result.value)
    if not native then self:rememberFailure(snapshot, { error = err }); return end
    local encoded, encode_error = session.codec:encode(native)
    if encoded == nil then self:rememberFailure(snapshot, { error = encode_error }); return end
    if encoded == snapshot.value then self.store:ack(snapshot, result); self.status = "shared"; return end
    self.applying = true
    local ok, apply_error = pcall(session.codec.apply, session.codec, native)
    self.applying = false
    if not ok then self.status = tostring(apply_error); return end
    local record = self.store:get(snapshot.identity)
    record.native, record.value = session.codec:capture(), encoded
    self.store:put(record)
    self.store:ack(record, result)
    self.reader:saveSettings()
    self.status = "shared"
end

--- Exchange one record, keeping all network I/O in a cancellable child process.
---@param manual boolean|nil
function Progress:sync(manual)
    if not self:enabled() then return end
    self:checkpoint()
    if not self:credentialsMatch() then self.status = "Check position-sharing permissions in Settings"; return end
    if not self.runtime:isOnline() then self.status = "pending (offline)"; return end
    if self.paused == Identity.keyHash(self.api.getAPIKey()) then
        if manual then self.runtime:message("Position access is paused. Disable and re-enable sharing to check permissions.", 5) end
        return
    end
    if self.runtime:now() < self.next_try or not self.api.beginOperation("position") then return end
    local snapshot = self:snapshot()
    if not snapshot or snapshot.reason or snapshot.value == nil then
        self.api.endOperation()
        if manual then self.runtime:message(self.status or "Open a verified Zotero attachment first.", 4) end
        return
    end
    local md5 = Identity.checksum(snapshot.identity.path, true)
    if md5 ~= snapshot.identity.md5 then
        self.api.endOperation(); self.status = "Queued document has changed"
        snapshot.reason = self.status; self.store:put(snapshot); self:drainLater(snapshot.identity); return
    end
    self:startExchange(snapshot, manual)
end

---@param snapshot table
---@param manual boolean|nil
---@param retried boolean|nil
function Progress:startExchange(snapshot, manual, retried)
    local key, session = self.api.getAPIKey(), self.session
    local revision = session and session.revision
    self.last_push = self.runtime:now()
    self.cancel = self.runtime:background(function() return Remote.exchange(self.api, key, snapshot) end, function(result)
        self.cancel = nil; self.api.endOperation()
        if key ~= self.api.getAPIKey() then return end
        local ok, err = pcall(self.finishExchange, self, snapshot, result, session, revision, manual, retried)
        if not ok then self.status = "Could not save shared position: " .. tostring(err) end
    end)
end

---@param snapshot table
---@param result table
---@param session table|nil
---@param revision integer|nil
---@param manual boolean|nil
---@param retried boolean|nil
function Progress:finishExchange(snapshot, result, session, revision, manual, retried)
    if result.conflict and not retried then self:retryConflict(snapshot, manual); return end
    if result.conflict then result = { error = "Position changed twice; local progress remains pending", delay = 60 } end
    self:accept(snapshot, result, session, revision)
    if manual then self.runtime:message(self:statusText(), 4) end
    if not result.error then self:drainLater(snapshot.identity) end
end

---@param snapshot table
---@param manual boolean|nil
function Progress:retryConflict(snapshot, manual)
    self:checkpoint()
    if not self:matchesAccount(snapshot.identity) or not self.runtime:isOnline() then return end
    local latest = self.store:get(snapshot.identity)
    if not latest or latest.reason or latest.value == nil then return end
    if Identity.checksum(latest.identity.path, true) ~= latest.identity.md5 then return end
    latest.pending = true; self.store:put(latest)
    if self.api.beginOperation("position") then self:startExchange(latest, manual, true) end
end

---@param previous table
function Progress:drainLater(previous)
    for _, record in pairs(self.store:load().records) do
        if record.pending and record.value ~= nil and not record.reason and self:matchesAccount(record.identity)
            and Store.key(record.identity) ~= Store.key(previous) then
            -- A queued document must not replace the active reader during a pull.
            self.runtime:later(0.2, function() self:safe("drainRecord", record) end)
            return
        end
    end
end

---@param record table
function Progress:drainRecord(record)
    if self.runtime:now() < self.next_try or self.paused == Identity.keyHash(self.api.getAPIKey() or "") then return end
    if not self:matchesAccount(record.identity) or not self.runtime:isOnline() or self.api.operation then return end
    record = self.store:get(record.identity)
    if not record or not record.pending or record.reason or record.value == nil then return end
    if Identity.checksum(record.identity.path, true) ~= record.identity.md5 then return end
    self.api.beginOperation("position")
    self:startExchange(record, false)
end

--- Checkpoint before the document disappears; closing never waits for HTTP.
---@param reader table
function Progress:close(reader)
    if reader ~= self.reader then return end
    self:checkpoint()
    if self.save_task then self.runtime:unschedule(self.save_task) end
    if self.push_task then self.runtime:unschedule(self.push_task) end
    self.reader, self.session, self.origin = nil, nil, nil
    self.runtime:later(0.1, function() self:safe("sync", false) end)
end

--- Persist before suspend and cancel outstanding requests. Example: progress:suspend().
function Progress:suspend()
    self:checkpoint()
    if self.cancel then self.cancel() end
end

--- Human-readable state without credentials or internal locators.
---@return string
function Progress:statusText()
    if not self:enabled() then return "Position sharing is off" end
    return "Reading position: " .. (self.status or "pending")
end

return Progress
