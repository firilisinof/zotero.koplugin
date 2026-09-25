local Runner = require("spec.support.fake_task_runner")
local Worker = require("spec.support.fake_worker")
local FakeUI = {}
FakeUI.__index = FakeUI

local function widgetType(kind)
    return { new = function(_, fields)
        fields.kind = kind
        fields.onShowKeyboard = function(self) self.keyboard_shown = true end
        fields.getInputText = function(self) return self.input end
        fields.getFields = function(self)
            local values = {}
            for index, field in ipairs(self.fields) do values[index] = field.text end
            return values
        end
        return fields
    end }
end

function FakeUI.new()
    local runtime = setmetatable({ shown = {}, closed = {}, scheduled = {}, online = true,
        clock = 1000000, runner = Runner.new(), worker = Worker.new(), repaints = 0, wraps = 0 }, FakeUI)
    runtime.jobs = runtime.worker.jobs
    for _, kind in ipairs({ "InputDialog", "MultiInputDialog", "RadioButtonWidget", "ButtonDialog",
        "SpinWidget", "InfoMessage", "TextViewer" }) do
        runtime[kind] = widgetType(kind)
    end
    return runtime
end

function FakeUI:show(widget) table.insert(self.shown, widget) end
function FakeUI:repaint() self.repaints = self.repaints + 1 end
function FakeUI:schedule(callback) table.insert(self.scheduled, callback) end
function FakeUI:wrap(callback) self.wraps = self.wraps + 1 return callback() end
function FakeUI:run(task) return self.runner:run(task) end
function FakeUI:background(task, callback, limit) return self.worker:run(task, callback, limit) end
function FakeUI:work() self.worker:work() end

-- InfoMessage calls its dismiss callback however it closes, tapped or closed by code.
function FakeUI:close(widget)
    if not widget then return end
    table.insert(self.closed, widget)
    local dismiss = widget.dismiss_callback
    widget.dismiss_callback = nil
    if dismiss then dismiss() end
end

function FakeUI:cancellable(text, on_cancel)
    local widget = self:message(text)
    widget.dismiss_callback = on_cancel
    return widget
end

-- InfoMessage closes itself on tap.
function FakeUI:tapClose(widget) self:close(widget) end
function FakeUI:isOnline() return self.online end
function FakeUI:now() return self.clock end
function FakeUI:openReader(path, after_open)
    self.opened_path = path
    if after_open then after_open({}) end
end
function FakeUI:bindReaderReturn(reader, library, position)
    self.reader_return = { reader = reader, library = library, position = position }
end

function FakeUI:message(text, timeout)
    local widget = self.InfoMessage:new{ text = text, timeout = timeout }
    self:show(widget)
    return widget
end

function FakeUI:flush()
    while #self.scheduled > 0 do table.remove(self.scheduled, 1)() end
end

function FakeUI:last()
    return self.shown[#self.shown]
end

function FakeUI:newBrowser(Browser, api)
    return setmetatable({ api = api, runtime = self, paths = {},
        current_view = { kind = "home" }, close_callback = function() end,
        switchItemTable = function(browser, title, rows) browser.title, browser.rows = title, rows end,
    }, { __index = Browser })
end

return FakeUI
