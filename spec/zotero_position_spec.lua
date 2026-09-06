require("commonrequire")
package.path = "plugins/zotero.koplugin/?.lua;" .. package.path
local Env = require("spec.support.zotero_env")
local FakeUI = require("spec.support.fake_ui")
local Browser = require("zoterobrowser")
local Plugin = dofile("plugins/zotero.koplugin/main.lua")

describe("Zotero browser position", function()
    local env, api, runtime, browser
    local function newBrowser()
        return Browser:new{ api = api, runtime = runtime, title = "Zotero",
            width = 600, height = 800, items_per_page = 2, is_enable_shortcut = false,
            close_callback = function() end }
    end

    before_each(function()
        env = Env.new()
        api = env.api
        env:credentials()
        env:library()
        runtime = FakeUI.new()
        browser = newBrowser()
        browser:restoreLibrary()
    end)

    after_each(function() browser:free() end)

    it("restores collection pages, searches and back history after closing and recreation", function()
        browser:onGotoPage(2)
        browser:navigate{ kind = "collection", key = "COLLAAA1" }
        browser:onGotoPage(2)
        browser:navigate{ kind = "search", query = "attention" }
        browser:onCloseAllMenus()
        browser:free()
        api.init(env.root)
        browser = newBrowser()
        browser:restoreLibrary()
        assert.equals("attention", browser.current_view.query)
        browser:onReturn()
        assert.equals("COLLAAA1", browser.current_view.key)
        assert.equals(2, browser.page)
        browser:onReturn()
        assert.is_nil(browser.current_view.key)
        assert.equals(2, browser.page)
        assert.equals(0, env.http:callCount())
    end)

    it("reopens on the same page after opening a local document", function()
        local path = env:file("ATTACH01")
        browser:navigate{ kind = "collection", key = "COLLAAA1" }
        browser:onGotoPage(2)
        browser:onMenuSelect(browser.item_table[3])
        assert.equals(path, runtime.opened_path)
        local plugin = setmetatable({ api = api, runtime = runtime, browser = browser,
            initialized = true, zotero_dialog = {} }, { __index = Plugin })
        plugin:onZoteroOpenAction()
        assert.equals("COLLAAA1", browser.current_view.key)
        assert.equals(2, browser.page)
        assert.equals(0, #runtime.scheduled)
    end)

    it("uses the last view saved by another reader or file manager instance", function()
        browser:navigate{ kind = "collection", key = "COLLAAA1" }
        local reader_browser = newBrowser()
        reader_browser:restoreLibrary()
        reader_browser:navigate{ kind = "device", query = "attention" }
        reader_browser:onCloseAllMenus()
        reader_browser:free()
        browser:restoreLibrary()
        assert.equals("device", browser.current_view.kind)
        assert.equals("attention", browser.current_view.query)
        browser:onReturn()
        assert.equals("COLLAAA1", browser.current_view.key)
    end)

    it("does not overwrite newer history when an older instance observes an account change", function()
        browser:navigate{ kind = "collection", key = "COLLAAA1" }
        local reader_browser = newBrowser()
        reader_browser:restoreLibrary()
        reader_browser:navigate{ kind = "device", query = "attention" }
        api.setAccount("group", "99", "key")
        reader_browser:restoreLibrary()
        reader_browser:navigate{ kind = "search", query = "group" }
        reader_browser:free()
        browser:restoreLibrary()
        assert.equals("group", browser.current_view.query)
        api.setAccount("user", "4242", "key")
        browser:restoreLibrary()
        assert.equals("device", browser.current_view.kind)
        assert.equals("attention", browser.current_view.query)
    end)

    it("does not save an unopened browser over an existing position", function()
        browser:navigate{ kind = "search", query = "attention" }
        local unopened = newBrowser()
        unopened:savePosition()
        unopened:free()
        assert.equals("attention", api.getBrowserPosition("users/4242").view.query)
    end)

    it("preserves current pages on refresh and clamps when filters shrink results", function()
        browser:navigate{ kind = "search", query = "" }
        browser:onLastPage()
        local page = browser.page
        env:file("ATTACH01")
        browser:refresh()
        assert.equals(page, browser.page)
        api.setFilterTag("missing")
        browser:refresh()
        assert.equals(1, browser.page)
        assert.is_true(browser.item_table[1].is_label)
        assert.equals("search", browser.current_view.kind)
        assert.equals("", browser.current_view.query)
    end)

    it("keeps separate positions for personal IDs and groups with the same ID", function()
        browser:navigate{ kind = "collection", key = "COLLAAA1" }
        browser:onGotoPage(2)
        for _, account in ipairs({ { "group", "4242" }, { "user", "55" } }) do
            api.setAccount(account[1], account[2], "key")
            browser:restoreLibrary()
            assert.equals("collection", browser.current_view.kind)
            assert.is_nil(browser.current_view.key)
            env:library()
            browser:navigate{ kind = "device", query = account[2] }
        end
        api.setAccount("user", "4242", "key")
        browser:restoreLibrary()
        assert.equals("COLLAAA1", browser.current_view.key)
        assert.equals(2, browser.current_view.page)
        browser:savePosition()
        api.init(env.root)
        browser:free()
        browser = newBrowser()
        browser:restoreLibrary()
        env:library()
        browser:refresh()
        assert.equals(2, browser.page)
        api.setAccount("group", "4242", "key")
        browser:restoreLibrary()
        assert.equals("device", browser.current_view.kind)
        assert.equals("4242", browser.current_view.query)
    end)

    it("falls back through history when a synced collection disappears", function()
        browser:navigate{ kind = "collection", key = "COLLAAA1" }
        browser:navigate{ kind = "collection", key = "COLLCCC3" }
        local collections = api.getCollections()
        collections.COLLCCC3 = nil
        api.setCollections(collections)
        browser:refresh()
        assert.equals("COLLAAA1", browser.current_view.key)
        api.setCollections({})
        browser:refresh()
        assert.equals("collection", browser.current_view.kind)
        assert.is_nil(browser.current_view.key)
    end)

    it("persists On device pages and searches and rechecks presence on reopen", function()
        env:file("ATTACH01")
        env:file("ATTACH02")
        local path = env:file("STANDAL1")
        browser:navigate{ kind = "device" }
        browser:onGotoPage(2)
        browser:navigate{ kind = "device", query = "attention" }
        browser:onCloseAllMenus()
        browser:free()
        browser = newBrowser()
        browser:restoreLibrary()
        assert.equals("device", browser.current_view.kind)
        assert.equals("attention", browser.current_view.query)
        browser:onReturn()
        assert.equals(2, browser.page)
        assert(os.remove(path))
        browser:restoreLibrary()
        assert.equals(1, browser.page)
        assert.equals(2, #browser.item_table)
    end)

    it("copies persisted state and contains malformed settings", function()
        local position = { view = { kind = "device", query = "paper", page = 3 },
            paths = { { kind = "search", query = "all", page = 2 } } }
        api.saveBrowserPosition("users/4242", position)
        position.paths[1].query = "changed"
        local saved = api.getBrowserPosition("users/4242")
        assert.equals("all", saved.paths[1].query)
        saved.view.query = "changed"
        assert.equals("paper", api.getBrowserPosition("users/4242").view.query)
        api.getSettings():saveSetting("browser_positions", { ["users/4242"] = {
            view = { kind = "search", query = false, page = -20 }, paths = "bad" } })
        assert.same({ view = { kind = "search", query = "", page = 1 }, paths = {} }, api.getBrowserPosition("users/4242"))
        api.getSettings():saveSetting("browser_positions", "bad")
        assert.same({ view = { kind = "collection", page = 1 }, paths = {} }, api.getBrowserPosition("users/4242"))
    end)
end)
