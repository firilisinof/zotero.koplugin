local EPUB = require("zoteroepub")
local Codec = {}
Codec.__index = Codec

--- Select only supported reader engines. Example: Codec.new(reader, identity).
---@param reader table
---@param identity table
---@return table|nil, string|nil
function Codec.new(reader, identity)
    if identity.format == "application/pdf" and reader.paging then
        return setmetatable({ reader = reader, kind = "pdf" }, Codec)
    end
    if identity.format ~= "application/epub+zip" or not reader.rolling then return nil, "Unsupported position-sharing reader provider" end
    local ok, epub = pcall(EPUB.new, reader.document, reader.doc_settings:readSetting("cre_dom_version") or reader.document:getLatestDomVersion())
    if not ok then return nil, tostring(epub) end
    return setmetatable({ reader = reader, kind = "epub", epub = epub }, Codec)
end

--- Capture native progress without forcing a sidecar flush. Example: codec:capture().
---@return string|integer
function Codec:capture()
    return self.kind == "pdf" and self.reader.paging:getLastProgress() or self.reader.rolling:getLastProgress()
end

---@param page number
---@return boolean
function Codec:validPage(page)
    return type(page) == "number" and page % 1 == 0 and page >= 1 and page <= self.reader.document:getPageCount()
end

--- Encode a page or exact content point. Example: codec:encode(native).
---@param native string|integer
---@return string|integer|nil, string|nil
function Codec:encode(native)
    if self.epub then
        local cfi, reason = self.epub:encode(native)
        return cfi and cfi:match("^epubcfi%((.*)%)$"), reason
    end
    if self:validPage(native) then return native - 1 end
    return nil, "Invalid PDF page " .. tostring(native)
end

--- Decode without moving the reader. Example: codec:decode(remote).
---@param value string|integer
---@return string|integer|nil, string|nil
function Codec:decode(value)
    if self.epub then return self.epub:decode(value) end
    if type(value) == "number" and self:validPage(value + 1) then return value + 1 end
    return nil, "Invalid Zotero PDF page index " .. tostring(value)
end

--- Navigate through KOReader so its own progress and sidecars stay authoritative.
---@param native string|integer
function Codec:apply(native)
    if self.epub then self.reader.rolling:onGotoXPointer(native)
    else self.reader.paging:onGotoPage(native) end
end

return Codec
