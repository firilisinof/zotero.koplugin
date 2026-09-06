local _ = require("gettext")
local Menus = {}

---@param plugin table
---@param title string
---@param callback function
---@return table
local function entry(plugin, title, callback)
    return { text = title, callback = callback }
end

---@param plugin table
---@param title string
---@param getter function
---@param setter function
---@return table
local function toggle(plugin, title, getter, setter)
    return { text = title, checked_func = getter, callback = function()
        setter(not getter())
        plugin.api.saveModifiedItems()
    end }
end

---@param plugin table
---@return table[]
local function webdavEntries(plugin)
    local api = plugin.api
    local entries = {
        { text = _("Enable WebDAV storage"), checked_func = api.getWebDAVEnabled, callback = api.toggleWebDAVEnabled },
        entry(plugin, _("Configure WebDAV account"), function() plugin:setWebdavAccount() end),
        entry(plugin, _("Check WebDAV connection"), function()
            local err = api.checkWebDAV()
            plugin.runtime:message(err and (_("WebDAV could not connect: ") .. err) or _("Success, WebDAV works!"), 3)
        end),
    }
    for _, item in ipairs(entries) do
        item.enabled_func = function() return api.getLibraryType() == "user" end
    end
    return entries
end

---@param plugin table
---@return table[]
local function settingsEntries(plugin)
    local api = plugin.api
    local entries = {
        entry(plugin, _("Configure Zotero account"), function() plugin:setAccount() end),
        entry(plugin, _("Filter by tag"), function() plugin:setFilterTag() end),
        toggle(plugin, _("Sync on startup"), api.getSyncOnStartup, api.setSyncOnStartup),
        toggle(plugin, _("Sync on browse when older than 24 hours"), api.getSyncOnOpen, api.setSyncOnOpen),
        entry(plugin, _("Items per page"), function() plugin:setItemsPerPage() end),
    }
    for _, item in ipairs(webdavEntries(plugin)) do table.insert(entries, item) end
    return entries
end

--- Build the menu with live settings and sync status. Example: plugin:addToMainMenu(menu_items).
---@param menu_items table
function Menus:addToMainMenu(menu_items)
    menu_items.zotero = { text = _("Zotero"), sorting_hint = "search", sub_item_table = {
        entry(self, _("Browse"), function() self:onZoteroOpenAction() end),
        entry(self, _("Synchronize"), function() self:onZoteroSyncAction() end),
        { text_func = function() return self:lastSyncText() end, enabled = false },
        { text = _("Maintenance"), sub_item_table = {
            entry(self, _("Resync entire collection"), function() self:onZoteroSyncAction(true) end),
        } },
        { text = _("Settings"), sub_item_table = settingsEntries(self) },
    } }
end

--- Format the last successful completion in local time. Example: plugin:lastSyncText().
---@return string
function Menus:lastSyncText()
    local last = tonumber(self.api.getLastSync()) or 0
    if last == 0 then return _("Never synced") end
    return _("Last synced: ") .. os.date("%Y-%m-%d %H:%M", last)
end

return Menus
