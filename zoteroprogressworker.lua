-- Non-modal counterpart of Trapper's subprocess boundary: only JSON crosses back.
local ffiutil = require("ffi/util")
local UIManager = require("ui/uimanager")
local JSON = require("json")
local ffi = require("ffi")
local Worker = {}

--- Run bounded network work without intercepting reader input. Example: Worker.run(task, callback).
---@param task function
---@param callback function
---@return function cancel
function Worker.run(task, callback)
    local pid, pipe = ffiutil.runInSubProcess(function(_, output)
        local ok, result = pcall(task)
        ffiutil.writeToFD(output, JSON.encode(ok and result or { error = "Position worker failed" }), true)
    end, true)
    if not pid then callback({ error = "Could not start position worker" }); return function() end end
    local done, elapsed, chunks = false, 0, {}
    local poll
    local function finish(result, kill)
        if done then return end
        done = true
        UIManager:unschedule(poll)
        -- Also kill the PID if cancellation beats the child's setpgid(). Never
        -- read a live pipe here: suspend/close must not wait for network work.
        if kill then ffi.C.kill(-pid, 9); ffi.C.kill(pid, 9) end
        if pipe then ffi.C.close(pipe); pipe = nil end
        local function reap()
            if not ffiutil.isSubProcessDone(pid) then UIManager:scheduleIn(1, reap) end
        end
        reap()
        callback(result)
    end
    poll = function()
        if done then return end
        elapsed = elapsed + 0.25
        local available = ffiutil.getNonBlockingReadSize(pipe) or 0
        if available > 0 then
            local buffer = ffi.new("char[?]", available)
            local count = tonumber(ffi.C.read(pipe, buffer, available))
            if count > 0 then table.insert(chunks, ffi.string(buffer, count)) end
        end
        if ffiutil.isSubProcessDone(pid) then
            table.insert(chunks, ffiutil.readAllFromFD(pipe))
            pipe = nil
            local ok, result = pcall(JSON.decode, table.concat(chunks))
            finish(ok and result or { error = "Position worker returned no result" }, false)
            return
        end
        if elapsed >= 30 then finish({ error = "Position request timed out", delay = 60 }, true); return end
        UIManager:scheduleIn(0.25, poll)
    end
    UIManager:scheduleIn(0.25, poll)
    return function() finish({ error = "Position request interrupted", delay = 0 }, true) end
end

return Worker
