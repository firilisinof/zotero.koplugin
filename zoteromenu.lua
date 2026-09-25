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
    table.insert(entries, { text = _("Share reading position"),
        checked_func = function() return plugin.api.progress and plugin.api.progress:enabled() or false end,
        callback = function() plugin.api.progress:safe("toggle") end })
    table.insert(entries, { text = _("Sync highlights"),
        checked_func = function() return plugin.api.highlights and plugin.api.highlights:enabled() or false end,
        callback = function() plugin.api.highlights:safe("toggle") end })
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
        entry(self, _("Sync position now"), function() self.api.progress:safe("sync", true) end),
        { text_func = function() return self.api.progress and self.api.progress:statusText() or _("Position sharing is off") end,
            enabled = false },
        entry(self, _("Sync highlights now"), function() self.api.highlights:safe("sync", true) end),
        entry(self, _("Resolve highlight conflicts"), function() self:showHighlightConflicts() end),
        { text_func = function() return self.api.highlights and self.api.highlights:statusText() or _("Highlight sync is off") end,
            enabled = false },
    } }
end

---@param value table|boolean
---@return string
local function describeHighlight(value)
    if value == false then return _("Deleted") end
    return value.text .. "\n" .. value.comment .. "\n" .. value.color
end

--- Present both saved values for review. Example: plugin:showHighlightChoice(id, conflict).
---@param id string
---@param conflict table
function Menus:showHighlightChoice(id, conflict)
    local dialog
    ---@param side string
    local function choose(side)
        self.runtime:close(dialog); self.api.highlights:safe("resolve", id, side)
    end
    dialog = self.runtime.ButtonDialog:new{ title = _("Highlight conflict") .. "\n" ..
        _("KOReader:") .. "\n" .. describeHighlight(conflict.local_value) .. "\n\n" .. _("Zotero:") .. "\n" .. describeHighlight(conflict.remote),
        buttons = {
            { { text = _("Keep KOReader"), callback = function() choose("local") end },
              { text = _("Keep Zotero"), callback = function() choose("remote") end } },
            { { text = _("Later"), callback = function() self.runtime:close(dialog) end } },
        } }
    self.runtime:show(dialog)
end

--- Review each conflict before choosing either version. Example: plugin:showHighlightConflicts().
function Menus:showHighlightConflicts()
    local highlights = self.api.highlights
    if not highlights or not highlights:active() then self.runtime:message(_("Open a shared document first."), 3); return end
    local record = highlights.store:get(highlights.identity)
    for id, annotation in pairs(record.entries) do
        if annotation.conflict then self:showHighlightChoice(id, annotation.conflict); return end
    end
    self.runtime:message(_("No highlight conflicts."), 3)
end

--- Format the last successful completion in local time. Example: plugin:lastSyncText().
---@return string
function Menus:lastSyncText()
    local last = tonumber(self.api.getLastSync()) or 0
    if last == 0 then return _("Never synced") end
    return _("Last synced: ") .. os.date("%Y-%m-%d %H:%M", last)
end

return Menus
