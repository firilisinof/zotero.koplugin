local Helpers = require("zoterohighlightutil")
local util = require("util")
local Merge = {}

--- Three-way field merge. Deletion versus editing and overlapping edits stay unresolved.
---@param base table|boolean
---@param local_value table|boolean
---@param remote table|boolean
---@return table|boolean|nil, string[]|nil
function Merge.values(base, local_value, remote)
    if Helpers.equal(local_value, remote) then return util.tableDeepCopy(local_value) end
    if Helpers.equal(local_value, base) then return util.tableDeepCopy(remote) end
    if Helpers.equal(remote, base) then return util.tableDeepCopy(local_value) end
    if base == false or local_value == false or remote == false then return nil, { "creation or deletion" } end
    local merged, conflicts = {}, {}
    for _, field in ipairs({ "text", "comment", "color", "kind", "position" }) do
        local result = local_value[field]
        if Helpers.equal(result, base[field]) then result = remote[field]
        elseif not Helpers.equal(remote[field], base[field]) and not Helpers.equal(remote[field], result) then
            conflicts[#conflicts + 1] = field
        end
        merged[field] = util.tableDeepCopy(result)
    end
    if #conflicts > 0 then return nil, conflicts end
    return merged
end

--- Resolve a saved choice only against the exact remote revision the user reviewed.
---@param entry table
---@param local_value table|boolean
---@param remote table|boolean
---@return table|boolean|nil, string[]|nil
function Merge.choose(entry, local_value, remote)
    local choice = entry.resolution
    if choice and Helpers.equal(choice.remote, remote) and Helpers.equal(choice.local_value, local_value) then
        if choice.side == "local" then return util.tableDeepCopy(local_value) end
        return util.tableDeepCopy(remote)
    end
    return Merge.values(entry.base, local_value, remote)
end

return Merge
