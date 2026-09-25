-- Explicit live probe: the manifest must contain only dedicated original fixtures.
require("setupkoenv")
local root = assert(os.getenv("KO_HOME"))
assert(root:match("^/tmp/"), "Live probe requires temporary KO_HOME")
G_defaults = require("luadefaults"):open(root .. "/defaults.lua")
G_reader_settings = require("luasettings"):open(root .. "/settings.reader.lua")
local Device = require("device")
require("document/canvascontext"):init(Device)
require("ui/bidi").setup()
local plugin = assert(os.getenv("ZOTERO_PLUGIN_ROOT"))
package.path = plugin .. "/?.lua;" .. package.path
local api = require("zoteroapi")
local manifest = api.util.decode(assert(api.util.read(assert(os.getenv("ZOTERO_POSITION_MANIFEST")))))
assert(not manifest.cleaned and manifest.test_id, "Expected active test fixture manifest")
local credentials = require("luasettings"):open(assert(os.getenv("ZOTERO_TEST_CREDENTIALS")))
local key = assert(credentials:readSetting("api_key"))
local Remote = require("zoteroprogressremote")
local authorization = Remote.authorize(api, key)
assert(not authorization.error, authorization.error)
assert(authorization.owner == manifest.owner, "Test fixture account mismatch")
local Registry = require("document/documentregistry")
local EPUB = require("zoteroepub")
local read_only = os.getenv("ZOTERO_POSITION_READ_ONLY") == "1"
for _, entry in ipairs(manifest.items) do
    assert(require("zoteroprogressidentity").checksum(entry.path, true) == entry.md5, "Test fixture changed")
    local identity = { owner = manifest.owner, library = "users/" .. manifest.owner, key = entry.key, md5 = entry.md5 }
    local doc = assert(Registry:openDocument(entry.path))
    local codec, value
    if entry.format == "application/pdf" then
        assert(doc:getPageCount() == 3); value = 2
    else
        doc:requestDomVersion(20260812); assert(doc:loadDocument()); doc:render()
        codec = EPUB.new(doc, 20260812)
        value = assert(codec:encode("/body/DocFragment[2]/body/p/text().20"))
        value = value:match("^epubcfi%((.*)%)$")
    end
    local result = Remote.exchange(api, key, { identity = identity, value = value, pending = not read_only })
    assert(not result.error, result.error)
    if read_only then
        if codec then
            local pointer, reason = codec:decode(result.value)
            assert(pointer, reason)
            assert(doc:isXPointerInDocument(pointer))
            print("LIVE EPUB PULL", pointer, doc:getTextFromXPointer(pointer))
        else
            assert(type(result.value) == "number" and result.value >= 0 and result.value < 3)
            print("LIVE PDF PULL physical page", result.value + 1)
        end
    else
        assert(result.pushed and result.value == value)
        print("LIVE POSITION PUSH PASS", entry.format, "setting version", result.version)
    end
    doc:close()
end
Device:exit()
print("LIVE POSITION TRANSPORT PASS")
