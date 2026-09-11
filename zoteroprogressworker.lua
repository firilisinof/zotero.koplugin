-- Non-modal counterpart of Trapper's subprocess boundary: only JSON crosses back.
-- Position sharing, highlight sync and library sync all run their network work here.
local ffiutil = require("ffi/util")
local UIManager = require("ui/uimanager")
local Util = require("zoteroutil")
local ffi = require("ffi")
local Worker = {}

-- Position and highlight exchanges are a few small requests.
local DEFAULT_LIMIT = 30

--- Run bounded network work without intercepting reader input. Example: Worker.run(task, callback, 60).
---@param task function
---@param callback function
---@param limit number|nil Seconds before the child is killed, 30 when omitted
---@return function cancel
function Worker.run(task, callback, limit)
    limit = limit or DEFAULT_LIMIT
    local pid, pipe = ffiutil.runInSubProcess(function(_, output)
        local ok, result = pcall(task)
        ffiutil.writeToFD(output, Util.encode(ok and result or { error = "Zotero worker failed" }), true)
    end, true)
    if not pid then callback({ error = "Could not start Zotero worker" }); return function() end end
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
            local ok, result = pcall(Util.decode, table.concat(chunks))
            finish(ok and result or { error = "Zotero worker returned no result" }, false)
            return
        end
        if elapsed >= limit then finish({ error = "Zotero request timed out", delay = 60 }, true); return end
        UIManager:scheduleIn(0.25, poll)
    end
    UIManager:scheduleIn(0.25, poll)
    return function() finish({ error = "Zotero request interrupted", delay = 0 }, true) end
end

return Worker
