local util = require("util")
local Registry = require("document/documentregistry")
local Reader = {}
Reader.__index = Reader

function Reader.new(path, kind)
    local document = assert(Registry:openDocument(path))
    if kind == "epub" then document:requestDomVersion(20260812); assert(document:loadDocument()); document:render() end
    local self = setmetatable({ document = document, saved = 0 }, Reader)
    self[kind == "epub" and "rolling" or "paging"] = {}
    self.doc_settings = require("docsettings"):open(path)
    self.doc_settings:saveSetting("cre_dom_version", 20260812)
    self.annotation = { annotations = {}, updateAnnotations = function() self.saved = self.saved + 1 end }
    return self
end
function Reader:close() self.document:close() end
function Reader:highlight(kind)
    local item = { text = "Alpha", color = "yellow", drawer = "lighten", datetime = "2026-09-11 10:00:00" }
    if kind == "epub" then
        item.pos0, item.pos1 = "/body/DocFragment[1]/body/p[1]/text().0", "/body/DocFragment[1]/body/p[1]/text().5"
        item.page = item.pos0
    else
        item.pos0, item.pos1 = { page = 1, x = 73, y = 65 }, { page = 1, x = 100, y = 80 }
        item.pboxes, item.page = { { x = 72, y = 64, w = 30, h = 18 } }, 1
    end
    self.annotation.annotations[#self.annotation.annotations + 1] = item
    return item
end
function Reader:bookmark(kind)
    local item = { text = "unrelated bookmark", page = kind == "epub" and "/body/DocFragment[1]/body/p[1]/text().0" or 2 }
    self.annotation.annotations[#self.annotation.annotations + 1] = item
    return util.tableDeepCopy(item)
end
return Reader
