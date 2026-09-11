-- Actual ReaderUI, native document engines, subprocesses, and temporary sidecars.
require("setupkoenv")
local root = assert(os.getenv("KO_HOME"))
assert(root:match("^/tmp/") or root:match("^/private/tmp/"), "Use temporary KO_HOME")
G_defaults = require("luadefaults"):open(root .. "/defaults.lua")
G_reader_settings = require("luasettings"):open(root .. "/settings.reader.lua")
local Device = require("device")
require("document/canvascontext"):init(Device)
require("ui/bidi").setup()
local plugin_root = os.getenv("ZOTERO_PLUGIN_ROOT") or "plugins/zotero.koplugin"
package.path = plugin_root .. "/?.lua;plugins/zotero.koplugin/?.lua;" .. package.path
package.reload = function(name) package.loaded[name] = nil return require(name) end
local UIManager = require("ui/uimanager")
local Runtime = require("zoteroui")
local runtime = setmetatable({ online = true }, { __index = Runtime })
function runtime:isOnline() return self.online end
local env = require("spec.support.zotero_env").new()
local Plugin = dofile(plugin_root .. "/main.lua")
local plugin = Plugin:new{ api = env.api, runtime = runtime, ui = { menu = { registerToMainMenu = function() end } } }
local api, progress = plugin.api, plugin.api.progress
env:credentials(); env:library()
local fixture = "plugins/zotero.koplugin/spec/fixtures/positions/"
local Identity = require("zoteroprogressidentity")
local Server = require("spec.support.fake_progress_server")
local server = Server.new(); api.http = server
local DocSettings = require("docsettings")
local ReaderUI = require("apps/reader/readerui")
api.settings:saveSetting("share_reading_position", true)
api.settings:saveSetting("progress_authorization", { owner = "4242", key_hash = Identity.keyHash(api.getAPIKey()) })
api.saveModifiedItems()
local files = {}
for _, entry in ipairs({ { "ATTACH01", "sample.pdf", "application/pdf" }, { "EPBOOK01", "sample.epub", "application/epub+zip" } }) do
    local item = env:attachment(entry[1], "PARENT01", entry[2]); item.data.contentType = entry[3]
    files[entry[1]] = env:file(entry[1], assert(api.util.read(fixture .. entry[2])))
    item.data.md5 = Identity.checksum(files[entry[1]], true)
    server.items[entry[1]] = item
end
api.setItems(api.getItems())
local pdf_settings = DocSettings:open(files.ATTACH01)
pdf_settings:saveSetting("last_page", 2); pdf_settings:saveSetting("zotero_position_marker", "preserved"); pdf_settings:flush()
local epub_settings = DocSettings:open(files.EPBOOK01)
epub_settings:saveSetting("last_xpointer", "/body/DocFragment[1]/body/p[1]/text().8")
epub_settings:saveSetting("cre_dom_version", 20260812)
local annotations = { { datetime = "2026-01-01 12:00:00", drawer = "lighten", color = "yellow", text = "Alpha",
    page = "/body/DocFragment[1]/body/p[1]/text().0", pos0 = "/body/DocFragment[1]/body/p[1]/text().0",
    pos1 = "/body/DocFragment[1]/body/p[1]/text().5", pageno = 1 } }
epub_settings:saveSetting("annotations", annotations); epub_settings:flush()
local steps = {}
local function step(name, action) table.insert(steps, { name = name, action = action }) end
local function current() return assert(ReaderUI.instance) end
local function record() return progress.store:get(progress.session.identity) end
local function shared()
    if api.operation then return false end
    assert(record().status == "shared", progress:statusText()); return true
end
step("pdf-push", function()
    if not shared() then return false end
    assert(current().paging:getLastProgress() == 2)
    assert(record().value == 1)
    server.delay = 2000000
    progress:sync()
    local clock = require("socket").gettime
    local started = clock(); progress:suspend()
    assert(clock() - started < 0.5, "Suspend waited for the network child")
    assert(not api.operation, "Suspend retained the operation lock")
    server.delay = nil
    server:setting(0); progress:sync()
end)
step("pdf-pull", function()
    if not shared() then return false end
    assert(current().paging:getLastProgress() == 1)
    runtime.online = false
    current().paging:onGotoPage(3); progress:suspend()
    assert(record().pending and record().value == 2)
    current():onHome()
end)
step("offline-reopen", function()
    plugin.browser:openAttachment(files.ATTACH01, "ATTACH01")
end)
step("offline-restored", function()
    assert(current().paging:getLastProgress() == 3)
    assert(record().pending)
    runtime.online = true; progress:sync()
end)
step("pdf-reconnected", function()
    if not shared() then return false end
    assert(record().value == 2)
    assert(DocSettings:open(files.ATTACH01):readSetting("zotero_position_marker") == "preserved")
    plugin.browser:openAttachment(files.EPBOOK01, "EPBOOK01")
end)
step("epub-push", function()
    if not shared() then return false end
    assert(record().value:match(":9$"))
    local target = assert(progress.session.codec:encode("/body/DocFragment[2]/body/p/text().20"))
    server.settings.lastPageIndex_u_EPBOOK01 = { value = target, version = 99 }
    progress:sync()
end)
step("epub-pull", function()
    if not shared() then return false end
    assert(current().rolling:getLastProgress():find("DocFragment[2]", 1, true))
    runtime.online = false
    current():reloadDocument()
end)
step("epub-reload", function()
    assert(progress.reader == current())
    assert(current().rolling:getLastProgress():find("DocFragment[2]", 1, true))
    current():onHome()
    local saved = DocSettings:open(files.EPBOOK01):readSetting("annotations")
    assert(#saved == 1 and saved[1].text == "Alpha" and saved[1].pos1 == annotations[1].pos1)
    assert(api.util.read(files.EPBOOK01) == api.util.read(fixture .. "sample.epub"))
end)
local index, retries, finished = 1, 0, false
local function advance()
    local current_step = steps[index]
    if not current_step then finished = true; print("POSITION SMOKE PASS: " .. #steps .. " stages"); UIManager:quit(); return end
    local ok, result = xpcall(current_step.action, debug.traceback)
    if not ok then print("POSITION SMOKE FAIL: " .. tostring(result)); UIManager:quit(1); return end
    if result == false then retries = retries + 1 else
        print("POSITION SMOKE " .. current_step.name)
        Device.screen:shot(root .. "/" .. current_step.name .. ".png")
        index, retries = index + 1, 0
    end
    if retries > 50 then print("POSITION SMOKE TIMEOUT: " .. progress:statusText()); UIManager:quit(1); return end
    UIManager:scheduleIn(0.2, advance)
end
plugin.browser:openAttachment(files.ATTACH01, "ATTACH01")
UIManager:scheduleIn(0.5, advance)
local result = UIManager:run()
Device:exit()
os.exit(finished and (result or 0) or 1)
