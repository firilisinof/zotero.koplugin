-- Coordinate calibration uses only KOReader's protected MuPDF API. Some builds
-- hide pdf_page_transform. A private in-memory document serializes a known quad
-- into a scratch PDF; its PDF-space corners give the exact affine transform.
-- Never save the reader document or the source attachment.
local PDF = {}
PDF.__index = PDF

--- Adapt installed MuPDF without new native symbols. Example: PDF.new(document, cache).
---@param document table
---@param cache table|nil
---@param scratch string|nil
---@return table
function PDF.new(document, cache, scratch)
    return setmetatable({ document = document, matrices = cache or {}, scratch = scratch }, PDF)
end

---@return table
function PDF:probeDocument()
    if not self.probe then
        self.probe = require("ffi/mupdf").openDocument(self.document.file)
        self.scratch = self.scratch or os.tmpname()
    end
    return self.probe
end

--- Release scratch calibration state; no user annotation is ever embedded.
function PDF:close()
    if self.probe then self.probe:close(); self.probe = nil end
    if self.scratch then os.remove(self.scratch); self.scratch = nil end
end

---@param page table
---@return string
local function insertCalibration(page)
    local quad = require("ffi").new("fz_quad[1]")
    quad[0].ul.x, quad[0].ul.y = 0, 0
    quad[0].ur.x, quad[0].ur.y = 100, 0
    quad[0].ll.x, quad[0].ll.y = 0, 100
    quad[0].lr.x, quad[0].lr.y = 100, 100
    page:addMarkupAnnotation(quad, 1, 8)
    local annotation = assert(page:getMarkupAnnotation(quad, 1), "Missing scratch calibration annotation")
    local marker = "ZoteroCalibration" .. require("zoterohighlightutil").key() .. require("zoterohighlightutil").key()
    page:updateMarkupAnnotation(annotation, marker)
    return marker
end

---@param scratch string
---@param marker string
---@return number[]
local function readCalibration(scratch, marker)
    local file = assert(io.open(scratch, "rb"))
    local size = file:seek("end"); file:seek("set", math.max(0, size - 4 * 1024 * 1024))
    local tail = file:read("*a"); file:close()
    local coordinates
    for object in tail:gmatch("%d+%s+%d+%s+obj%s*(.-)%s*endobj") do
        if object:find(marker, 1, true) then coordinates = object:match("/QuadPoints%s*%[([^%]]+)%]"); break end
    end
    assert(coordinates, "Could not read MuPDF scratch calibration quad")
    local values = {}
    for token in coordinates:gmatch("%S+") do values[#values + 1] = assert(tonumber(token), "Invalid calibration coordinate " .. token) end
    assert(#values == 8, "Expected eight calibration coordinates")
    return values
end

--- Calibrate without relying on unexported native symbols. Example: pdf:calibrate(1).
---@param page_number integer
---@return number[]
function PDF:calibrate(page_number)
    local probe = self:probeDocument()
    local page = probe:openPage(page_number)
    local marker = insertCalibration(page)
    probe:writeDocument(self.scratch); page:close()
    local values = readCalibration(self.scratch, marker)
    local inverse = { (values[3] - values[1]) / 100, (values[4] - values[2]) / 100,
        (values[5] - values[1]) / 100, (values[6] - values[2]) / 100, values[1], values[2] }
    return PDF.inverse(inverse)
end

--- Obtain and cache the actual CropBox/Rotate/UserUnit transform in the worker.
---@param page_number integer
---@return number[]
function PDF:matrix(page_number)
    assert(type(page_number) == "number" and page_number % 1 == 0 and page_number >= 1
        and page_number <= self.document:getPageCount(), "Invalid PDF page " .. tostring(page_number))
    local key = tostring(page_number)
    if not self.matrices[key] then self.matrices[key] = self:calibrate(page_number) end
    return self.matrices[key]
end

--- Invert a nonsingular affine transform. Example: PDF.inverse(matrix).
---@param m number[]
---@return number[]
function PDF.inverse(m)
    local determinant = m[1] * m[4] - m[2] * m[3]
    assert(math.abs(determinant) > 1e-10, "Expected nonsingular PDF page transform")
    return { m[4] / determinant, -m[2] / determinant, -m[3] / determinant, m[1] / determinant,
        (m[3] * m[6] - m[4] * m[5]) / determinant, (m[2] * m[5] - m[1] * m[6]) / determinant }
end

--- Transform all corners; rotation can exchange width and height. Example: PDF.rect(rect, matrix).
---@param rect number[]
---@param matrix number[]
---@return number[]
function PDF.rect(rect, matrix)
    assert(type(rect) == "table" and #rect == 4, "Expected PDF rectangle with four coordinates")
    for _, n in ipairs(rect) do assert(type(n) == "number" and n == n and math.abs(n) < 1e8, "Invalid PDF coordinate " .. tostring(n)) end
    assert(rect[3] > rect[1] and rect[4] > rect[2], "Expected positive PDF rectangle area")
    local bounds = { math.huge, math.huge, -math.huge, -math.huge }
    for _, point in ipairs({ {rect[1],rect[2]}, {rect[1],rect[4]}, {rect[3],rect[2]}, {rect[3],rect[4]} }) do
        local x = matrix[1] * point[1] + matrix[3] * point[2] + matrix[5]
        local y = matrix[2] * point[1] + matrix[4] * point[2] + matrix[6]
        bounds = { math.min(bounds[1], x), math.min(bounds[2], y), math.max(bounds[3], x), math.max(bounds[4], y) }
    end
    for i, n in ipairs(bounds) do bounds[i] = math.floor(n * 1000 + 0.5) / 1000 end
    return bounds
end

--- Encode native inclusive pboxes in unrotated PDF coordinates. Example: pdf:encodeBoxes(1, boxes).
---@param page integer
---@param boxes table[]
---@return table[]
function PDF:encodeBoxes(page, boxes)
    assert(type(boxes) == "table" and #boxes > 0, "Expected nonempty PDF highlight pboxes")
    local matrix, rects = PDF.inverse(self:matrix(page)), {}
    for _, box in ipairs(boxes) do
        rects[#rects + 1] = PDF.rect({ box.x, box.y, box.x + box.w - 1, box.y + box.h - 1 }, matrix)
    end
    return rects
end

--- Decode Zotero rectangles without changing zoom or writing embedded PDF markup.
---@param page integer
---@param rects table[]
---@return table
function PDF:decodeBoxes(page, rects)
    assert(type(rects) == "table" and #rects > 0, "Expected nonempty Zotero PDF rects")
    local matrix, boxes = self:matrix(page), {}
    for _, rect in ipairs(rects) do
        local r = PDF.rect(rect, matrix)
        boxes[#boxes + 1] = { x = r[1], y = r[2], w = r[3] - r[1] + 1, h = r[4] - r[2] + 1 }
    end
    local first, last = boxes[1], boxes[#boxes]
    return { pboxes = boxes, pos0 = { page = page, x = first.x + 0.5, y = first.y + 0.5, zoom = 1, rotation = 0 },
        pos1 = { page = page, x = last.x + last.w - 1.5, y = last.y + last.h - 1.5, zoom = 1, rotation = 0 } }
end

return PDF
