local Menu = require("ui/widget/menu")
local _ = require("gettext")

local Browser = Menu:extend{
    no_title = false, is_borderless = true, is_popout = false,
    title_bar_left_icon = "appbar.search", covers_full_screen = true,
    return_arrow_propagation = false,
}

--- Initialize navigation once per browser. Example: browser:init().
function Browser:init()
    Menu.init(self)
    self.paths = {}
    self.current_view = { kind = "collection" }
end

---@param view table
function Browser:navigate(view)
    table.insert(self.paths, self.current_view)
    self.current_view = view
    self:refresh()
end

--- Return to the actual previous collection or query. Example: browser:onReturn().
---@return boolean
function Browser:onReturn()
    self.current_view = table.remove(self.paths) or { kind = "collection" }
    self:refresh()
    return true
end

--- Offer a search without changing history on cancel. Example: browser:onLeftButtonTap().
function Browser:onLeftButtonTap()
    local dialog
    dialog = self.runtime.InputDialog:new{
        title = _("Search Zotero titles"), input = "",
        description = _("Search title, first author and DOI within the active tag filter."),
        buttons = { {
            { text = _("Cancel"), id = "close", callback = function() self.runtime:close(dialog) end },
            { text = _("Search"), is_enter_default = true, callback = function()
                self.runtime:close(dialog)
                self:navigate{ kind = "search", query = dialog:getInputText() }
            end },
        } },
    }
    self.runtime:show(dialog)
    dialog:onShowKeyboard()
end

--- Refresh the active view after sync, filtering or download. Example: browser:refresh().
function Browser:refresh()
    local view = self.current_view or { kind = "collection" }
    if view.kind == "search" then self:displaySearchResults(view.query) return end
    self:displayCollection(view.key)
end

--- Reset navigation when the selected library changes. Example: browser:resetLibrary().
function Browser:resetLibrary()
    self.paths = {}
    self.current_view = { kind = "collection" }
    self:refresh()
end

--- Display cached search results. Example: browser:displaySearchResults("attention").
---@param query string
function Browser:displaySearchResults(query)
    self.current_view = { kind = "search", query = query }
    self:setItems(self.api.displaySearchResults(query), _("No Results"))
end

--- Display direct collection members. Example: browser:displayCollection("COLLAAA1").
---@param key string|nil
function Browser:displayCollection(key)
    self.current_view = { kind = "collection", key = key }
    local items = self.api.displayCollection(key)
    if key == nil then table.insert(items, 1, { text = _("All Items"), wildcard_collection = true }) end
    self:setItems(items, _("No Items"))
end

---@param items ZoteroRow[]
---@param empty_text string
function Browser:setItems(items, empty_text)
    if #items == 0 then table.insert(items, { text = empty_text, is_label = true }) end
    for _index, item in ipairs(items) do
        if item.downloaded then item.text = _("[Downloaded]") .. " " .. item.text end
    end
    self:switchItemTable(_("Zotero"), items)
end

--- Handle row selection. Example: browser:onMenuSelect(row).
---@param item ZoteroRow
function Browser:onMenuSelect(item)
    if item.collection then self:navigate{ kind = "collection", key = item.key } return end
    if item.wildcard_collection then self:navigate{ kind = "search", query = "" } return end
    if item.is_label then return end
    self:startDownload(function() return self:downloadItem(item) end)
end

--- Offer row-specific actions. Example: browser:onMenuHold(row).
---@param item ZoteroRow
---@return boolean
function Browser:onMenuHold(item)
    if not item.key or item.is_label then return true end
    local dialog
    local action = item.collection and _("Download collection") or _("Show Zotero notes")
    dialog = self.runtime.ButtonDialog:new{ title = item.text, buttons = { {
        { text = action, callback = function()
            self.runtime:close(dialog)
            if item.collection then self:startDownload(function() self:downloadCollection(item.key) end)
            else self:showNotes(item.key) end
        end },
    } } }
    self.runtime:show(dialog)
    return true
end

--- Show cached child notes without network I/O. Example: browser:showNotes("ATTACH01").
---@param key string
function Browser:showNotes(key)
    local notes = self.api.getItemNotes(key)
    local text = {}
    for _, note in ipairs(notes) do table.insert(text, note.text) end
    self.runtime:show(self.runtime.TextViewer:new{
        title = _("Zotero notes"),
        text = #notes > 0 and table.concat(text, "\n\n----------\n\n") or _("No Zotero notes for this item."),
    })
end

---@param task function
function Browser:startDownload(task)
    if not self.api.beginOperation("download") then
        self.runtime:message(_("A Zotero operation is already running."), 3)
        return
    end
    self.runtime:wrap(function()
        local ok, path = pcall(task)
        self.runtime:close(self.download_dialog)
        self.download_dialog = nil
        self.api.endOperation()
        self:refresh()
        if not ok then self.runtime:message(tostring(path), 5) return end
        if path then self.close_callback() self.runtime:openReader(path) end
    end)
end

---@param text string
function Browser:showProgress(text)
    self.runtime:close(self.download_dialog)
    self.download_dialog = self.runtime:message(text)
    self.runtime:repaint()
end

---@param item ZoteroRow
function Browser:downloadItem(item)
    self:showProgress(_("Downloading file (tap to cancel)"))
    local completed, path, err = self.runtime:run(function()
        return self.api.downloadAndGetPath(item.key)
    end, self.download_dialog)
    self.runtime:close(self.download_dialog)
    self.download_dialog = nil
    if not completed then return end
    if not path then self.runtime:message(_("Could not open file. ") .. tostring(err), 5) return end
    return path
end

---@param summary ZoteroDownloadSummary
---@return string
local function summaryText(summary)
    return (_("Downloaded: %d\nAlready current: %d\nFailed: %d\nCancelled: %d"))
        :format(summary.downloaded, summary.skipped, summary.failed, summary.cancelled)
end

---@param key string
function Browser:downloadCollection(key)
    local summary = self.api.downloadCollection(key, function(progress, entry)
        local number = progress.downloaded + progress.skipped + progress.failed + 1
        self:showProgress((_("Downloading %d of %d (tap to cancel)\n%s")):format(number, progress.total, entry.text))
    end, function(task) return self.runtime:run(task, self.download_dialog) end)
    self.runtime:close(self.download_dialog)
    self.download_dialog = nil
    local lines = { summaryText(summary) }
    for _, err in ipairs(summary.errors) do table.insert(lines, err.text) end
    self.runtime:show(self.runtime.TextViewer:new{
        title = _("Collection download"), text = table.concat(lines, "\n\n"),
    })
end

return Browser
