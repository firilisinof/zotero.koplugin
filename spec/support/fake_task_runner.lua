local Runner = {}
Runner.__index = Runner

function Runner.new()
    return setmetatable({ calls = 0 }, Runner)
end

function Runner:run(task)
    self.calls = self.calls + 1
    if self.before then self.before(self.calls) end
    if self.cancel_on == self.calls then return false end
    return true, task()
end

return Runner
