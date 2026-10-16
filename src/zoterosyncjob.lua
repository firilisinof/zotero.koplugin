-- Library sync off the UI thread. A non-modal child fetches deltas into staged
-- files and returns only versions and changed flags. The parent alone commits.
local _ = require("gettext")
local SyncJob = {}
SyncJob.__index = SyncJob

-- Each page request carries its own socket timeout, and a first sync of a large
-- library takes many pages. This backstop only keeps a wedged child, such as one
-- stuck resolving DNS, from holding the operation lock forever.
local TIME_LIMIT = 30 * 60

---@class ZoteroSyncOwner
---@field dir string
---@field prefix string|nil
---@field key string|nil

---@class ZoteroSyncRun
---@field automatic boolean
---@field owner ZoteroSyncOwner
---@field stage table<string, string>
---@field progress table|nil
---@field cancel function|nil
---@field reason string|nil Why the parent aborted the child

--- Create the sync job shared by file-manager and reader plugin instances. Example: SyncJob.new(api, runtime).
---@param api ZoteroAPI
---@param runtime table
---@return table
function SyncJob.new(api, runtime)
    -- on_commit arrives later from the newest plugin instance, through Plugin:attachSyncJob.
    return setmetatable({ api = api, runtime = runtime }, SyncJob)
end

---@return ZoteroSyncOwner
function SyncJob:owner()
    return { dir = self.api.zotero_dir, prefix = self.api.getLibraryPrefix(), key = self.api.getAPIKey() }
end

---@param first ZoteroSyncOwner
---@param second ZoteroSyncOwner
---@return boolean
local function sameOwner(first, second)
    return first.dir == second.dir and first.prefix == second.prefix and first.key == second.key
end

--- Start one background sync unless another operation holds the lock. Example: job:start(false, true).
---@param rebuild boolean Fetch from version 0, replacing the cache only after success
---@param automatic boolean Run silently without a progress message
---@return boolean started
function SyncJob:start(rebuild, automatic)
    if not self.api.beginOperation("sync") then
        if not automatic then self.runtime:message(_("A Zotero operation is already running."), 3) end
        return false
    end
    local run = { automatic = automatic, owner = self:owner(), stage = self.api.getSyncStage() }
    self.run = run
    local ok, err = pcall(self.launch, self, run, rebuild)
    if not ok then self:complete(run, { error = tostring(err) }) end
    return true
end

---@param run ZoteroSyncRun
---@param rebuild boolean
function SyncJob:launch(run, rebuild)
    -- A child killed mid-write can leave files no later result would overwrite.
    self.api.discardSyncStage(run.stage)
    if not run.automatic then
        run.progress = self.runtime:cancellable(_("Synchronizing Zotero library (tap to cancel)"),
            function() self:cancel("cancelled") end)
    end
    local api, stage = self.api, run.stage
    run.cancel = self.runtime:background(function()
        local ok, result = pcall(api.stageLibrary, rebuild, stage)
        return ok and result or { error = tostring(result) }
    end, function(result) self:complete(run, result) end, TIME_LIMIT)
end

--- Kill the running child, keeping the current cache. Example: job:cancel("suspend").
---@param reason string
function SyncJob:cancel(reason)
    local run = self.run
    if not run or not run.cancel then return end
    run.reason = reason
    run.cancel()
end

---@param run ZoteroSyncRun
---@param result ZoteroSyncResult
---@return boolean committed, string|nil error
function SyncJob:settle(run, result)
    if run.reason then return false, nil end
    if result.error then return false, tostring(result.error) end
    if not sameOwner(run.owner, self:owner()) then
        return false, _("The Zotero account changed during sync. The library was not updated.")
    end
    local err = self.api.commitLibrary(result, run.stage)
    return err == nil, err
end

---@param run ZoteroSyncRun
---@param result ZoteroSyncResult
function SyncJob:complete(run, result)
    -- The worker may call back before launch returns, or after a cancel already settled.
    if self.run ~= run then return end
    self.run = nil
    local ok, committed, err = pcall(self.settle, self, run, result)
    if not ok then committed, err = false, tostring(committed) end
    self.api.discardSyncStage(run.stage)
    self.runtime:close(run.progress)
    self.api.endOperation()
    self:announce(run, committed, err)
end

---@param run ZoteroSyncRun
---@param committed boolean
---@param err string|nil
function SyncJob:announce(run, committed, err)
    if err then self.runtime:message(err, 5) return end
    if not committed then
        if not run.automatic then self.runtime:message(_("Zotero sync cancelled. The library was not changed."), 3) end
        return
    end
    -- Refresh after the lock is free, so follow-up position and highlight syncs can start.
    local refreshed, refresh_error = pcall(self.on_commit or function() end)
    if not refreshed then self.runtime:message(tostring(refresh_error), 5) return end
    if not run.automatic then self.runtime:message(_("Success."), 3) end
end

return SyncJob
