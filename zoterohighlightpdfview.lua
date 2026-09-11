local Helpers = require("zoterohighlightutil")
local Geom = require("ui/geometry")
local PDFView = {}

---@param first table
---@param second table
---@return boolean
local function samePoint(first, second)
    return first and second and first.page == second.page and first.x == second.x and first.y == second.y
end

---@param item table
---@param page integer
---@param first table
---@param last table
---@return table[]|nil
local function exactBoxes(item, page, first, last)
    local saved = item.zotero_pdf_geometry
    if not saved or not samePoint(item.pos0, saved.pos0) or not samePoint(item.pos1, saved.pos1) then return end
    local part = saved.ext and (saved.ext[page] or saved.ext[tostring(page)]) or saved
    if not part or not samePoint(part.pos0, first) or not samePoint(part.pos1, last) then return end
    local boxes = {}
    for _, box in ipairs(part.pboxes or {}) do boxes[#boxes + 1] = Geom:new(Helpers.copy(box)) end
    return boxes
end

--- Preserve imported rectangles when native word/OCR snapping would expand or clip them.
--- Bind the document instance only; unrelated selections still use KOReader's method.
---@param reader table
function PDFView.bind(reader)
    if not reader.paging or not reader.document.getPageBoxesFromPositions then return end
    local document = reader.document
    local original = document.zotero_original_boxes or document.getPageBoxesFromPositions
    document.zotero_original_boxes = original
    document.getPageBoxesFromPositions = function(current, page, first, last)
        if current.configurable.text_wrap ~= 1 then
            for _, item in ipairs(reader.annotation.annotations) do
                local boxes = exactBoxes(item, page, first, last)
                if boxes then return boxes end
            end
        end
        return original(current, page, first, last)
    end
end

--- Restore the native provider at document close. Example: PDFView.unbind(reader).
---@param reader table
function PDFView.unbind(reader)
    local document = reader.document
    if document and document.zotero_original_boxes then
        document.getPageBoxesFromPositions = document.zotero_original_boxes
        document.zotero_original_boxes = nil
    end
end

--- Keep exact geometry as plugin-owned provenance; resize edits invalidate it automatically.
---@param item table
function PDFView.remember(item)
    if not item.pboxes then return end
    item.zotero_pdf_geometry = { pos0 = Helpers.copy(item.pos0), pos1 = Helpers.copy(item.pos1),
        pboxes = Helpers.copy(item.pboxes), ext = item.ext and Helpers.copy(item.ext) or nil }
end

return PDFView
