-- Run from the emulator directory with a fresh KO_HOME under /tmp.
-- HTTP uses fixtures. Screenshots and settings stay under KO_HOME.
require("setupkoenv")
local root = require("datastorage"):getDataDir()
assert(root:match("^/tmp/") or root:match("^/private/tmp/"), "Use a temporary KO_HOME")
G_defaults = require("luadefaults"):open(root .. "/defaults.lua")
G_reader_settings = require("luasettings"):open(root .. "/settings.reader.lua")
local Device = require("device")
require("document/canvascontext"):init(Device)
require("ui/bidi").setup()
package.path = "plugins/zotero.koplugin/?.lua;" .. package.path
package.reload = function(name) package.loaded[name] = nil return require(name) end
local UIManager = require("ui/uimanager")
local env = require("spec.support.zotero_env").new()
local Plugin = dofile("plugins/zotero.koplugin/main.lua")
local plugin = Plugin:new{ api = env.api, ui = { menu = { registerToMainMenu = function() end } } }
assert(plugin.initialized)
local api, browser = plugin.api, plugin.browser
assert(api.util.mkdir(root .. "/screenshots"))
env:credentials()
env:library()
local original = env:file("ATTACH01", "old paper", 1)
api.util.mkdir(original .. ".sdr")
api.util.write(original .. ".sdr/metadata.lua", "progress")
env.http:on("GET", "/items/STANDAL1/file", { body = "standalone" })
env.http:on("GET", "/items/ATTACH01/file", { body = "updated paper" })
local fake_request = env.http.request
env.http.request = function(request)
    require("ffi/util").usleep(350000)
    return fake_request(request)
end

local function top()
    return UIManager._window_stack[#UIManager._window_stack].widget
end

local function closeTop()
    UIManager:close(top())
end

local function shot(name)
    UIManager:forceRePaint()
    Device.screen:shot(root .. "/screenshots/" .. name .. ".png")
    print("SMOKE " .. name)
end

local steps = {}
local function step(name, action)
    table.insert(steps, { name = name, action = action })
end

step("01-browser", function()
    browser:displayCollection("COLLAAA1")
end)
step("02-library-selector", function() plugin:setAccount() end)
step("03-group-account", function()
    local selector = top()
    selector.provider = "group"
    selector.callback(selector)
    UIManager:close(selector)
    assert(top().input_fields[1]:getText() == "")
end)
step("04-group-library", function()
    local dialog = top()
    dialog.input_fields[1]:setText("99")
    dialog.buttons[1][2].callback()
    assert(api.getLibraryPrefix() == "groups/99")
    env:library()
    browser:displayCollection("COLLAAA1")
    assert(not api.displaySearchResults("attention")[1].downloaded)
end)
step("05-notes-menu", function() browser:onMenuHold({ key = "ATTACH01", text = "Attention Is All You Need" }) end)
step("06-notes", function() top().buttons[1][1].callback() end)
step("07-tag-dialog", function()
    closeTop()
    assert(not api.setAccount("user", "4242", "offline-test-key"))
    env:library()
    api.getItems().PARENT01.data.tags = { { tag = "Read" } }
    api.setItems(api.getItems())
    browser:displayCollection("COLLAAA1")
    plugin:setFilterTag()
end)
step("08-filtered", function()
    local dialog = top()
    dialog:setInputText("Read")
    dialog.buttons[1][3].callback()
    assert(#api.displaySearchResults("") == 1)
end)
step("09-download-menu", function()
    plugin:setFilterTag()
    top().buttons[1][2].callback()
    browser:onMenuHold({ key = "COLLAAA1", text = "Papers/", collection = true })
end)
step("10-progress", function() top().buttons[1][1].callback() end)
step("11-complete", function()
    assert(not api.operation, "download should be finished")
    assert(api.isAttachmentCurrent("ATTACH01"))
    assert(api.isAttachmentCurrent("STANDAL1"))
    assert(api.util.read(original .. ".sdr/metadata.lua") == "progress")
    assert(top().text:find("Downloaded: 2", 1, true))
end)
step("12-cancel-progress", function()
    closeTop()
    api.getItems().ATTACH01.version = 9999
    api.getItems().STANDAL1.version = 9999
    browser:startDownload(function() browser:downloadCollection("COLLAAA1") end)
end)
step("13-cancelled", function()
    assert(browser.download_dialog, "active progress dialog expected")
    browser.download_dialog:onTapClose()
    assert(not api.operation)
    assert(top().text:find("Cancelled: 2", 1, true))
    assert(api.util.read(original) == "updated paper")
end)
step("14-offline-browser", function()
    closeTop()
    browser:displayCollection("COLLAAA1")
    assert(api.displaySearchResults("attention")[1].downloaded)
end)

step("15-metadata-collection", function()
    local items = api.getItems()
    items.LINKED01.data.collections = { "COLLAAA1" }
    items.LONGP = { key = "LONGP", version = 1, meta = { creatorSummary = "Chen et al.", parsedDate = "2024-01-01" },
        data = { itemType = "journalArticle", collections = { "COLLAAA1" },
            title = "Understanding long publication titles on electronic paper displays: metadata, readability, and accessible navigation across very large research libraries" } }
    api.setItems(items)
    env:attachment("LONGFILE", "LONGP", "long-title.pdf")
    env:attachment("ORPHAN", "MISSING", "orphan-report.pdf")
    items = api.getItems()
    items.ORPHAN.data.title = ""
    items.PARENT02.data.collections = { "COLLAAA1", "COLLCCC3" }
    items.PARENT02.meta.creatorSummary = nil
    items.PARENT02.meta.parsedDate = "2008"
    api.setItems(items)
    browser.is_enable_shortcut = false
    browser:displayCollection("COLLAAA1")
    assert(browser.item_group[1].entry.collection)
    assert(browser.item_group[2].metadata_widgets.status.text == "Unavailable")
    assert(browser.item_group[3].metadata_widgets.status.text == "Downloaded")
end)
step("16-metadata-search", function()
    browser:displaySearchResults("")
    assert(api.displaySearchResults("orphan-report.pdf")[1].title == "orphan-report.pdf")
    local long_title = browser.item_group[3].metadata_widgets.title
    assert(long_title.line_with_ellipsis == 2)
    assert(browser.item_group:getSize().h <= browser.available_height)
end)
step("17-metadata-large-font", function()
    browser.items_font_size = 36
    browser:displayCollection("COLLAAA1")
    assert(browser.page_num > 1)
    assert(browser.item_group:getSize().h <= browser.available_height)
end)
step("18-metadata-large-search", function()
    browser:displaySearchResults("")
    assert(browser.page_num > 1)
    assert(browser.item_group:getSize().h <= browser.available_height)
end)
step("19-metadata-next-page", function()
    browser:onNextPage()
    assert(browser.page == 2)
    assert(browser.item_group[1].idx == browser.perpage + 1)
end)
step("20-metadata-collections", function()
    browser.items_font_size = nil
    browser:displayCollection(nil)
    assert(browser.item_group[1].entry.wildcard_collection)
    assert(browser.item_group[2].entry.collection)
end)

local index, finished = 0, false
local function advance()
    index = index + 1
    local current = steps[index]
    if not current then finished = true print("SMOKE PASS: " .. #steps .. " screens") UIManager:quit() return end
    local ok, err = pcall(function() current.action() shot(current.name) end)
    if not ok then print("SMOKE FAIL: " .. tostring(err)) UIManager:quit(1) return end
    UIManager:scheduleIn(current.name == "10-progress" and 1.5 or 0.1, advance)
end

plugin:onZoteroOpenAction()
UIManager:scheduleIn(0.1, advance)
UIManager:scheduleIn(20, function() print("SMOKE TIMEOUT") UIManager:quit(1) end)
local result = UIManager:run()
Device:exit()
os.exit(finished and (result or 0) or 1)
