-- Controlled ReaderUI handoff. Only manifest-listed original fixtures are opened.
require("setupkoenv")
local root = assert(os.getenv("KO_HOME"))
assert(root:match("^/tmp/"), "Live highlight test requires temporary KO_HOME")
G_defaults = require("luadefaults"):open(root .. "/defaults.lua")
G_reader_settings = require("luasettings"):open(root .. "/settings.reader.lua")
local Device = require("device")
require("document/canvascontext"):init(Device)
require("ui/bidi").setup()
local plugin_root = assert(os.getenv("ZOTERO_PLUGIN_ROOT"))
package.path = plugin_root .. "/?.lua;" .. package.path
local api = require("zoteroapi")
local manifest = api.util.decode(assert(api.util.read(assert(os.getenv("ZOTERO_HIGHLIGHT_MANIFEST")))))
assert(manifest.test_id and not manifest.cleaned, "Expected active dedicated test manifest")
local secret = require("luasettings"):open(assert(os.getenv("ZOTERO_TEST_CREDENTIALS"))):readSetting("api_key")
api.util.mkdir(root .. "/zotero"); api.init(root .. "/zotero")
api.setAccount("user", manifest.owner, secret)
local Remote = require("zoterohighlightremote")
local Identity = require("zoteroprogressidentity")
local auth = Remote.authorize(api, secret, "users/" .. manifest.owner)
auth.key_hash = Identity.keyHash(secret)
api.settings:saveSetting("highlight_authorization", auth)
api.settings:saveSetting("share_highlights", true)
local phase = os.getenv("ZOTERO_HIGHLIGHT_PHASE") or "push"
local items = {}
for _, fixture in ipairs(manifest.items) do
    assert(Identity.checksum(fixture.path, true) == fixture.md5, "Original fixture changed")
    local response = Remote.request(api, secret, auth.library .. "/items/" .. fixture.key)
    assert(response.code == 200 and response.body.data.title:match("^Highlight sync test "), "Refusing a non-test attachment")
    assert(response.body.data.md5 == fixture.md5, "Remote test content differs")
    items[fixture.key] = response.body
end
api.setItems(items); api.saveModifiedItems()
for _, fixture in ipairs(manifest.items) do
    local directory, path = api.getDirAndPath(fixture.key)
    api.util.mkdir(directory)
    if not api.util.read(path) then assert(not api.util.write(path, assert(api.util.read(fixture.path)))) end
    fixture.local_path = path
end
local UIManager = require("ui/uimanager")
local Runtime = require("zoteroui")
local runtime = setmetatable({ online = true }, { __index = Runtime })
function runtime:isOnline() return self.online end
local Plugin = dofile(plugin_root .. "/main.lua")
local plugin = Plugin:new{ api = api, runtime = runtime, ui = { menu = { registerToMainMenu = function() end } } }
local sync = api.highlights
local ReaderUI = require("apps/reader/readerui")
local evidence, index, stage, attempts, finished = {}, 1, "open", 0, false

local function seed(reader, fixture)
    if #reader.annotation.annotations > 0 then return end
    local selection
    if fixture.format == "application/pdf" then
        local line = reader.document:getPageTextBoxes(1)[1]
        local first, last = line[1], line[2]
        assert(first.word == "Position" and last.word == "fixture", "Unexpected PDF text layer")
        selection = { text = "Position fixture", pboxes = { { x = first.x0, y = first.y0,
            w = last.x1 - first.x0 + 1, h = last.y1 - first.y0 + 1 } },
            pos0 = { page = 1, x = first.x0 + 1, y = first.y0 + 1, zoom = 1, rotation = 0 },
            pos1 = { page = 1, x = last.x1 - 1, y = last.y1 - 1, zoom = 1, rotation = 0 } }
    else
        selection = { text = "Alpha 😀 beta", pos0 = "/body/DocFragment[1]/body/p[1]/text().0",
            pos1 = "/body/DocFragment[1]/body/p[1]/text().12" }
    end
    selection.color, selection.drawer, selection.note = "yellow", "lighten", "KOReader live handoff"
    reader.highlight.highlight_write_into_pdf = false
    reader.highlight.selected_text = selection; reader.highlight:saveHighlight(); reader.highlight.selected_text = nil
    reader.doc_settings:saveSetting("highlight_test_sentinel", "preserved")
    sync:changed(); sync:sync()
end

local function check(reader, fixture)
    local record = sync.store:get(sync.identity)
    assert(record and not record.delivery, sync:statusText())
    local count, comments = 0, {}
    for _, entry in pairs(record.entries) do
        assert(not entry.error and not entry.conflict, sync:statusText())
        assert(entry.base ~= false, "Highlight not yet acknowledged")
        count = count + 1; comments[#comments + 1] = entry.base.comment
        if fixture.format == "application/pdf" then
            local text = reader.document.koptinterface:getTextFromBoxes(reader.document:getPageTextBoxes(entry.native.pos0.page), entry.native.pos0, entry.native.pos1)
            assert(text and text.text == entry.base.text, "PDF native selection mismatch: " .. tostring(text and text.text) .. " vs " .. entry.base.text)
        end
    end
    assert(count > 0, "Expected test highlights")
    if phase == "pull" then
        local found = false
        for _, comment in ipairs(comments) do if comment:find("Desktop", 1, true) then found = true end end
        assert(found, "Expected Desktop handoff annotation")
    end
    assert(reader.doc_settings:readSetting("highlight_test_sentinel") == "preserved")
    assert(Identity.checksum(fixture.local_path, true) == fixture.md5, "Source PDF/EPUB was modified")
    reader:saveSettings()
    Device.screen:shot(root .. "/highlight-" .. phase .. "-" .. index .. ".png")
    evidence[#evidence + 1] = { format = fixture.format, attachment = fixture.key, entries = record.entries }
end

local function advance()
    local ok, err = xpcall(function()
        local fixture = manifest.items[index]
        if not fixture then finished = true; UIManager:quit(); return end
        if stage == "open" then
            runtime.online = false
            plugin.browser:openAttachment(fixture.local_path, fixture.key)
            runtime.online = true; stage = "seed"; return
        end
        local reader = assert(ReaderUI.instance)
        if stage == "seed" then
            if reader.paging then reader.zooming:onSetZoomMode("page"); reader.paging:onGotoPage(1) end
            if phase == "push" then seed(reader, fixture) else sync:sync() end
            stage = "wait"; return
        end
        if api.operation then attempts = attempts + 1; assert(attempts < 180, "Live sync timed out"); return end
        check(reader, fixture)
        print("LIVE HIGHLIGHT " .. phase:upper() .. " PASS", fixture.format)
        runtime.online = false; reader:onHome()
        index, stage, attempts = index + 1, "open", 0
    end, debug.traceback)
    if not ok then print("LIVE HIGHLIGHT FAIL", err); UIManager:quit(1); return end
    if not finished then UIManager:scheduleIn(0.3, advance) end
end
advance()
local result = UIManager:run()
api.util.write(root .. "/highlight-" .. phase .. "-evidence.json", api.util.encode(evidence))
Device:exit()
os.exit(finished and (result or 0) or 1)
