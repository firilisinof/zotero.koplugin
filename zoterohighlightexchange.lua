local Helpers = require("zoterohighlightutil")
local Remote = require("zoterohighlightremote")
local Merge = require("zoterohighlightmerge")
local Codec = require("zoterohighlightcodec")
local Exchange = {}

---@param codec table
---@param entries table
---@param items table
---@return table
local function classify(codec, entries, items)
    local used, candidates = {}, {}
    for _, entry in pairs(entries) do used[entry.key] = true end
    for key, item in pairs(items) do
        local fields = item.data
        if not used[key] and not fields.annotationIsExternal and fields.itemType == "annotation" and
            (fields.annotationType == "highlight" or fields.annotationType == "underline") then
            local ok, value = pcall(codec.remote, codec, item)
            candidates[key] = { value = ok and value or nil, error = not ok and tostring(value) or nil }
        end
    end
    return candidates
end

---@param codec table
---@param entries table
local function localDuplicates(codec, entries)
    local order, seen = {}, {}
    for id in pairs(entries) do order[#order + 1] = id end
    table.sort(order, function(a, b)
        if (entries[a].base ~= false) ~= (entries[b].base ~= false) then return entries[a].base ~= false end
        return a < b
    end)
    for _, id in ipairs(order) do
        local entry = entries[id]
        local ok, value = pcall(codec.encode, codec, entry.native)
        if ok and value ~= false then
            for _, prior in ipairs(seen) do
                if entry.base == false and Helpers.equal(prior, value) then
                    entry.error = "Duplicate local highlight preserved; remove the extra copy to share it"
                end
            end
            seen[#seen + 1] = value
        end
    end
end

---@param codec table
---@param entries table
---@param candidates table
local function adopt(codec, entries, candidates)
    for _, entry in pairs(entries) do
        if not entry.error and entry.base == false and entry.native ~= false then
            local ok, local_value = pcall(codec.encode, codec, entry.native)
            local matches = {}
            if ok then
                for key, candidate in pairs(candidates) do
                    if Helpers.equal(candidate.value, local_value) then matches[#matches + 1] = key end
                end
            end
            if #matches == 1 then
                entry.key = matches[1]; candidates[matches[1]] = nil
            elseif #matches > 1 then
                entry.error = "Multiple identical Zotero highlights; resolve duplicates in Zotero first"
                for _, key in ipairs(matches) do candidates[key] = nil end
            end
        end
    end
end

--- Leave ambiguous desktop copies untouched until their owner removes the extras.
---@param context table
---@param entries table
---@param candidates table
local function remoteDuplicates(context, entries, candidates)
    local values = {}
    for key, candidate in pairs(candidates) do values[key] = candidate.value end
    for _, entry in pairs(entries) do
        local item = context.items[entry.key]
        if item then
            local ok, value = pcall(context.codec.remote, context.codec, item)
            if ok then values[entry.key] = value end
        end
    end
    for key, candidate in pairs(candidates) do
        if candidate.value then
            for other_key, value in pairs(values) do
                if key ~= other_key and Helpers.equal(candidate.value, value) then
                    candidate.error = "Duplicate Zotero highlight preserved; remove the extra copy before importing"
                end
            end
        end
    end
end

---@param context table
---@param entry table
---@param current table|nil
---@param remote table|boolean
---@param merged table|boolean
local function push(context, entry, current, remote, merged)
    if Helpers.equal(merged, remote) then return end
    local fields = context.codec:fields(merged)
    if current and merged ~= false then
        -- Presentation labels and extension metadata are owned by Zotero.
        fields.annotationPageLabel, fields.annotationSortIndex = nil, nil
        if Helpers.equal(merged.position, remote ~= false and remote.position) then fields.annotationPosition = nil end
        if current.data.deleted == 1 or current.data.deleted == true then fields.deleted = 0 end
    end
    current = Remote.write(context.api, context.secret, context.snapshot.identity, entry, current, fields)
    assert(Helpers.equal(context.codec:remote(current), merged), "Annotation changed during confirmation; retry")
end

---@param context table
---@param entry table
local function reconcile(context, entry)
    local codec, snapshot = context.codec, context.snapshot
    local current = context.items[entry.key] or Remote.get(context.api, context.secret, snapshot.identity, entry.key)
    local remote = current and codec:remote(current) or false
    local local_value = codec:encode(entry.native)
    local merged, conflicts = Merge.choose(entry, local_value, remote)
    if merged == nil then
        entry.conflict = { fields = conflicts, local_value = local_value, remote = remote }
        entry.resolution = nil; return
    end
    push(context, entry, current, remote, merged)
    if not Helpers.equal(local_value, merged) then entry.native = codec:decode(merged) end
    entry.base, entry.conflict, entry.resolution, entry.error = merged, nil, nil, nil
end

---@param context table
---@param entries table
---@return table
local function importCandidates(context, entries)
    local candidates = classify(context.codec, entries, context.items)
    localDuplicates(context.codec, entries)
    adopt(context.codec, entries, candidates)
    remoteDuplicates(context, entries, candidates)
    local warnings = {}
    for key, candidate in pairs(candidates) do
        if candidate.error then warnings[#warnings + 1] = candidate.error
        elseif candidate.value then
            local id = "remote-" .. key
            entries[id] = { key = key, native = false, base = false }
        end
    end
    return warnings
end

---@param context table
---@return table
local function run(context)
    Remote.verify(context.api, context.secret, context.snapshot.identity)
    context.items = Remote.list(context.api, context.secret, context.snapshot.identity)
    local entries = Helpers.copy(context.snapshot.entries)
    for _, entry in pairs(entries) do entry.error = nil end
    local warnings = importCandidates(context, entries)
    for _, entry in pairs(entries) do
        if not entry.error then
            local ok, err = pcall(reconcile, context, entry)
            if not ok then
                if type(err) == "table" then return { entries = entries, error = err.error, delay = err.delay, paused = err.paused } end
                entry.error = tostring(err)
            end
        end
    end
    return { entries = entries, warnings = warnings }
end

--- Perform conversion and network work in the existing cancellable subprocess.
---@param api ZoteroAPI
---@param secret string
---@param snapshot table
---@return table
function Exchange.run(api, secret, snapshot)
    local codec
    local ok, result = pcall(function()
        codec = Codec.open(snapshot.identity, snapshot.dom_version, snapshot.pdf_matrices, snapshot.scratch)
        return run({ api = api, secret = secret, snapshot = snapshot, codec = codec })
    end)
    if codec then
        if ok and codec.pdf then result.pdf_matrices = codec.pdf.matrices end
        codec:close()
    end
    if ok then return result end
    return type(result) == "table" and result or { error = tostring(result), delay = 60 }
end

return Exchange
