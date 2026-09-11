local CFI = require("zoterocfi")
local Range = {}

--- Combine two verified point CFIs using the common path. Example: Range.join(start, finish).
---@param first string
---@param last string
---@return string
function Range.join(first, last)
    CFI.parse(first); CFI.parse(last)
    local base, start = first:match("^epubcfi%((.-)!(.-)%)$")
    local end_base, finish = last:match("^epubcfi%((.-)!(.-)%)$")
    assert(base == end_base, "Highlights spanning EPUB spine entries are unsupported")
    local a, b = {}, {}
    for step in start:gmatch("/[^/]+") do a[#a + 1] = step end
    for step in finish:gmatch("/[^/]+") do b[#b + 1] = step end
    local shared = {}
    while #a > 1 and #b > 1 and a[1] == b[1] do
        shared[#shared + 1] = table.remove(a, 1); table.remove(b, 1)
    end
    return "epubcfi(" .. base .. "!" .. table.concat(shared) .. "," .. table.concat(a) .. "," .. table.concat(b) .. ")"
end

--- Expand ranges, respecting escaped commas in assertions. Example: Range.split(cfi).
---@param value string
---@return string, string
function Range.split(value)
    assert(type(value) == "string" and #value < 32768, "Expected EPUB range CFI up to 32768 bytes")
    if value:sub(1, 1) == "/" then value = "epubcfi(" .. value .. ")" end
    local inner = assert(value:match("^epubcfi%((.*)%)$"), "Expected epubcfi range wrapper")
    local parts, start, depth, escaped = {}, 1, 0, false
    for i = 1, #inner do
        local character = inner:sub(i, i)
        if escaped then escaped = false
        elseif character == "^" then escaped = true
        elseif character == "[" then depth = depth + 1
        elseif character == "]" then depth = depth - 1
        elseif character == "," and depth == 0 then parts[#parts + 1] = inner:sub(start, i - 1); start = i + 1 end
    end
    parts[#parts + 1] = inner:sub(start)
    assert(#parts == 3, "Expected EPUB CFI range with two endpoints")
    local first, last = "epubcfi(" .. parts[1] .. parts[2] .. ")", "epubcfi(" .. parts[1] .. parts[3] .. ")"
    CFI.parse(first); CFI.parse(last)
    return first, last
end

return Range
