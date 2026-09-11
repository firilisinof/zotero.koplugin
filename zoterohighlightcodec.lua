local Helpers = require("zoterohighlightutil")
local util = require("util")
local ZoteroUtil = require("zoteroutil")
local Range = require("zoterocfirange")
local Codec = {}
Codec.__index = Codec
local colors = { yellow = "#ffd400", red = "#ff6666", green = "#5fb236", blue = "#2ea8e5",
    purple = "#a28ae5", orange = "#f19837", gray = "#aaaaaa", pink = "#e56eee", olive = "#5fb236" }
local color_names = { ["#ffd400"] = "yellow", ["#ff6666"] = "red", ["#5fb236"] = "green",
    ["#2ea8e5"] = "blue", ["#a28ae5"] = "purple", ["#f19837"] = "orange", ["#aaaaaa"] = "gray", ["#e56eee"] = "pink" }

--- Open an isolated conversion document inside the worker. Example: Codec.open(identity, dom_version).
---@param identity table
---@param dom_version integer|nil
---@param matrices table|nil
---@param scratch string|nil
---@return table
function Codec.open(identity, dom_version, matrices, scratch)
    local doc = assert(require("document/documentregistry"):openDocument(identity.path), "Could not open annotation document")
    local self = setmetatable({ document = doc }, Codec)
    if identity.format == "application/pdf" then self.pdf = require("zoteropdf").new(doc, matrices, scratch); return self end
    assert(identity.format == "application/epub+zip", "Unsupported highlight format " .. tostring(identity.format))
    doc:requestDomVersion(assert(dom_version, "Expected enrolled EPUB DOM version"))
    assert(doc:loadDocument(), "Could not load EPUB for highlights"); doc:render()
    self.epub = require("zoteroepub").new(doc, dom_version)
    return self
end

--- Release only the worker's document reference. Example: codec:close().
function Codec:close()
    if self.pdf then self.pdf:close() end
    self.document:close()
end

---@param native table
---@return table
function Codec:position(native)
    if self.epub then
        assert(self.document:compareXPointers(native.pos0, native.pos1) > 0, "Expected forward, nonempty EPUB highlight")
        local start, err = self.epub:encode(native.pos0); assert(start, err)
        local finish, reason = self.epub:encode(native.pos1); assert(finish, reason)
        return { type = "FragmentSelector", conformsTo = "http://www.idpf.org/epub/linking/cfi/epub-cfi.html", value = Range.join(start, finish) }
    end
    local first, last = native.pos0.page, native.pos1.page
    assert(first == last or last == first + 1, "PDF highlights spanning more than two pages are unsupported")
    local first_part = native.ext and (native.ext[first] or native.ext[tostring(first)])
    local position = { pageIndex = first - 1, rects = self.pdf:encodeBoxes(first, first_part and first_part.pboxes or native.pboxes) }
    if last ~= first then
        local last_part = assert(native.ext[last] or native.ext[tostring(last)], "Missing second-page PDF boxes")
        position.nextPageRects = self.pdf:encodeBoxes(last, last_part.pboxes)
    end
    return position
end

--- Encode only fields this plugin owns. Example: codec:encode(native).
---@param native table|boolean
---@return table|boolean
function Codec:encode(native)
    if native == false then return false end
    assert(Helpers.supported(native), "Expected supported native text highlight")
    assert(not native.note_format or native.note_format == "plain", "Formatted KOReader notes are unsupported")
    return { text = native.text or "", comment = native.note or "", color = colors[native.color or "yellow"] or "#ffd400",
        kind = native.drawer == "underscore" and "underline" or "highlight", position = self:position(native) }
end

--- Resolve the format-specific geometry. Example: codec:decodePosition(position).
---@param position table
---@return table
function Codec:decodePosition(position)
    local native = {}
    if self.epub then
        assert(position.type == "FragmentSelector" and not position.refinedBy and
            position.conformsTo == "http://www.idpf.org/epub/linking/cfi/epub-cfi.html", "Expected EPUB CFI FragmentSelector")
        local start, finish = Range.split(position.value)
        local err
        native.pos0, err = self.epub:decode(start); assert(native.pos0, err)
        native.pos1, err = self.epub:decode(finish); assert(native.pos1, err)
        assert(self.document:compareXPointers(native.pos0, native.pos1) > 0, "Expected forward EPUB highlight range")
    else
        native = self.pdf:decodeBoxes(position.pageIndex + 1, position.rects)
        if position.nextPageRects then
            local last = self.pdf:decodeBoxes(position.pageIndex + 2, position.nextPageRects)
            -- String page keys survive the JSON journal, as in Helpers.native.
            native.ext = { [tostring(position.pageIndex + 1)] = util.tableDeepCopy(native), [tostring(position.pageIndex + 2)] = last }
            native.pos1 = last.pos1
        end
    end
    return native
end

--- Convert a validated remote range to native geometry. Example: codec:decode(value).
---@param value table|boolean
---@return table|boolean
function Codec:decode(value)
    if value == false then return false end
    assert(value.kind == "highlight" or value.kind == "underline", "Unsupported Zotero annotation type " .. tostring(value.kind))
    local native = self:decodePosition(value.position)
    native.text, native.note = value.text, value.comment ~= "" and value.comment or nil
    native.color = assert(color_names[value.color], "Unsupported Zotero highlight color " .. tostring(value.color))
    native.drawer = value.kind == "underline" and "underscore" or "lighten"
    return native
end

--- Canonicalize incoming positions through both engines, ignoring presentation metadata.
---@param item table
---@return table|boolean
function Codec:remote(item)
    local fields = item.data
    assert(not fields.annotationIsExternal, "Embedded Zotero annotations are not writable highlights")
    if fields.deleted == true or fields.deleted == 1 then return false end
    assert(fields.itemType == "annotation", "Expected Zotero annotation item")
    local value = { text = fields.annotationText or "", comment = fields.annotationComment or "",
        color = (fields.annotationColor or ""):lower(), kind = fields.annotationType,
        position = type(fields.annotationPosition) == "string" and ZoteroUtil.decode(fields.annotationPosition) or fields.annotationPosition }
    -- Preserve every position extension on the server: only canonical fields are compared.
    return self:encode(self:decode(value))
end

--- Build minimal PATCH/create fields; remote tags, authors and relations are never replaced.
---@param value table|boolean
---@return table
function Codec:fields(value)
    if value == false then return { deleted = 1 } end
    local page, sort_index
    if self.epub then
        local offset
        page, offset = self.epub:sortOffset((Range.split(value.position.value)))
        sort_index = string.format("%05d|%08d", page, offset)
    else
        page = value.position.pageIndex
        local native = self.pdf:decodeBoxes(page + 1, value.position.rects)
        sort_index = string.format("%05d|%06d|%05d", page, 0, math.max(0, math.floor(native.pboxes[1].y)))
    end
    return { annotationType = value.kind, annotationText = value.text, annotationComment = value.comment,
        annotationColor = value.color, annotationPosition = ZoteroUtil.encode(value.position),
        annotationPageLabel = tostring(page + 1), annotationSortIndex = sort_index }
end

return Codec
