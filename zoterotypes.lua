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
---@field on_device boolean|nil
---@field destination 'collection'|'all'|'device'|nil
---@field continue_reading boolean|nil
---@field search boolean|nil
---@field subtitle string|nil

---@class ZoteroRecentDocument
---@field key string
---@field path string
---@field title string

---@class ZoteroBrowserView
---@field kind 'home'|'all'|'collection'|'search'|'device'
---@field key string|nil
---@field query string|nil
---@field page integer|nil

---@class ZoteroBrowserPosition
---@field view ZoteroBrowserView
---@field paths ZoteroBrowserView[]

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
---@field sync_job table|nil Background library sync shared by plugin instances

return {}
