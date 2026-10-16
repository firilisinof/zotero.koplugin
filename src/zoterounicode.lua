local Unicode = {}

--- Map Unicode code-point boundaries to UTF-16 boundaries. Example: Unicode.boundaries("a😀").
---@param value string
---@return integer[]
function Unicode.boundaries(value)
    local offsets, i, units = { [0] = 0 }, 1, 0
    while i <= #value do
        local lead = value:byte(i)
        local width = lead < 128 and 1 or lead >= 194 and lead <= 223 and 2
            or lead >= 224 and lead <= 239 and 3 or lead >= 240 and lead <= 244 and 4
        assert(width and i + width - 1 <= #value, "Invalid UTF-8 at byte " .. i)
        local code = width == 1 and lead or lead % (2 ^ (7 - width))
        for j = 1, width - 1 do
            local byte = value:byte(i + j)
            assert(byte >= 128 and byte <= 191, "Invalid UTF-8 continuation at byte " .. (i + j))
            code = code * 64 + byte - 128
        end
        assert(code <= 0x10FFFF and not (code >= 0xD800 and code <= 0xDFFF), "Invalid Unicode scalar " .. code)
        assert(width == 1 or code >= ({ [2] = 128, [3] = 2048, [4] = 65536 })[width], "Overlong UTF-8")
        units = units + (code > 65535 and 2 or 1)
        offsets[#offsets + 1], i = units, i + width
    end
    return offsets
end

--- Convert an exact boundary, rejecting split surrogates. Example: Unicode.offset(text, 3, true).
---@param value string
---@param offset integer
---@param from_utf16 boolean|nil
---@return integer
function Unicode.offset(value, offset, from_utf16)
    assert(type(offset) == "number" and offset >= 0 and offset % 1 == 0, "Invalid character offset " .. tostring(offset))
    local map = Unicode.boundaries(value)
    if not from_utf16 then
        assert(map[offset], "Character offset " .. offset .. " exceeds text length " .. #map)
        return map[offset]
    end
    for i = 0, #map do if map[i] == offset then return i end end
    error("UTF-16 offset " .. offset .. " is not a code-point boundary")
end

--- Match only exact text or deterministic ASCII-whitespace normalization.
--- Returns native-codepoint -> source-codepoint boundaries, never fuzzy matches.
---@param source string
---@param native string
---@return table|nil
function Unicode.align(source, native)
    Unicode.boundaries(source); Unicode.boundaries(native)
    local chars = {}
    for char in source:gmatch(".[\128-\191]*") do table.insert(chars, char) end
    if source == native then
        local map = {}; for i = 0, #chars do map[i] = i end; return map
    end
    local output, map, i = {}, { [0] = 0 }, 1
    while i <= #chars do
        local char = chars[i]
        if char:match("^[ \t\r\n\f]$") then
            while chars[i + 1] and chars[i + 1]:match("^[ \t\r\n\f]$") do i = i + 1 end
            char = " "
        end
        table.insert(output, char); map[#output] = i; i = i + 1
    end
    if table.concat(output) == native then return map end
    if output[1] == " " then
        table.remove(output, 1)
        local shifted = { [0] = map[1] }
        for j = 1, #output do shifted[j] = map[j + 1] end
        map = shifted
        if table.concat(output) == native then return map end
    end
    if output[#output] == " " then
        table.remove(output); map[#output + 1] = nil
        if table.concat(output) == native then return map end
    end
end

return Unicode
