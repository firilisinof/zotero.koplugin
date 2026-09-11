-- Named fake for zoteroprogressworker. Jobs wait until a spec runs, expires or cancels them.
local Util = require("zoteroutil")
local Worker = {}
Worker.__index = Worker

function Worker.new()
    return setmetatable({ jobs = {} }, Worker)
end

-- Like the real worker, refusing to start calls back before returning a no-op cancel.
function Worker:run(task, callback, limit)
    if self.refuse then
        callback({ error = "Could not start Zotero worker" })
        return function() end
    end
    local job = { task = task, callback = callback, limit = limit }
    table.insert(self.jobs, job)
    return function() self:finish(job, { error = "Interrupted", delay = 0 }) end
end

function Worker:finish(job, result)
    if job.done then return end
    job.done = true
    job.callback(result)
end

function Worker:next()
    local job = table.remove(self.jobs, 1)
    assert(job, "No background job queued")
    return job
end

-- Results cross the same JSON pipe as zoteroprogressworker, so lossy encoding shows up here.
function Worker:deliver(job, result)
    self:finish(job, Util.decode(Util.encode(result)))
end

function Worker:work()
    local job = self:next()
    if not job.done then self:deliver(job, job.task()) end
end

-- The worst timeout: the child wrote all its files, then was killed before reporting.
function Worker:expire()
    local job = self:next()
    job.task()
    self:finish(job, { error = "Zotero request timed out", delay = 60 })
end

return Worker
