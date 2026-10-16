--[[--
Counts the full attachment reads zoteroprogressidentity makes while still opening
the real file, so specs can tell a cached checksum stamp from a rehash.

    local opener = FakeFileOpener.new()
    Identity.open = opener.open
    -- exercise a reader path
    assert.equals(0, opener:readCount(path))
    Identity.open = io.open
]]

local FakeFileOpener = {}
FakeFileOpener.__index = FakeFileOpener

function FakeFileOpener.new()
    local self = setmetatable({ reads = {} }, FakeFileOpener)
    -- Identity calls `Identity.open(path, mode)`, so this has to be a plain field holding a function.
    self.open = function(path, mode)
        self.reads[path] = (self.reads[path] or 0) + 1
        return io.open(path, mode)
    end
    return self
end

--- Number of times a path was opened for hashing.
function FakeFileOpener:readCount(path)
    return self.reads[path] or 0
end

return FakeFileOpener
