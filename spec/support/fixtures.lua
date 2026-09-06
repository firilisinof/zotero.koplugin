--[[--
Loads the canned Zotero Web API responses in spec/fixtures/.

The directory is derived from this file's own source path, which Lua resolved
through `package.path`. Opening a fixture with the same relative path therefore
resolves against the same working directory, wherever the test runner started.
]]

local JSON = require("json")

local this_file = debug.getinfo(1, "S").source:sub(2)
local FIXTURE_DIR = this_file:gsub("support[/\\][^/\\]+$", "fixtures/")

local Fixtures = {}

--- The raw JSON text of a fixture, as the API would have sent it.
function Fixtures.raw(name)
    local path = FIXTURE_DIR .. name
    local f = assert(io.open(path, "r"), "could not open fixture " .. path)
    local content = f:read("*all")
    f:close()
    return content
end

--- A fixture decoded into a Lua table.
function Fixtures.decode(name)
    return JSON.decode(Fixtures.raw(name))
end

Fixtures.dir = FIXTURE_DIR

return Fixtures
