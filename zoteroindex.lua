local Index = {}

---@param entry ZoteroRow
---@return ZoteroRow
local function copyRow(entry)
    local row = {}
    for field, value in pairs(entry) do row[field] = value end
    return row
end

---@param value string|nil
---@return string|nil
local function nonempty(value)
    if type(value) == "string" and value:find("%S") then return value end
end

---@param owner ZoteroItem
---@return string|nil
local function publicationYear(owner)
    local parsed = nonempty(owner.meta and owner.meta.parsedDate)
    local date = parsed or nonempty(owner.data.date)
    return date and date:match("%f[%d](%d%d%d%d)%f[%D]")
end

---@param key string
---@param item ZoteroItem
---@param parent ZoteroItem|nil
---@return ZoteroRow
local function attachmentRow(key, item, parent)
    local owner = parent or item
    return {
        key = key,
        title = nonempty(parent and parent.data.title) or nonempty(item.data.title) or nonempty(item.data.filename),
        author = nonempty(owner.meta and owner.meta.creatorSummary),
        year = publicationYear(owner),
        file_format = item.data.contentType == "application/pdf" and "PDF" or "EPUB",
        downloadable = item.data.linkMode ~= "linked_file",
    }
end

---@param item ZoteroItem|nil
---@return boolean
local function readable(item)
    local fields = item and item.data
    if not fields or fields.itemType ~= "attachment" then return false end
    return fields.contentType == "application/pdf" or fields.contentType == "application/epub+zip"
end

---@param item ZoteroItem
---@param tag string
---@return boolean
local function matchesTag(item, tag)
    if tag == "" then return true end
    for _, entry in ipairs(item.data.tags or {}) do
        if entry.tag == tag then return true end
    end
    return false
end

---@param parent ZoteroItem
---@return string
local function nameFor(parent)
    local author = (parent.meta and parent.meta.creatorSummary) or "Unknown"
    return author .. " - " .. tostring(parent.data.title)
end

---@param lists table<string, ZoteroRow[]>
---@param collections string[]|nil
---@param row ZoteroRow
local function fileUnder(lists, collections, row)
    for _, key in ipairs(collections or {}) do
        lists[key] = lists[key] or {}
        table.insert(lists[key], row)
    end
end

---@param index ZoteroIndex
---@param key string
---@param item ZoteroItem
---@param parent ZoteroItem|nil
local function indexAttachment(index, key, item, parent)
    local row = attachmentRow(key, item, parent)
    -- Keep legacy ordering and ordered author/title/DOI matching independent of layout.
    local title = parent and nameFor(parent) or nonempty(item.data.title) or row.title or key
    local owner = parent or item
    row.text = title
    if parent or not item.data.parentItem then
        fileUnder(index.by_collection, owner.data.collections, row)
    end
    -- Only search includes the DOI in matching and ordering. Orphans use their own title.
    local doi = parent and parent.data.DOI
    if doi and doi ~= "" then title = title .. " - " .. doi end
    local search_row = copyRow(row)
    search_row.text, search_row.haystack = title, string.lower(title)
    table.insert(index.searchable, search_row)
end

---@param first ZoteroRow
---@param second ZoteroRow
---@return boolean
local function byText(first, second)
    if first.text == second.text then return first.key < second.key end
    return first.text < second.text
end

-- Walk the library once instead of rescanning every item on every render.
---@param api ZoteroAPI
---@return ZoteroIndex
local function buildIndex(api)
    local items = api.getItems()
    local index = { by_collection = {}, searchable = {} }
    for key, item in pairs(items) do
        local parent = item.data and items[item.data.parentItem]
        if parent and not parent.data then parent = nil end
        if readable(item) and matchesTag(parent or item, api.getFilterTag()) then
            indexAttachment(index, key, item, parent)
        end
    end
    for _, entries in pairs(index.by_collection) do table.sort(entries, byText) end
    table.sort(index.searchable, byText)
    return index
end

--- Return lazily cached attachment lookups. Example: API.getIndex().searchable.
---@param api ZoteroAPI
---@return ZoteroIndex
function Index.getIndex(api)
    if not api.index then api.index = buildIndex(api) end
    return api.index
end

---@param api ZoteroAPI
---@param entry ZoteroRow
---@return ZoteroRow
local function displayRow(api, entry)
    -- File presence changes independently of metadata, including in subprocesses.
    local _, path = api.getDirAndPath(entry.key)
    local row = copyRow(entry)
    row.haystack = nil
    row.downloaded = api.util.isFile(path)
    return row
end

---@param api ZoteroAPI
---@param key string|nil
---@return ZoteroRow[]
local function collectionRows(api, key)
    local result = {}
    for collection_key, collection in pairs(api.getCollections()) do
        local parent = collection.data.parentCollection
        if (key == nil and parent == false) or (key ~= nil and parent == key) then
            table.insert(result, { key = collection_key, text = collection.data.name .. "/", collection = true })
        end
    end
    table.sort(result, byText)
    return result
end

--- List child collections followed by attachments. Example: API.displayCollection("ABCD1234").
---@param api ZoteroAPI
---@param key string|nil
---@return ZoteroRow[]
function Index.displayCollection(api, key)
    local result = collectionRows(api, key)
    if not key then return result end
    -- Hand back copies because the browser inserts its own rows and adds presentation fields.
    for _, entry in ipairs(api.getIndex().by_collection[key] or {}) do
        table.insert(result, displayRow(api, entry))
    end
    return result
end

--- Escape words and match them in order. Example: API.buildSearchPattern("Ben-Kiki YAML").
---@param api ZoteroAPI
---@param query string
---@return string
function Index.buildSearchPattern(api, query)
    local words = {}
    for word in string.gmatch(string.lower(query), "%S+") do
        table.insert(words, (word:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")))
    end
    -- Lua patterns are already unanchored. A leading .* makes the matcher retry
    -- from every position and used to cost about twenty times as much.
    return table.concat(words, ".*")
end

--- Search titles, first authors and DOIs. Example: API.displaySearchResults("attention").
---@param api ZoteroAPI
---@param query string
---@return ZoteroRow[]
function Index.displaySearchResults(api, query)
    local pattern = api.buildSearchPattern(query)
    local result = {}
    for _, entry in ipairs(api.getIndex().searchable) do
        if string.match(entry.haystack, pattern) then table.insert(result, displayRow(api, entry)) end
    end
    return result
end

--- Read a publication's child notes from the cache. Example: API.getItemNotes("ATTACH01").
---@param api ZoteroAPI
---@param attachment_key string
---@return ZoteroRow[]
function Index.getItemNotes(api, attachment_key)
    local items = api.getItems()
    local attachment = items[attachment_key]
    local parent_key = attachment and attachment.data and attachment.data.parentItem
    if not parent_key or not items[parent_key] then return {} end
    local notes = {}
    for key, item in pairs(items) do
        local fields = item.data or {}
        if fields.itemType == "note" and fields.parentItem == parent_key
            and fields.deleted ~= true and fields.deleted ~= 1 and type(fields.note) == "string" then
            table.insert(notes, { key = key, text = api.util.plainText(fields.note) })
        end
    end
    table.sort(notes, function(a, b) return a.key < b.key end)
    return notes
end

return Index
