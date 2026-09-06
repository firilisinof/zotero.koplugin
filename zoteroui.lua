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

--- Open an attachment in KOReader. Example: UI:openReader(path).
---@param path string
function UI:openReader(path)
    require("apps/reader/readerui"):showReader(path)
end

return UI
