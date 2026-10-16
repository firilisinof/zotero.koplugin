-- Render the README screenshots from a demo library. Nothing contacts Zotero.
-- Run from the emulator's koreader directory with a fresh KO_HOME under /tmp:
--   EMULATE_READER_W=758 EMULATE_READER_H=1024 KO_HOME="$(mktemp -d /tmp/zotero-readme.XXXXXX)" \
--       ./luajit /absolute/path/to/zotero.koplugin/tools/readme-screenshots.lua /absolute/path/to/zotero.koplugin
local plugin_dir = assert(arg[1], "pass the plugin checkout as the first argument")
require("setupkoenv")
local root = require("datastorage"):getDataDir()
assert(root:match("^/tmp/") or root:match("^/private/tmp/"), "Use a temporary KO_HOME, got " .. root)
G_defaults = require("luadefaults"):open(root .. "/defaults.lua")
G_reader_settings = require("luasettings"):open(root .. "/settings.reader.lua")
local Device = require("device")
-- E-readers without a keyboard show no Q/W/E shortcut hints beside the rows.
Device.hasKeyboard = function() return false end
require("document/canvascontext"):init(Device)
require("ui/bidi").setup()
package.path = plugin_dir .. "/?.lua;" .. package.path
package.reload = function(name) package.loaded[name] = nil return require(name) end
local UIManager = require("ui/uimanager")
local env = require("spec.support.zotero_env").new()
local Plugin = dofile(plugin_dir .. "/main.lua")
local plugin = Plugin:new{ api = env.api, ui = { menu = { registerToMainMenu = function() end } } }
assert(plugin.initialized and plugin:ensureBrowser())
local api, browser = plugin.api, plugin.browser
local out = plugin_dir .. "/docs/screenshots"
assert(api.util.mkdir(out))
env:credentials()

-- Collections: key, name, parent.
local COLLECTIONS = {
    { "CMLEARN1", "Machine Learning" },
    { "CTRANSF1", "Transformers", "CMLEARN1" },
    { "CREINF01", "Reinforcement Learning", "CMLEARN1" },
    { "CMIND001", "Philosophy of Mind" },
    { "CTHESIS1", "Thesis: Chapter 2" },
    { "CTOREAD1", "To read" },
}

-- Publications: key, title, creator summary, year, format, collections, downloaded.
local PAPERS = {
    { "VASWANI1", "Attention Is All You Need", "Vaswani et al.", "2017", "pdf", { "CTRANSF1", "CTHESIS1" }, true },
    { "DEVLIN01", "BERT: Pre-training of Deep Bidirectional Transformers for Language Understanding",
        "Devlin et al.", "2019", "pdf", { "CTRANSF1" }, true },
    { "BROWN001", "Language Models are Few-Shot Learners", "Brown et al.", "2020", "pdf", { "CTRANSF1" }, false },
    { "DOSOVIT1", "An Image is Worth 16x16 Words: Transformers for Image Recognition at Scale",
        "Dosovitskiy et al.", "2021", "pdf", { "CTRANSF1", "CTOREAD1" }, false },
    { "BAHDANA1", "Neural Machine Translation by Jointly Learning to Align and Translate",
        "Bahdanau et al.", "2015", "pdf", { "CTRANSF1" }, true },
    { "MNIH0001", "Human-level control through deep reinforcement learning", "Mnih et al.", "2015", "pdf",
        { "CREINF01" }, true },
    { "SUTTON01", "Reinforcement Learning: An Introduction", "Sutton and Barto", "2018", "epub",
        { "CREINF01", "CMLEARN1" }, true },
    { "GOODFEL1", "Deep Learning", "Goodfellow et al.", "2016", "epub", { "CMLEARN1" }, false },
    { "LECUN001", "Deep learning", "LeCun et al.", "2015", "pdf", { "CMLEARN1" }, true },
    { "NAGEL001", "What Is It Like to Be a Bat?", "Nagel", "1974", "pdf", { "CMIND001" }, true },
    { "CHALMER1", "Facing Up to the Problem of Consciousness", "Chalmers", "1995", "pdf", { "CMIND001" }, false },
    { "SEARLE01", "Minds, brains, and programs", "Searle", "1980", "pdf", { "CMIND001", "CTHESIS1" }, true },
    { "TURING01", "Computing Machinery and Intelligence", "Turing", "1950", "pdf", { "CMIND001", "CTHESIS1" }, true },
    { "HOFSTAD1", "Gödel, Escher, Bach: An Eternal Golden Braid", "Hofstadter", "1979", "epub", { "CTOREAD1" }, false },
    { "DENNETT1", "Consciousness Explained", "Dennett", "1991", "epub", { "CMIND001", "CTOREAD1" }, true },
}

local NOTE = [[<h1>Reading notes</h1>
<p>Scaled dot-product attention divides by the square root of the key dimension so softmax gradients stay
usable for large d_k.</p>
<p>Multi-head attention lets each head attend to a different representation subspace.</p>
<p>Compare positional encodings with the learned embeddings in BERT for chapter 2.</p>]]

local function collectionEntries()
    local collections = {}
    for index, spec in ipairs(COLLECTIONS) do
        collections[spec[1]] = { key = spec[1], version = index, meta = {},
            data = { key = spec[1], name = spec[2], parentCollection = spec[3] or false } }
    end
    return collections
end

local function addPaper(items, index, spec)
    local key, title, author, year, format, collections = spec[1], spec[2], spec[3], spec[4], spec[5], spec[6]
    local added = string.format("2024-%02d-%02dT10:00:00Z", (index % 12) + 1, (index % 27) + 1)
    items[key] = { key = key, version = index, meta = { creatorSummary = author, parsedDate = year },
        data = { key = key, itemType = format == "epub" and "book" or "journalArticle", title = title,
            date = year, collections = collections, tags = {}, dateAdded = added } }
    local attachment = key:sub(1, 6) .. "AT"
    items[attachment] = { key = attachment, version = index, meta = {}, data = {
        key = attachment, itemType = "attachment", parentItem = key, linkMode = "imported_file",
        title = format == "epub" and "EPUB" or "Full Text PDF", filename = author .. " - " .. year .. "." .. format,
        contentType = format == "epub" and "application/epub+zip" or "application/pdf", tags = {}, dateAdded = added } }
    return attachment
end

local function buildLibrary()
    local items, downloaded = {}, {}
    for index, spec in ipairs(PAPERS) do
        local attachment = addPaper(items, index, spec)
        if spec[7] then table.insert(downloaded, attachment) end
    end
    items.VASWNOTE = { key = "VASWNOTE", version = 99, meta = {},
        data = { key = "VASWNOTE", itemType = "note", parentItem = "VASWANI1", note = NOTE, tags = {} } }
    api.setItems(items)
    api.setCollections(collectionEntries())
    api.getSettings():saveSetting("cache_schema", 1)
    api.setLastSync(os.time() - 3600)
    for _, key in ipairs(downloaded) do env:file(key, "demo", 1) end
    api.saveContinueReading(api.getLocalLibraryPrefix() or "local", "VASWANAT", api.getLocalAttachmentPath("VASWANAT"))
end

local function top()
    return UIManager._window_stack[#UIManager._window_stack].widget
end

local function shot(name)
    UIManager:forceRePaint()
    Device.screen:shot(out .. "/" .. name .. ".png")
    print("SHOT " .. name)
end

local steps = {
    { "home", function() browser:displayHome() end },
    { "collection", function() browser:displayCollection("CTRANSF1") end },
    { "search", function() browser:displaySearchResults("learning") end },
    { "notes", function()
        browser:displayCollection("CTRANSF1")
        browser:showNotes("VASWANAT")
    end },
}

buildLibrary()
local index, finished = 0, false
local function advance()
    index = index + 1
    local current = steps[index]
    if not current then finished = true UIManager:quit() return end
    local ok, err = xpcall(function() current[2]() shot(current[1]) end, debug.traceback)
    if not ok then print("SHOT FAIL: " .. tostring(err)) UIManager:quit(1) return end
    if top() ~= plugin.zotero_dialog then UIManager:close(top()) end
    UIManager:scheduleIn(0.5, advance)
end

plugin:onZoteroOpenAction()
UIManager:scheduleIn(0.3, advance)
UIManager:scheduleIn(30, function() print("SHOT TIMEOUT") UIManager:quit(1) end)
UIManager:run()
Device:exit()
os.exit(finished and 0 or 1)
