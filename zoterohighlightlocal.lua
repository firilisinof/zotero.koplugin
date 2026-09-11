local Helpers = require("zoterohighlightutil")
local Local = {}

---@param item table
local function preparePDF(item)
    if type(item.pos0) ~= "table" then return end
    if item.ext then
        local pages = {}
        for page, part in pairs(item.ext) do pages[tonumber(page)] = part end
        item.ext = pages
    end
    require("zoterohighlightpdfview").remember(item)
end

---@param item table
---@param record table
---@param seen table
---@return boolean
local function captureItem(item, record, seen)
    local id, changed = item.zotero_highlight_id, false
    if not Helpers.supported(item) and not (id and record.entries[id]) then return false end
    if not id or seen[id] then id = Helpers.key() .. Helpers.key(); item.zotero_highlight_id = id; changed = true end
    seen[id] = true
    local entry = record.entries[id]
    if not entry then
        entry = { key = Helpers.key(), native = false, base = false }
        record.entries[id] = entry
    end
    local native = Helpers.native(item)
    if type(item.pos0) == "table" and entry.base ~= false and not item.zotero_pdf_geometry
        and Helpers.equal(entry.native, native) then preparePDF(item); changed = true end
    if not Helpers.equal(entry.native, native) then entry.native = native; changed = true end
    return changed
end

--- Assign durable IDs only to shared text markup. Example: Local.capture(reader, record).
---@param reader table
---@param record table
---@return boolean
function Local.capture(reader, record)
    local seen, changed = {}, false
    for _, item in ipairs(reader.annotation.annotations) do changed = captureItem(item, record, seen) or changed end
    for id, entry in pairs(record.entries) do
        if not seen[id] and entry.native ~= false then entry.native = false; changed = true end
    end
    return changed
end

--- Compare just native state for a crash-safe delivery, independent of sync metadata.
---@param entries table
---@param expected table
---@return boolean
function Local.matches(entries, expected)
    for id, entry in pairs(entries) do
        if not Helpers.equal(entry.native, expected[id] and expected[id].native or false) then return false end
    end
    for id, entry in pairs(expected) do
        if not Helpers.equal(entry.native, entries[id] and entries[id].native or false) then return false end
    end
    return true
end

--- Flush the annotation table only; never export or write markup into the PDF file.
---@param reader table
function Local.save(reader)
    reader.doc_settings:saveSetting("annotations", reader.annotation.annotations)
    assert(reader.doc_settings:flush(), "Could not flush highlight annotations to the document sidecar")
end

---@param reader table
---@param item table
---@param native table
local function updateItem(reader, item, native)
    for _, field in ipairs({ "pos0", "pos1", "pboxes", "ext", "drawer", "color", "text", "note", "note_format" }) do
        item[field] = native[field] ~= nil and Helpers.copy(native[field]) or nil
    end
    item.page = reader.paging and item.pos0.page or item.pos0
    preparePDF(item)
end

---@param reader table
---@param after table
---@return table
local function updateExisting(reader, after)
    local annotations, found = reader.annotation.annotations, {}
    for i = #annotations, 1, -1 do
        local item = annotations[i]
        local id = item.zotero_highlight_id
        local entry = id and after[id]
        if entry then
            found[id] = true
            if entry.native == false then table.remove(annotations, i)
            elseif not Helpers.equal(Helpers.native(item), entry.native) then
                updateItem(reader, item, entry.native)
            end
        end
    end
    return found
end

--- Apply a journal while preserving unrelated fields. Example: Local.apply(reader, before, after, runtime).
---@param reader table
---@param before table
---@param after table
---@param runtime table
function Local.apply(reader, before, after, runtime)
    local annotations, found = reader.annotation.annotations, updateExisting(reader, after)
    for id, entry in pairs(after) do
        if not found[id] and entry.native ~= false then
            local item = Helpers.copy(entry.native)
            item.zotero_highlight_id, item.datetime = id, os.date("%Y-%m-%d %H:%M:%S")
            item.page = reader.paging and item.pos0.page or item.pos0
            preparePDF(item)
            annotations[#annotations + 1] = item
        end
    end
    reader.annotation:updateAnnotations(true, true)
    Local.save(reader)
    runtime:refreshHighlights(reader)
end

return Local
