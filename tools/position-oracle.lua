-- Real crengine half of the independent Zotero interoperability check.
require("setupkoenv")
local root = assert(os.getenv("KO_HOME"))
assert(root:match("^/tmp/") or root:match("^/private/tmp/"), "Oracle requires temporary KO_HOME")
G_defaults = require("luadefaults"):open(root .. "/defaults.lua")
G_reader_settings = require("luasettings"):open(root .. "/settings.reader.lua")
local Device = require("device")
require("document/canvascontext"):init(Device)
require("ui/bidi").setup()
local plugin = assert(os.getenv("ZOTERO_PLUGIN_ROOT"))
package.path = plugin .. "/?.lua;" .. package.path
local Util = require("zoteroutil")
local fixture = plugin .. "/spec/fixtures/positions/"
local source = Util.decode(assert(Util.read(fixture .. "source.json")))
local name = os.getenv("ZOTERO_ORACLE_FIXTURE") or "sample.epub"
local doc = assert(require("document/documentregistry"):openDocument(fixture .. name))
local version = tonumber(os.getenv("ZOTERO_DOM_VERSION")) or doc:getLatestDomVersion()
doc:requestDomVersion(version)
assert(doc:loadDocument())
doc:render()
local codec = require("zoteroepub").new(doc, version)
for _, case in ipairs(source.cases) do
    case.spine = case.section + 1
    if name == "mixed.epub" and case.section == 1 then
        case.spine = 3
        if version >= 20240114 then case.pointer = case.pointer:gsub("DocFragment%[2%]", "DocFragment[3]") end
    end
    local cfi, err = codec:encode(case.pointer)
    assert(cfi, err)
    case.cfi, case.text = cfi, doc:getTextFromXPointer(case.pointer)
end
local incoming = Util.read(root .. "/incoming.json")
if incoming then
    for i, cfi in ipairs(Util.decode(incoming)) do
        local pointer, err = codec:decode(cfi)
        assert(pointer, err)
        local expected = source.cases[i]
        assert(doc:getTextFromXPointer(pointer) == expected.text, "Different native passage")
        assert(codec:encode(pointer) == expected.cfi, "Different native character boundary")
        assert(codec:decode(cfi:match("^epubcfi%((.*)%)$")), "Bare synced CFI could not be decoded")
    end
end
-- Exact endpoint pairs exercise the same path later used by highlights.
source.range_text = doc:getTextFromXPointers(source.cases[3].pointer, source.cases[4].pointer)
source.dom_version = version
assert(not Util.write(root .. "/outgoing.json", Util.encode(source)))
doc:close()
Device:exit()
print("CRENGINE POSITION ORACLE PASS")
