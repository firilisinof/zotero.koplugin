-- Compatibility target: EpubCFI bundled with Zotero 10.0.1 (epub.js fork).
local XML = require("zoteroxml")
local CFI = {}

---@param node table
---@return integer
local function nodeStep(node)
    local siblings = XML.children(node.parent, node.name == "#text" and "#text" or nil)
    for i, sibling in ipairs(siblings) do
        if sibling == node then return node.name == "#text" and (i * 2 - 1) or (i * 2) end
    end
    error("CFI node is absent from its parent")
end

--- Serialize a point using Zotero's text-sibling numbering. Example: CFI.encode(node, 0, "/6/2").
---@param node table
---@param offset integer|nil
---@param base string
---@return string
function CFI.encode(node, offset, base)
    local steps = {}
    while node.parent and node.parent.name ~= "#document" do
        table.insert(steps, 1, "/" .. nodeStep(node))
        node = node.parent
    end
    return "epubcfi(" .. base .. "!" .. table.concat(steps) .. (offset and (":" .. offset) or "") .. ")"
end

---@param path string
---@return table[], integer|nil
local function parseSteps(path)
    local steps, i = {}, 1
    while path:sub(i, i) == "/" do
        local number, finish = path:match("^/(%d+)()", i)
        assert(number and tonumber(number) > 0, "Invalid CFI step in " .. path)
        i = finish
        local assertion
        if path:sub(i, i) == "[" then
            local chars = {}
            i = i + 1
            while i <= #path and path:sub(i, i) ~= "]" do
                if path:sub(i, i) == "^" then i = i + 1 end
                table.insert(chars, path:sub(i, i)); i = i + 1
            end
            assert(path:sub(i, i) == "]", "Unclosed CFI assertion in " .. path)
            assertion, i = table.concat(chars), i + 1
        end
        table.insert(steps, { number = tonumber(number), assertion = assertion })
    end
    local rest = path:sub(i)
    assert(rest == "" or rest:match("^:%d+$"), "Unsupported CFI suffix " .. rest)
    return steps, rest ~= "" and tonumber(rest:sub(2)) or nil
end

--- Parse a single content point; reject ranges and media offsets. Example: CFI.parse(cfi).
---@param value string
---@return table
function CFI.parse(value)
    assert(type(value) == "string" and #value <= 16384, "Expected CFI string up to 16384 bytes")
    -- Zotero 10.0.1 serializes synced lastPageIndex settings without the wrapper.
    if value:sub(1, 1) == "/" then value = "epubcfi(" .. value .. ")" end
    local base, path = value:match("^epubcfi%((.-)!(.-)%)$")
    assert(base and not base:find("!", 1, true), "Invalid CFI " .. value)
    local package_steps = parseSteps(base)
    assert(#package_steps == 2 and package_steps[2].number % 2 == 0, "Unsupported CFI package path " .. base)
    local steps, offset = parseSteps(path)
    return { spine = package_steps[2].number / 2, package_steps = package_steps, steps = steps, offset = offset }
end

--- Resolve content steps in Zotero's transformed tree. Example: CFI.resolve(html, parsed).
---@param root table
---@param parsed table
---@return table, integer
function CFI.resolve(root, parsed)
    local node = root
    for _, step in ipairs(parsed.steps) do
        local text = step.number % 2 == 1
        local siblings = XML.children(node, text and "#text" or nil)
        node = siblings[text and (step.number + 1) / 2 or step.number / 2]
        assert(node, "CFI step " .. step.number .. " does not exist")
        assert(not step.assertion or node.attributes.id == step.assertion, "CFI element ID does not match")
    end
    return node, parsed.offset or 0
end

return CFI
