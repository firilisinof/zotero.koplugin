local Blitbuffer = require("ffi/blitbuffer")
local Dispatcher = require("dispatcher")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local DataStorage = require("datastorage")
local Browser = require("zoterobrowser")
local SyncJob = require("zoterosyncjob")
local _ = require("gettext")

local Plugin = WidgetContainer:new{
    name = "zotero", is_doc_only = false,
    api = require("zoteroapi"), runtime = require("zoteroui"),
}

for name, method in pairs(require("zoterodialogs")) do Plugin[name] = method end
for name, method in pairs(require("zoteromenu")) do Plugin[name] = method end

--- Register the existing dispatcher actions. Example: plugin:onDispatcherRegisterActions().
function Plugin:onDispatcherRegisterActions()
    Dispatcher:registerAction("zotero_open_action", {
        category = "none", event = "ZoteroOpenAction", title = _("Zotero Open"), general = true,
    })
    Dispatcher:registerAction("zotero_sync_action", {
        category = "none", event = "ZoteroSyncAction", title = _("Zotero Sync"), general = true,
    })
end

--- Mount the plugin, containing initialization errors. Example: plugin:init().
function Plugin:init()
    self.initialized = false
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    -- pcall rather than xpcall: a method used as an error handler would receive
    -- the error string in place of self and fail while reporting the first error.
    local ok, err = pcall(self.initAPIAndBrowser, self)
    if not ok then
        print(self.api.util.encode({ event = "zotero_init_failed", error = tostring(err) }))
        return
    end
    self.initialized = true
    if self.api.settings then self:maybeStartupSync() end
end

--- Guard actions after a failed initialization. Example: plugin:checkInitialized().
---@return boolean
function Plugin:checkInitialized()
    if self.initialized and self.browser then return true end
    self.runtime:message(_("Zotero could not be initialized. Check the KOReader log for details."), 3)
    return false
end

--- Wire the browser to the shared API and KOReader runtime. Example: plugin:initAPIAndBrowser().
function Plugin:initAPIAndBrowser()
    self.zotero_dir_path = DataStorage:getDataDir() .. "/zotero"
    self.api.util.mkdir(self.zotero_dir_path)
    if self.api.zotero_dir ~= self.zotero_dir_path then self.api.init(self.zotero_dir_path) end
    self.api.progress = self.api.progress or require("zoteroprogress").new(self.api, self.runtime)
    self.progress = self.api.progress
    self.api.highlights = self.api.highlights or require("zoterohighlights").new(self.api, self.runtime)
    self.highlights = self.api.highlights
    self.browser = Browser:new{
        api = self.api, runtime = self.runtime, items_per_page = self:getItemsPerPage(),
        close_callback = function() self.runtime:close(self.zotero_dialog) end,
    }
    self.zotero_dialog = FrameContainer:new{
        padding = 0, bordersize = 0, background = Blitbuffer.COLOR_WHITE, self.browser,
    }
    self.browser.show_parent = self.zotero_dialog
    self.api.sync_job = self.api.sync_job or SyncJob.new(self.api, self.runtime)
    self:attachSyncJob(self.api.sync_job)
end

--- Share one sync job across plugin instances. A sync outlives the instance that started it,
--- so the newest instance, whose browser can be visible, handles its commit. Example: plugin:attachSyncJob(job).
---@param job table
function Plugin:attachSyncJob(job)
    self.sync_job = job
    job.on_commit = function() self:afterSyncCommit() end
end

--- Browse cached metadata immediately. Example: plugin:onZoteroOpenAction().
function Plugin:onZoteroOpenAction()
    if not self:checkInitialized() then return end
    self.browser:restoreLibrary()
    self.runtime:show(self.zotero_dialog)
    self:maybeAutoSync("open")
end

--- Attempt startup sync at most once per process. Example: plugin:maybeStartupSync().
function Plugin:maybeStartupSync()
    if self.api.startup_attempted then return end
    self.api.startup_attempted = true
    self:maybeAutoSync("startup")
end

--- Run enabled automatic triggers only with an existing connection. Example: plugin:maybeAutoSync("open").
---@param trigger string
function Plugin:maybeAutoSync(trigger)
    if not self.api.shouldAutoSync(trigger, self.runtime:now()) then return end
    if not self.runtime:isOnline() then return end
    self.sync_job:start(false, true)
end

--- Synchronize explicitly, optionally refetching everything. Example: plugin:onZoteroSyncAction(true).
---@param reset boolean|nil Fetch from version 0, keeping the current cache until that succeeds
function Plugin:onZoteroSyncAction(reset)
    if not self:checkInitialized() then return end
    self.sync_job:start(reset == true, false)
end

--- Show committed metadata and hand off to position and highlight syncs. Example: plugin:afterSyncCommit().
function Plugin:afterSyncCommit()
    self.browser:refresh()
    if self.progress then self.progress:safe("sync", false) end
    if self.highlights then self.highlights:safe("sync", false) end
end

--- Forward native lifecycle events only for the bound Zotero reader.
function Plugin:onPageUpdate()
    if self.progress and self.progress.reader == self.ui then self.progress:safe("changed") end
end
Plugin.onPosUpdate = Plugin.onPageUpdate

function Plugin:onSaveSettings()
    if self.progress and self.progress.reader == self.ui then self.progress:safe("checkpoint") end
    if self.highlights and self.highlights.reader == self.ui then self.highlights:safe("checkpoint") end
end

function Plugin:onAnnotationsModified()
    if self.highlights and self.highlights.reader == self.ui then self.highlights:safe("changed") end
end

function Plugin:onCloseDocument()
    if self.progress then self.progress:safe("close", self.ui) end
    if self.highlights then self.highlights:safe("close", self.ui) end
end

function Plugin:onSuspend()
    if self.sync_job then self.sync_job:cancel("suspend") end
    if self.progress then self.progress:safe("suspend") end
    if self.highlights then self.highlights:safe("suspend") end
end
Plugin.onNetworkDisconnecting = Plugin.onSuspend

function Plugin:onResume()
    if self.progress then self.runtime:later(0.5, function() self.progress:safe("sync", false) end) end
    if self.highlights then self.runtime:later(1, function() self.highlights:safe("sync", false) end) end
end
Plugin.onNetworkConnected = Plugin.onResume

return Plugin
