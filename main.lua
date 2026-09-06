local Blitbuffer = require("ffi/blitbuffer")
local Dispatcher = require("dispatcher")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local DataStorage = require("datastorage")
local Browser = require("zoterobrowser")
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
    self.browser = Browser:new{
        api = self.api, runtime = self.runtime, items_per_page = self:getItemsPerPage(),
        close_callback = function() self.runtime:close(self.zotero_dialog) end,
    }
    self.zotero_dialog = FrameContainer:new{
        padding = 0, bordersize = 0, background = Blitbuffer.COLOR_WHITE, self.browser,
    }
    self.browser.show_parent = self.zotero_dialog
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
    self:startSync(false, true)
end

--- Synchronize explicitly, optionally rewinding the delta. Example: plugin:onZoteroSyncAction(true).
---@param reset boolean|nil
function Plugin:onZoteroSyncAction(reset)
    if not self:checkInitialized() then return end
    self:startSync(reset == true, false)
end

---@param reset boolean
---@param automatic boolean
function Plugin:startSync(reset, automatic)
    if not self.api.beginOperation("sync") then
        if not automatic then self.runtime:message(_("A Zotero operation is already running."), 3) end
        return
    end
    self.runtime:schedule(function() self:performSync(reset, automatic) end)
end

---@param reset boolean
---@param automatic boolean
function Plugin:performSync(reset, automatic)
    local progress = self.runtime:message(_("Synchronizing Zotero library. This might take some time."))
    self.runtime:repaint()
    local ok, err = pcall(function()
        if reset then self.api.resetSyncState() end
        return self.api.syncAllItems()
    end)
    self.runtime:close(progress)
    self.api.endOperation()
    self.browser:refresh()
    if not ok or err then self.runtime:message(tostring(err), 5) return end
    if not automatic then self.runtime:message(_("Success."), 3) end
end

return Plugin
