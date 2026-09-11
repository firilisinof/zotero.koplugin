-- Real zoteroutil file I/O for outbox store specs, counting reads and writes and
-- failing writes on demand. Store calls util functions with a dot, so these are closures.
local Util = require("zoteroutil")
local FakeStoreDisk = {}

function FakeStoreDisk.new()
    local disk = { reads = 0, writes = 0, fail_writes = false, encode = Util.encode, decode = Util.decode }
    disk.read = function(path)
        disk.reads = disk.reads + 1
        return Util.read(path)
    end
    disk.write = function(path, contents, durable)
        if disk.fail_writes then return "Could not write " .. path .. ": no space left on device" end
        disk.writes = disk.writes + 1
        return Util.write(path, contents, durable)
    end
    return disk
end

return FakeStoreDisk
