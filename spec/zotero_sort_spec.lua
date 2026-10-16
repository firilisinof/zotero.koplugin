require("commonrequire")
package.path = "plugins/zotero.koplugin/?.lua;" .. package.path
local Env = require("spec.support.zotero_env")
local FakeUI = require("spec.support.fake_ui")
local Browser = require("zoterobrowser")
local Menus = require("zoteromenu")

describe("Zotero date-added sorting", function()
    local env, api
    before_each(function()
        env = Env.new()
        api = env.api
        env:credentials()
        env:library()
        local items = api.getItems()
        items.PARENT01.data.dateAdded = "2024-01-01T00:00:00Z"
        items.PARENT02.data.dateAdded = "2025-01-01T00:00:00Z"
        items.PARENT02.data.collections = { "COLLAAA1" }
        items.ATTACH01.data.dateAdded = "2026-01-01T00:00:00Z"
        api.setItems(items)
    end)

    local function keys(rows)
        local result = {}
        for _, row in ipairs(rows) do
            if row.key == "ATTACH01" or row.key == "ATTACH02" then table.insert(result, row.key) end
        end
        return result
    end

    it("keeps alphabetical as the default and persists date ordering with index invalidation", function()
        assert.equal("alphabetical", api.getSortOrder())
        local index = api.getIndex()
        api.setSortOrder("date_added_desc")
        assert.is_not_equal(index, api.getIndex())
        api.init(env.root)
        assert.equal("date_added_desc", api.getSortOrder())
        api.getSettings():saveSetting("sort_order", "unknown")
        assert.equal("alphabetical", api.getSortOrder())
    end)

    it("sorts collections, all items, search and local copies by publication date", function()
        env:file("ATTACH01")
        env:file("ATTACH02")
        for _, order in ipairs({ "date_added_desc", "date_added_asc" }) do
            api.setSortOrder(order)
            local expected = order == "date_added_desc" and { "ATTACH02", "ATTACH01" } or { "ATTACH01", "ATTACH02" }
            assert.same(expected, keys(api.displayCollection("COLLAAA1")))
            assert.same(expected, keys(api.displaySearchResults("")))
            local browser = FakeUI.new():newBrowser(Browser, api)
            browser:displayAllItems()
            assert.same(expected, keys(browser.rows))
            assert.same(expected, keys(api.displayOnDevice("")))
            assert.equal("ATTACH01", api.displaySearchResults("attention")[1].key)
            assert.is_true(api.displayCollection("COLLAAA1")[1].collection)
        end
    end)

    it("uses standalone and orphan dates, puts undated rows last and breaks ties by text then key", function()
        local items = {}
        for _, key in ipairs({ "C", "B", "A", "D", "E" }) do
            items[key] = { key = key, version = 1, data = { itemType = "attachment", title = "Same",
                contentType = "application/pdf", dateAdded = "2024-01-01T00:00:00Z" } }
        end
        items.A.data.title = "First"
        items.B.data.parentItem = "MISSING"
        items.D.data.dateAdded = nil
        items.E.data.dateAdded = ""
        api.setItems(items)
        for _, order in ipairs({ "date_added_desc", "date_added_asc" }) do
            api.setSortOrder(order)
            local actual = {}
            for _, row in ipairs(api.displaySearchResults("")) do table.insert(actual, row.key) end
            assert.same({ "A", "B", "C", "D", "E" }, actual)
        end
    end)

    it("preserves tag filtering under date ordering", function()
        local items = api.getItems()
        items.PARENT01.data.tags = { { tag = "Read" } }
        api.setItems(items)
        api.setSortOrder("date_added_desc")
        api.setFilterTag("Read")
        assert.same({ "ATTACH01" }, keys(api.displaySearchResults("")))
        api.setSortOrder("date_added_asc")
        assert.same({ "ATTACH01" }, keys(api.displayCollection("COLLAAA1")))
    end)

    it("applies the menu choice immediately and safely before a browser exists", function()
        local runtime = FakeUI.new()
        local browser = runtime:newBrowser(Browser, api)
        browser:displayCollection("COLLAAA1", 2)
        local plugin = setmetatable({ api = api, browser = browser }, { __index = Menus })
        local menu = {}
        plugin:addToMainMenu(menu)
        local choices
        for _, entry in ipairs(menu.zotero.sub_item_table[5].sub_item_table) do
            if entry.text == "Sort items" then choices = entry.sub_item_table end
        end
        assert.is_true(choices[1].checked_func())
        choices[2].callback()
        assert.is_true(choices[2].checked_func())
        assert.equal(1, browser.current_view.page)
        assert.same({ "ATTACH02", "ATTACH01" }, keys(browser.rows))
        plugin.browser = nil
        choices[3].callback()
        assert.equal("date_added_asc", api.getSortOrder())
    end)
end)
