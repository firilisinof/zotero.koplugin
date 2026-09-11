-- SLAXML 756ffad03d2a06271170a0ba82d6eac02cc2a5ca is isolated here.
local SAX = require("zoteroslaxml")
local XML = {}

--- Parse mixed content without executing declarations. Example: XML.parse(xhtml).
---@param source string
---@return table
function XML.parse(source)
    assert(type(source) == "string", "Expected XML string, got " .. type(source))
    assert(#source <= 8 * 1024 * 1024, "XML exceeds supported 8 MiB section size")
    assert(not source:find("<!ENTITY", 1, true), "XML entity declarations are unsupported")
    source = source:gsub("\r\n", "\n"):gsub("\r", "\n")
    source = source:gsub("<!DOCTYPE[^>]*>", "")
    local root = { name = "#document", children = {}, attributes = {} }
    local current, depth = root, 0
    local parser = SAX:parser{
        startElement = function(name, namespace)
            depth = depth + 1
            assert(depth <= 256, "XML nesting exceeds supported depth 256")
            local node = { name = name, namespace = namespace, children = {}, attributes = {}, parent = current }
            table.insert(current.children, node)
            current = node
        end,
        attribute = function(name, value) current.attributes[name] = value end,
        closeElement = function(name)
            assert(current.name == name, "XML closing " .. name .. " does not match " .. current.name)
            current, depth = current.parent, depth - 1
        end,
        text = function(value, cdata)
            -- Unexpanded entities cannot safely supply character offsets.
            assert(cdata or not value:find("&[%w#]+;"), "Unresolved XML entity in text")
            table.insert(current.children, { name = "#text", text = value, parent = current, cdata = cdata })
        end,
        comment = function() end, pi = function() end,
    }
    parser:parse(source, { stripWhitespace = false })
    assert(current == root, "XML has unclosed element " .. current.name)
    return root
end

--- Return children matching a local name. Example: XML.children(node, "itemref").
---@param node table
---@param name string|nil
---@return table[]
function XML.children(node, name)
    local found = {}
    for _, child in ipairs(node.children) do
        if (name and child.name == name) or (not name and child.name ~= "#text") then
            table.insert(found, child)
        end
    end
    return found
end

--- Find the first descendant by local name. Example: XML.find(root, "spine").
---@param node table
---@param name string
---@return table|nil
function XML.find(node, name)
    if node.name == name then return node end
    for _, child in ipairs(node.children or {}) do
        local found = XML.find(child, name)
        if found then return found end
    end
end

return XML
