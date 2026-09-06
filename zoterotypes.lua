-- Shared LuaLS annotations. This file contains no runtime state.
---@class ZoteroItem
---@field key string
---@field version number
---@field data table
---@field meta table|nil

---@class ZoteroRow
---@field key string
---@field text string
---@field title string|nil Publication or attachment title, falling back to the filename
---@field author string|nil
---@field year string|nil
---@field file_format 'PDF'|'EPUB'|nil
---@field downloadable boolean|nil
---@field haystack string|nil
---@field collection boolean|nil
---@field downloaded boolean|nil

---@class ZoteroIndex
---@field by_collection table<string, ZoteroRow[]>
---@field searchable ZoteroRow[]

---@class ZoteroDownloadSummary
---@field total integer
---@field downloaded integer
---@field skipped integer
---@field failed integer
---@field cancelled integer
---@field errors ZoteroRow[]

---@class ZoteroAPI
---@field util table
---@field settings LuaSettings
---@field http table
---@field zotero_dir string
---@field storage_dir string
---@field index ZoteroIndex|nil
---@field operation string|nil

return {}
