-- Thin KOReader boundary. Browser and dialog tests inject a named fake runtime.
local UIManager = require("ui/uimanager")
local Trapper = require("ui/trapper")
local NetworkMgr = require("ui/network/manager")
local UI = {
    InputDialog = require("ui/widget/inputdialog"),
    MultiInputDialog = require("ui/widget/multiinputdialog"),
    RadioButtonWidget = require("ui/widget/radiobuttonwidget"),
    ButtonDialog = require("ui/widget/buttondialog"),
    SpinWidget = require("ui/widget/spinwidget"),
    InfoMessage = require("ui/widget/infomessage"),
    TextViewer = require("ui/widget/textviewer"),
}

--- Show a widget. Example: UI:show(dialog).
---@param widget table
function UI:show(widget)
    UIManager:show(widget)
end

--- Close a widget if present. Example: UI:close(dialog).
---@param widget table|nil
function UI:close(widget)
    if widget and not widget.zotero_dismissed then UIManager:close(widget) end
end

--- Display a message, persistent when timeout is nil. Example: UI:message("Done", 3).
---@param text string
---@param timeout number|nil
---@return table
function UI:message(text, timeout)
    local widget = self.InfoMessage:new{ text = text, timeout = timeout, icon = "notice-info" }
    self:show(widget)
    return widget
end

--- Let progress paint before starting work. Example: UI:repaint().
function UI:repaint()
    UIManager:forceRePaint()
end

--- Schedule after current UI work. Example: UI:schedule(callback).
---@param callback function
function UI:schedule(callback)
    UIManager:scheduleIn(0.05, callback)
end

--- Enter KOReader's cooperative task wrapper. Example: UI:wrap(callback).
---@param callback function
function UI:wrap(callback)
    return Trapper:wrap(callback)
end

--- Run file I/O outside the UI process. Example: UI:run(task, progress).
---@param task function
---@param progress table
---@return boolean, string|nil, string|nil
function UI:run(task, progress)
    local completed, path, err = Trapper:dismissableRunInSubprocess(task, progress)
    progress.dismiss_callback = nil
    progress.zotero_dismissed = not completed
    return completed, path, err
end

--- Read connectivity without enabling Wi-Fi. Example: UI:isOnline().
---@return boolean
function UI:isOnline()
    return NetworkMgr:isConnected() and NetworkMgr:isOnline()
end

--- Read wall time for automatic sync. Example: UI:now().
---@return number
function UI:now()
    return os.time()
end

--- Schedule a progress checkpoint without blocking input. Example: UI:later(2, callback).
---@param seconds number
---@param callback function
function UI:later(seconds, callback)
    UIManager:scheduleIn(seconds, callback)
end

--- Cancel a pending checkpoint. Example: UI:unschedule(callback).
---@param callback function
function UI:unschedule(callback)
    UIManager:unschedule(callback)
end

--- Invalidate native highlight boxes after an import, without changing reading layout.
---@param reader table
function UI:refreshHighlights(reader)
    reader.view:resetHighlightBoxesCache()
    if reader.view.footer then reader.view.footer:maybeUpdateFooter() end
    UIManager:setDirty(reader, "ui")
end

--- Execute network work in a non-modal child. Example: UI:background(task, callback).
---@param task function
---@param callback function
---@return function
function UI:background(task, callback)
    return require("zoteroprogressworker").run(task, callback)
end

--- Inspect existing progress before ReaderUI initializes defaults. Example: UI:readProgress(path).
---@param path string
---@return string|integer|nil
function UI:readProgress(path)
    local settings = require("docsettings"):open(path)
    return settings:readSetting("last_xpointer") or settings:readSetting("last_page")
end

--- Open an attachment in KOReader. Example: UI:openReader(path).
---@param path string
---@param after_open function|nil
function UI:openReader(path, after_open)
    require("apps/reader/readerui"):showReader(path, nil, nil, nil, after_open)
end

--- Attach return behavior only after KOReader successfully opens a Zotero document. Example: UI:bindReaderReturn(reader, library, position).
---@param reader table
---@param library string
---@param position ZoteroBrowserPosition
function UI:bindReaderReturn(reader, library, position)
    require("zoteroreader").bind(reader, function()
        local plugin = require("pluginloader"):getPluginInstance("zotero")
        if not plugin or not plugin.initialized then return end
        plugin.api.saveBrowserPosition(library, position)
        -- showFileManager has mounted a fresh plugin instance. Its browser owns
        -- the return view, and an account changed in the reader stays isolated.
        plugin.browser:restoreLibrary()
        self:show(plugin.zotero_dialog)
    end)
end

return UI
