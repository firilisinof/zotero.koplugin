local XML = require("zoteroxml")
local CFI = require("zoterocfi")
local Unicode = require("zoterounicode")
local EPUB = { VERSION = 1 }
EPUB.__index = EPUB
local replaced = { html = true, head = true, body = true, base = true, meta = true }
local removed = { style = true, title = true }

---@param base string
---@param href string
---@return string
local function archivePath(base, href)
    assert(not href:find("[?#]") and not href:match("^[/\\]") and not href:match("^%a+:"), "Unsupported EPUB resource " .. href)
    href = href:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
    local parts = {}
    for part in (base .. href):gmatch("[^/]+") do
        if part == ".." then assert(#parts > 0, "EPUB resource escapes archive"); table.remove(parts)
        elseif part ~= "." then table.insert(parts, part) end
    end
    return table.concat(parts, "/")
end

---@param document table
---@param path string
---@return table
local function readXML(document, path)
    local source = document:getDocumentFileContent(path)
    assert(source, "Missing EPUB resource " .. path)
    return XML.parse(source)
end

---@param node table
---@param parent table|nil
---@param mapping table
---@return table|nil
local function zoteroTree(node, parent, mapping)
    assert(node.name ~= "math", "MathML sections require an unsupported Zotero DOM transformation")
    if removed[node.name] or (node.name == "link" and (node.attributes.rel or ""):find("stylesheet")) then return end
    assert(node.name ~= "object", "EPUB object transformation is unsupported")
    local copy = { name = replaced[node.name] and ("replaced-" .. node.name) or node.name,
        text = node.text, attributes = node.attributes, parent = parent, children = {}, source = node }
    mapping[node] = copy
    for _, child in ipairs(node.children or {}) do
        local transformed = zoteroTree(child, copy, mapping)
        if transformed then table.insert(copy.children, transformed) end
    end
    return copy
end

--- Load the package once per open document. Example: EPUB.new(document, dom_version).
---@param document table
---@param dom_version integer
---@return table
function EPUB.new(document, dom_version)
    assert(document.getDocumentFileContent and document.getNormalizedXPointer, "EPUB provider lacks XPointer APIs")
    local container = readXML(document, "META-INF/container.xml")
    local rootfile = assert(XML.find(container, "rootfile"), "Missing EPUB rootfile")
    local path = assert(rootfile.attributes["full-path"], "Missing EPUB package path")
    local package = readXML(document, archivePath("", path))
    local spine = assert(XML.find(package, "spine"), "Missing EPUB spine")
    local self = setmetatable({ document = document, dom_version = dom_version, sections = {}, spine = {}, fragments = {} }, EPUB)
    local manifest, root = assert(XML.find(package, "manifest"), "Missing EPUB manifest"), spine.parent
    for i, child in ipairs(XML.children(root)) do if child == spine then self.spine_step = 2 * i end end
    local items = {}
    for _, item in ipairs(XML.children(manifest, "item")) do items[item.attributes.id] = item.attributes end
    for i, ref in ipairs(XML.children(spine, "itemref")) do
        local item = assert(items[ref.attributes.idref], "Missing EPUB spine manifest entry")
        local entry = { path = archivePath(path:match("^(.*[/])") or "", item.href), id = ref.attributes.idref,
            media = item["media-type"], index = i }
        self.spine[i] = entry
        if dom_version >= 20240114 or entry.media == "application/xhtml+xml" then
            table.insert(self.fragments, entry); entry.fragment = #self.fragments
        end
    end
    return self
end

---@param index integer
---@return table
function EPUB:section(index)
    if self.sections[index] then return self.sections[index] end
    local entry = assert(self.spine[index], "EPUB spine index does not exist: " .. tostring(index))
    assert(entry.media == "application/xhtml+xml", "Unsupported EPUB spine media type " .. tostring(entry.media))
    local source = readXML(self.document, entry.path)
    local html = assert(XML.find(source, "html"), "EPUB section has no html element")
    local mapping = {}
    local transformed = zoteroTree(source, nil, mapping)
    local section = { source = html, html = mapping[html], mapping = mapping, tree = transformed, entry = entry }
    self.section_order = self.section_order or {}
    table.insert(self.section_order, index)
    if #self.section_order > 2 then self.sections[table.remove(self.section_order, 1)] = nil end
    self.sections[index] = section
    return section
end

---@param segment string
---@return string, integer
local function xpathStep(segment)
    local name, index = segment:match("^([%w_:%-]+)%[(%d+)%]$")
    if not name then name, index = segment, "1" end
    if name:match("^text%(%)") then name = "#text" end
    return name, tonumber(index)
end

---@param pointer string
---@return table, integer|nil
local function pointerSteps(pointer)
    local location, offset = pointer:match("^(.*)%.(%d+)$")
    location = location or pointer
    local steps = {}
    for segment in location:gmatch("[^/]+") do
        local name, index
        if segment:match("^text%(%)") then
            name, index = "#text", tonumber(segment:match("%[(%d+)%]")) or 1
        else name, index = xpathStep(segment) end
        table.insert(steps, { name = name, index = index })
    end
    return steps, tonumber(offset)
end

---@param section table
---@param steps table[]
---@return table
local function sourceNode(section, steps)
    local node = section.source
    for i = 3, #steps do
        if steps[i].name == "#text" then return node end
        node = XML.children(node, steps[i].name)[steps[i].index]
        assert(node, "XPointer path is absent from source XHTML")
    end
    return node
end

---@param node table
---@param fragment integer
---@param offset integer|nil
---@return string
local function nativePointer(node, fragment, offset)
    local steps = {}
    while node.parent and node.parent.name ~= "#document" do
        local siblings = XML.children(node.parent, node.name)
        for i, sibling in ipairs(siblings) do
            if sibling == node then
                table.insert(steps, 1, (node.name == "#text" and "text()" or node.name) .. "[" .. i .. "]")
                break
            end
        end
        node = node.parent
    end
    return "/body/DocFragment[" .. fragment .. "]/" .. table.concat(steps, "/") .. (offset and ("." .. offset) or "")
end

---@param pointer string
---@param node table
local function validateText(self, pointer, node)
    assert(self.document:isXPointerInDocument(pointer), "XPointer is absent from the loaded document")
    if node.name == "#text" then
        assert(self.document:getTextFromXPointer(pointer) == node.text,
            "EPUB text normalization differs; exact location cannot be established")
    end
end

---@param parent table
---@param fragment integer
---@return table[], table
local function textLocations(self, parent, fragment)
    local locations, by_source, native_index = {}, {}, 1
    for _, source in ipairs(XML.children(parent, "#text")) do
        assert(not source.cdata, "CDATA text boundaries are unsupported")
        local pointer = nativePointer(parent, fragment) .. "/text()[" .. native_index .. "].0"
        local native = self.document:getTextFromXPointer(pointer)
        local map = native and Unicode.align(source.text, native)
        if map then
            local location = { source = source, pointer = pointer, native = native, boundaries = map }
            locations[native_index], by_source[source] = location, location
            native_index = native_index + 1
        else
            assert(source.text:match("^%s*$"), "EPUB text normalization differs; exact location cannot be established")
        end
    end
    return locations, by_source
end

--- Convert a live XPointer to a verified CFI point. Example: codec:encode(pointer).
---@param pointer string
---@return string|nil, string|nil
function EPUB:encode(pointer)
    local ok, result = pcall(function()
        local normalized = assert(self.document:getNormalizedXPointer(pointer), "Invalid native XPointer")
        local steps, offset = pointerSteps(normalized)
        assert(steps[1] and steps[1].name == "body" and steps[2] and steps[2].name == "DocFragment", "Unsupported XPointer root")
        local entry = assert(self.fragments[steps[2].index], "Unknown EPUB document fragment")
        local section = self:section(entry.index)
        local source = sourceNode(section, steps)
        if steps[#steps].name == "#text" then
            local locations = textLocations(self, source, entry.fragment)
            local location = assert(locations[steps[#steps].index], "Unknown native text node")
            source = location.source
            offset = assert(location.boundaries[offset or 0], "Native text offset is out of range")
        else validateText(self, pointer, source) end
        local node = assert(section.mapping[source], "XPointer targets removed Zotero content")
        if source.name == "#text" then offset = Unicode.offset(source.text, offset or 0)
        else assert(not offset or offset == 0, "Unsupported element offset"); offset = nil end
        return CFI.encode(node, offset, "/" .. self.spine_step .. "/" .. (entry.index * 2))
    end)
    if ok then return result end
    return nil, tostring(result):gsub("^.-:%d+: ", "")
end

--- Resolve a CFI and confirm the corresponding native passage. Example: codec:decode(cfi).
---@param value string
---@return string|nil, string|nil
function EPUB:decode(value)
    local ok, result = pcall(function()
        local parsed = CFI.parse(value)
        assert(parsed.package_steps[1].number == self.spine_step, "CFI package spine does not match")
        local section = self:section(parsed.spine)
        local assertion = parsed.package_steps[2].assertion
        assert(not assertion or assertion == section.entry.id, "CFI spine ID does not match")
        local node, offset = CFI.resolve(section.html, parsed)
        assert(section.entry.fragment, "CFI targets an unavailable native fragment")
        local pointer
        if node.name == "#text" then
            offset = Unicode.offset(node.text, offset, true)
            local _, locations = textLocations(self, node.source.parent, section.entry.fragment)
            local location = assert(locations[node.source], "CFI targets text omitted by the native reader")
            local native_offset
            for i, raw in pairs(location.boundaries) do if raw == offset then native_offset = i end end
            assert(native_offset, "CFI lies inside normalized whitespace; exact boundary unavailable")
            pointer = location.pointer:gsub("%.0$", "." .. native_offset)
        else
            assert(offset == 0, "Unsupported CFI element offset")
            pointer = nativePointer(node.source, section.entry.fragment)
            validateText(self, pointer, node.source)
        end
        return pointer
    end)
    if ok then return result end
    return nil, tostring(result):gsub("^.-:%d+: ", "")
end

--- Count UTF-16 characters before a resolved point for Zotero annotation ordering.
---@param cfi string
---@return integer, integer
function EPUB:sortOffset(cfi)
    local parsed = CFI.parse(cfi)
    local section = self:section(parsed.spine)
    local target, offset = CFI.resolve(section.html, parsed)
    local count, found = 0, false
    ---@param node table
    local function visit(node)
        if found then return end
        if node == target then count = count + offset; found = true; return end
        if node.name == "#text" then
            local boundaries = Unicode.boundaries(node.text)
            count = count + boundaries[#boundaries]
        end
        for _, child in ipairs(node.children or {}) do visit(child) end
    end
    visit(section.html)
    assert(found, "CFI sort target is absent from EPUB section")
    return parsed.spine - 1, count
end

return EPUB
