local UI = require("spec.support.fake_ui")
local Runtime = {}
Runtime.__index = Runtime
setmetatable(Runtime, { __index = UI })

function Runtime.new()
    local self = UI.new()
    self.timers = {}
    return setmetatable(self, Runtime)
end

function Runtime:readProgress() return self.existing end
function Runtime:refreshHighlights(reader) reader.refreshed = (reader.refreshed or 0) + 1 end
function Runtime:later(delay, task) self.timers[task] = self.clock + delay end
function Runtime:unschedule(task) self.timers[task] = nil end
function Runtime:advance(seconds)
    self.clock = self.clock + seconds
    local due = {}
    for task, time in pairs(self.timers) do if time <= self.clock then table.insert(due, task) end end
    for _, task in ipairs(due) do self.timers[task] = nil; task() end
end

return Runtime
