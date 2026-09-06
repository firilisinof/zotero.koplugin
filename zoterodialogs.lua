local _ = require("gettext")
local Dialogs = {}

---@param plugin table
---@param dialog table
---@param save function
---@return table
local function saveButtons(plugin, dialog, save)
    return { {
        { text = _("Cancel"), id = "close", callback = function() plugin.runtime:close(dialog()) end },
        { text = _("Update"), is_enter_default = true, callback = save },
    } }
end

---@param plugin table
---@param title string
---@param fields table[]
---@param save fun(values: string[]): string|nil
local function editFields(plugin, title, fields, save)
    local dialog
    dialog = plugin.runtime.MultiInputDialog:new{
        title = title, fields = fields,
        buttons = saveButtons(plugin, function() return dialog end, function()
            local err = save(dialog:getFields())
            if err then plugin.runtime:message(err, 5) return end
            plugin.runtime:close(dialog)
        end),
    }
    plugin.runtime:show(dialog)
    dialog:onShowKeyboard()
end

---@param plugin table
---@param library_type string
local function editAccount(plugin, library_type)
    local api = plugin.api
    local group = library_type == "group"
    local title = group and _("Group library account") or _("Personal library account")
    editFields(plugin, title, {
        { text = group and (api.getGroupID() or "") or (api.getUserID() or ""), hint = group and _("Group ID") or _("User ID"), input_type = "number" },
        { text = api.getAPIKey() or "", hint = _("API Key"), text_type = "password" },
    }, function(values)
        local previous = api.getLibraryPrefix()
        local err = api.setAccount(library_type, values[1], values[2])
        if err then return err end
        if previous ~= api.getLibraryPrefix() and plugin.browser then plugin.browser:resetLibrary() end
    end)
end

--- Choose a library type before editing its credentials. Example: plugin:setAccount().
function Dialogs:setAccount()
    self.runtime:show(self.runtime.RadioButtonWidget:new{
        title_text = _("Zotero library"), ok_text = _("Next"),
        radio_buttons = {
            { { text = _("Personal library"), provider = "user", checked = self.api.getLibraryType() == "user" } },
            { { text = _("Group library"), provider = "group", checked = self.api.getLibraryType() == "group" } },
        },
        callback = function(radio) editAccount(self, radio.provider) end,
    })
end

--- Edit the personal WebDAV connection. Example: plugin:setWebdavAccount().
function Dialogs:setWebdavAccount()
    local api = self.api
    editFields(self, _("Edit WebDAV credentials"), {
        { text = api.getWebDAVUrl() or "", hint = _("URL") },
        { text = api.getWebDAVUser() or "", hint = _("Username") },
        { text = api.getWebDAVPassword() or "", hint = _("Password"), text_type = "password" },
    }, function(values)
        api.setWebDAVUrl(values[1])
        api.setWebDAVUser(values[2])
        api.setWebDAVPassword(values[3])
        api.saveModifiedItems()
    end)
end

---@param plugin table
---@param dialog table
---@param tag string
local function saveTag(plugin, dialog, tag)
    plugin.api.setFilterTag(tag)
    plugin.runtime:close(dialog)
    plugin.browser:refresh()
end

--- Set one exact tag, or clear filtering. Example: plugin:setFilterTag().
function Dialogs:setFilterTag()
    local dialog
    dialog = self.runtime.InputDialog:new{
        title = _("Filter by tag"), input = self.api.getFilterTag(),
        description = _("Match one tag exactly, including case. Clear to show every item."),
        buttons = { {
            { text = _("Cancel"), id = "close", callback = function() self.runtime:close(dialog) end },
            { text = _("Clear"), callback = function() saveTag(self, dialog, "") end },
            { text = _("Update"), is_enter_default = true,
                callback = function() saveTag(self, dialog, dialog:getInputText()) end },
        } },
    }
    self.runtime:show(dialog)
    dialog:onShowKeyboard()
end

--- Configure pagination using KOReader's existing control. Example: plugin:setItemsPerPage().
function Dialogs:setItemsPerPage()
    self.runtime:show(self.runtime.SpinWidget:new{
        title_text = _("Set items per page"), value = self:getItemsPerPage(), value_min = 1, value_max = 1000,
        callback = function(dialog)
            self.api.getSettings():saveSetting("items_per_page", dialog.value)
            self.api.saveModifiedItems()
            self.runtime:message(_("This change requires a restart of KOReader to take effect."), 3)
        end,
    })
end

--- Return configured pagination. Example: plugin:getItemsPerPage().
---@return integer
function Dialogs:getItemsPerPage()
    return self.api.getSettings():readSetting("items_per_page", 14)
end

return Dialogs
