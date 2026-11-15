-- Under LuaJIT, assert(v, msg) and error(msg) prefix the raising chunk and line,
-- and a rethrown message gains one prefix per level. Status lines and messages
-- are read on the device, so they keep only the reason (#25).
local ErrorText = {}

-- Chunk names have no spaces on the device; a reason that mentions a path keeps it.
local LOCATION = "^%S-%.lua:%d+: "

--- Reduce a caught Lua error to user-facing text. Example: ErrorText.strip(err).
---@param err unknown A pcall error value: usually a string, sometimes a table or nil
---@return string
function ErrorText.strip(err)
    local text = tostring(err)
    local stripped = text:gsub(LOCATION, "", 1)
    while stripped ~= text do
        text = stripped
        stripped = text:gsub(LOCATION, "", 1)
    end
    return text
end

return ErrorText
