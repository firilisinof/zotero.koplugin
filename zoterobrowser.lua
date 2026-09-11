local Menu = require("ui/widget/menu")
local Row = require("zoterorow")
local Size = require("ui/size")
local Header = require("zoteroheader")
local Screen = require("device").screen
local _ = require("gettext")

local Browser = Menu:extend{
    no_title = false, is_borderless = true, is_popout = false,
    covers_full_screen = true,
    return_arrow_propagation = false,
    single_line = true, linesize = Size.line.thin,
}

--- Treat the page preference as a maximum so metadata never overlaps. Example: browser:_recalculateDimen().
---@param no_recalculate_dimen boolean|nil
function Browser:_recalculateDimen(no_recalculate_dimen)
    local page = self.page
    Menu._recalculateDimen(self, no_recalculate_dimen)
    self.font_size = math.max(14, self.font_size)
    local info_size = math.max(10, math.min(self.font_size - 2, self.items_mandatory_font_size or math.floor(self.font_size * 0.8)))
    self.row_metrics = Row.metrics(self.font_size, info_size)
    -- Only shrink when even one complete row cannot fit, e.g. a short landscape screen.
    while self.row_metrics.min_height + self.linesize > self.available_height and self.font_size > 1 do
        self.font_size, info_size = self.font_size - 1, math.max(1, info_size - 1)
        self.row_metrics = Row.metrics(self.font_size, info_size)
    end
    local capacity = math.max(1, math.floor(self.available_height / (self.row_metrics.min_height + self.linesize)))
    self.perpage = math.min(self.perpage, capacity)
    self.item_dimen.h = math.floor(self.available_height / self.perpage)
    for _, entry in ipairs(self.item_table) do entry.shortcut_icon_width = self.row_metrics.title_line_height end
    self.page_num = self:getPageNumber(#self.item_table)
    self.page = math.min(page, self.page_num)
end

--- Keep native menu pagination and input while rendering separate fields. Example: browser:updateItems(1).
---@param select_number number|nil
---@param no_recalculate_dimen boolean|nil
function Browser:updateItems(select_number, no_recalculate_dimen)
    Menu.updateItems(self, select_number, no_recalculate_dimen)
    for _, item in ipairs(self.item_group) do Row.decorate(item, self.row_metrics) end
end

--- Initialize navigation once per browser. Example: browser:init().
function Browser:init()
    self.custom_title_bar = Header:new{ browser = self, width = self.width or Screen:getWidth() }
    Menu.init(self)
    self.paths = {}
    self.current_view = { kind = "home", page = 1 }
end

--- Remember each source page before entering another view. Example: browser:navigate{ kind = "device" }.
---@param view ZoteroBrowserView
function Browser:navigate(view)
    self:savePosition()
    table.insert(self.paths, self.current_view)
    self.current_view = view
    self:refresh()
    self:savePosition()
end

--- Return to the actual previous collection or query. Example: browser:onReturn().
---@return boolean
function Browser:onReturn()
    self.current_view = table.remove(self.paths) or { kind = "home" }
    self:refresh()
    self:savePosition()
    return true
end

--- Open Zotero home while retaining the source page for Back. Example: browser:onHome().
---@return boolean
function Browser:onHome()
    if self.current_view.kind ~= "home" then self:navigate{ kind = "home" } end
    return true
end

--- Offer a search without changing history on cancel. Example: browser:onLeftButtonTap().
function Browser:onLeftButtonTap()
    local on_device = self.current_view.kind == "device"
    local dialog
    dialog = self.runtime.InputDialog:new{
        title = on_device and _("Search on device") or _("Search Zotero titles"), input = "",
        description = _("Search title, first author and DOI within the active tag filter."),
        buttons = { {
            { text = _("Cancel"), id = "close", callback = function() self.runtime:close(dialog) end },
            { text = _("Search"), is_enter_default = true, callback = function()
                self.runtime:close(dialog)
                self:navigate{ kind = on_device and "device" or "search", query = dialog:getInputText() }
            end },
        } },
    }
    self.runtime:show(dialog)
    dialog:onShowKeyboard()
end

--- Refresh the active view after sync, filtering or download. Example: browser:refresh().
function Browser:refresh()
    local view = self.current_view or { kind = "home" }
    -- Account changes clear metadata. Keep the saved destination until its cache returns.
    self.waiting_for_cache = view.kind ~= "home"
        and next(self.api.getItems()) == nil and next(self.api.getCollections()) == nil
        and self.api.getLastSync() == 0
    while not self.waiting_for_cache and view.kind == "collection" and view.key
        and not self.api.getCollections()[view.key] do
        view = table.remove(self.paths) or { kind = "home" }
    end
    if view.kind == "home" then self:displayHome(view.page) return end
    if view.kind == "all" then self:displayAllItems(view.page) return end
    if view.kind == "search" then self:displaySearchResults(view.query, view.page) return end
    if view.kind == "device" then self:displayOnDevice(view.query, view.page) return end
    self:displayCollection(view.key, view.page)
end

--- Offer the everyday destinations without network access. Example: browser:displayHome().
---@param page integer|nil
function Browser:displayHome(page)
    self.current_view = { kind = "home", page = page or 1 }
    local recent = self.api.getContinueReading(self.api.getLocalLibraryPrefix() or "local")
    self:setItems({
        { text = _("Continue reading"), continue_reading = true, enabled = recent ~= nil,
            subtitle = recent and recent.title or _("No recent document") },
        { text = _("Collections"), destination = "collection" },
        { text = _("All items"), destination = "all" },
        { text = _("On device"), destination = "device" },
        { text = _("Search"), search = true },
    }, _("No Items"))
end

--- List all indexed attachments with an explicit location. Example: browser:displayAllItems().
---@param page integer|nil
function Browser:displayAllItems(page)
    self.current_view = { kind = "all", page = page or 1 }
    self:setItems(self.api.displaySearchResults(""), _("No Items"))
end

--- Reopen the last view for the selected library. Example: browser:restoreLibrary().
function Browser:restoreLibrary()
    local library = self.api.getLocalLibraryPrefix() or "local"
    -- File manager and reader own separate plugin instances. Load the latest saved view.
    local position = self.api.getBrowserPosition(library)
    self.current_view, self.paths = position.view, position.paths
    self.position_library = library
    self:refresh()
end

--- Persist the current page and back history without touching attachments. Example: browser:savePosition().
function Browser:savePosition()
    if not self.current_view or not self.position_library then return end
    if not self.waiting_for_cache then self.current_view.page = self.page or 1 end
    self.api.saveBrowserPosition(self.position_library, { view = self.current_view, paths = self.paths })
end

--- Save native page turns, including swipes and page jumps. Example: browser:onGotoPage(2).
---@param page integer
---@return boolean
function Browser:onGotoPage(page)
    Menu.onGotoPage(self, page)
    self:savePosition()
    return true
end

--- Save before the menu closes or returns to the file manager. Example: browser:onCloseAllMenus().
---@return boolean
function Browser:onCloseAllMenus()
    self:savePosition()
    return Menu.onCloseAllMenus(self)
end

--- Display cached search results. Example: browser:displaySearchResults("attention").
---@param query string
---@param page integer|nil
function Browser:displaySearchResults(query, page)
    self.current_view = { kind = "search", query = query, page = page or 1 }
    self:setItems(self.api.displaySearchResults(query), _("No Results"))
end

--- Browse local copies, including a search limited to this view. Example: browser:displayOnDevice("").
---@param query string|nil
---@param page integer|nil
function Browser:displayOnDevice(query, page)
    self.current_view = { kind = "device", query = query or "", page = page or 1 }
    self:setItems(self.api.displayOnDevice(query), _("No local files match the current filters."))
end

--- Display direct collection members. Example: browser:displayCollection("COLLAAA1").
---@param key string|nil
---@param page integer|nil
function Browser:displayCollection(key, page)
    self.current_view = { kind = "collection", key = key, page = page or 1 }
    local items = self.api.displayCollection(key)
    self:setItems(items, _("No Items"))
end

--- Name the active location, including literal search text. Example: browser:locationTitle().
---@return string
function Browser:locationTitle()
    local view = self.current_view
    if view.kind == "home" then return _("Zotero home") end
    if view.kind == "all" then return _("Zotero - All items") end
    if view.kind == "search" then return _("Zotero - Search: ") .. view.query end
    if view.kind == "device" then
        return _("Zotero - On device") .. (view.query ~= "" and (": " .. view.query) or "")
    end
    local collection = view.key and self.api.getCollections()[view.key]
    return _("Zotero - ") .. (collection and collection.data.name or view.key or _("Collections"))
end

---@param items ZoteroRow[]
---@param empty_text string
function Browser:setItems(items, empty_text)
    if #items == 0 then table.insert(items, { text = empty_text, is_label = true }) end
    for _, item in ipairs(items) do
        if item.collection or item.destination then item.bold = true end
    end
    self.position_library = self.position_library or self.api.getLocalLibraryPrefix() or "local"
    self.page = self.current_view.page or 1
    self:switchItemTable(self:locationTitle(), items, -1)
    if not self.waiting_for_cache then self.current_view.page = self.page end
end

--- Handle row selection. Example: browser:onMenuSelect(row).
---@param item ZoteroRow
function Browser:onMenuSelect(item)
    if item.enabled == false then return end
    if item.destination then self:navigate{ kind = item.destination } return end
    if item.search then self:onLeftButtonTap() return end
    if item.continue_reading then self:continueReading() return end
    if item.collection then self:navigate{ kind = "collection", key = item.key } return end
    if item.is_label then return end
    local path = self.api.getLocalAttachmentPath(item.key)
    if path then self:openAttachment(path, item.key) return end
    self:startDownload(function() return self:downloadItem(item) end, item.key)
end

--- Recheck the last document before opening its original path. Example: browser:continueReading().
function Browser:continueReading()
    local recent = self.api.getContinueReading(self.api.getLocalLibraryPrefix() or "local")
    if recent then self:openAttachment(recent.path, recent.key) else self:refresh() end
end

--- Open the exact existing document path so KOReader retains its sidecars. Example: browser:openAttachment(path, "ATTACH01").
---@param path string
---@param key string
function Browser:openAttachment(path, key)
    local progress = self.api.progress
    local reading_context = progress and progress:safe("prepare", key, path)
    self:savePosition()
    local library = self.position_library or self.api.getLocalLibraryPrefix() or "local"
    local position = self.api.getBrowserPosition(library)
    self.close_callback()
    self.runtime:openReader(path, function(reader)
        self.api.saveContinueReading(library, key, path)
        if progress then progress:safe("attach", reader, reading_context) end
        self.runtime:bindReaderReturn(reader, library, position)
    end)
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
---@param key string|nil
function Browser:startDownload(task, key)
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
        if path then self:openAttachment(path, key) end
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
