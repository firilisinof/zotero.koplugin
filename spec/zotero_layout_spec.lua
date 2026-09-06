require("commonrequire")
package.path = "plugins/zotero.koplugin/?.lua;" .. package.path
local BD = require("ui/bidi")
local Browser = require("zoterobrowser")
local Env = require("spec.support.zotero_env")
local FakeUI = require("spec.support.fake_ui")
local Row = require("zoterorow")
local Screen = require("device").screen
local _ = require("gettext")

describe("Zotero native metadata layout", function()
    local env, browser, runtime, translations
    before_each(function()
        translations = _.translation
        env = Env.new()
        env:library()
        runtime = FakeUI.new()
        browser = Browser:new{ api = env.api, runtime = runtime, title = "Zotero",
            width = 600, height = 800, items_per_page = 14, is_enable_shortcut = false,
            close_callback = function() end }
    end)
    after_each(function()
        browser:free()
        _.translation = translations
    end)

    it("omits unavailable metadata and localizes presence independently", function()
        assert.equals("", Row.byline({}))
        assert.equals(BD.auto("Author"), Row.byline{ author = "Author" })
        assert.equals(BD.auto("2017"), Row.byline{ year = "2017" })
        assert.equals(BD.auto("Author") .. " · " .. BD.auto("2017"), Row.byline{ author = "Author", year = "2017" })
        assert.equals(_("Downloaded"), Row.status{ downloaded = true, downloadable = false })
        assert.equals(_("Unavailable"), Row.status{ downloaded = false, downloadable = false })
        assert.equals(_("Not downloaded"), Row.status{ downloaded = false })
    end)

    it("renders separate fields while keeping collection rows distinct", function()
        env:file("ATTACH01")
        browser:displayCollection("COLLAAA1")
        local collection, standalone, paper = unpack(browser.item_group)
        assert.is_nil(collection.metadata_widgets)
        assert.is_true(collection.bold)
        assert.equals("Subfolder/", collection.text)
        assert.equals("", standalone.metadata_widgets.byline.text)
        assert.equals(BD.auto("Attention Is All You Need"), paper.metadata_widgets.title.text)
        assert.equals("PDF", paper.metadata_widgets.format.text)
        assert.equals(_("Downloaded"), paper.metadata_widgets.status.text)
        assert.is_true(paper.metadata_widgets.title.face.size > paper.metadata_widgets.byline.face.size)
        browser:displaySearchResults("attention")
        assert.equals(_("Downloaded"), browser.item_group[1].metadata_widgets.status.text)
    end)

    it("provides an untitled label without showing legacy nil or unknown metadata", function()
        browser:setItems({ { key = "MISSING", text = "Unknown - nil", file_format = "PDF" } }, "Empty")
        assert.equals(BD.auto(_("Untitled")), browser.item_group[1].metadata_widgets.title.text)
        assert.equals("", browser.item_group[1].metadata_widgets.byline.text)
    end)

    it("measures and confines translated status labels", function()
        _.translation = { ["Not downloaded"] = "Noch nicht auf dieses Gerät heruntergeladen" }
        browser:displaySearchResults("attention")
        local item = browser.item_group[1]
        local fields = item.metadata_widgets
        assert.equals(_.translation["Not downloaded"], fields.status.text)
        assert.is_true(fields.status:isTruncated())
        assert.is_true(fields.title.width < fields.status.overlap_offset[1])
        assert.equals(item.content_width, fields.status.overlap_offset[1] + fields.status:getSize().w)
    end)

    it("contains long titles and large fonts on every page, including keyboard shortcuts", function()
        local entries = {}
        for i = 1, 30 do
            entries[i] = { key = tostring(i), text = "Search text " .. i, file_format = "PDF",
                title = string.rep("A very long publication title with descenders gyp ", 12), author = "Author", year = "2017" }
        end
        browser.items_font_size, browser.items_per_page, browser.is_enable_shortcut = 36, 1000, true
        browser:setItems(entries, "Empty")
        assert.is_true(browser.perpage < 14)
        assert.is_true(browser.page_num > 1)
        for page = 1, browser.page_num do
            browser:onGotoPage(page)
            assert.equals(page, browser.page)
            browser:paintTo(Screen.bb, 0, 0)
            assert.is_true(browser.item_group:getSize().h <= browser.available_height)
            for _, item in ipairs(browser.item_group) do
                local fields = item.metadata_widgets
                assert.equals(2, fields.title:getVisLineCount())
                assert.equals(2, fields.title.line_with_ellipsis)
                assert.is_true(fields.title:getSize().h <= browser.row_metrics.title_height)
                assert.is_true(fields.title.overlap_offset[2] + fields.title:getSize().h <= fields.byline.overlap_offset[2])
                assert.is_true(fields.status.overlap_offset[2] + fields.status:getSize().h <= item.dimen.h - item.linesize)
                assert.equals(item.content_width, fields.status.overlap_offset[1] + fields.status:getSize().w)
                assert.equals(item.content_width, fields.format.overlap_offset[1] + fields.format:getSize().w)
                assert.is_true(fields.title.width + require("ui/size").span.horizontal_default <= fields.status.overlap_offset[1])
            end
        end
        browser:onFirstPage()
        assert.equals("1", browser.item_group[1].entry.key)
        browser:onNextPage()
        assert.equals(tostring(browser.perpage + 1), browser.item_group[1].entry.key)
        browser:onPrevPage()
        assert.equals("1", browser.item_group[1].entry.key)
    end)

    it("fits a complete row on short screens and clamps dense default pagination", function()
        browser.items_per_page = 1000
        browser:displaySearchResults("")
        assert.is_true(browser.row_metrics.title_face.size > 0)
        browser.inner_dimen.h, browser.items_font_size = 250, 72
        browser:displaySearchResults("")
        assert.equals(1, browser.perpage)
        assert.is_true(browser.row_metrics.min_height + browser.linesize <= browser.available_height)
        assert.is_true(browser.item_group:getSize().h <= browser.available_height)
    end)

    it("retains native tap, hold and focus behavior after content replacement", function()
        browser:displayCollection("COLLAAA1")
        browser:paintTo(Screen.bb, 0, 0)
        local collection = browser.item_group[1]
        local gesture = { pos = { x = collection.dimen.x + 10, y = collection.dimen.y + 10 } }
        collection:onTapSelect(nil, gesture)
        assert.equals("COLLCCC3", browser.current_view.key)
        browser:paintTo(Screen.bb, 0, 0)
        local paper = browser.item_group[2]
        gesture.pos.y = paper.dimen.y + 10
        paper:onHoldSelect(nil, gesture)
        assert.equals("Show Zotero notes", runtime:last().buttons[1][1].text)
        paper:onFocus()
        assert.is_true(paper._underline_container.focused)
        paper:onUnfocus()
        assert.is_false(paper._underline_container.focused)
        env:credentials()
        env.http:on("GET", "/items/ATTACH02/file", { body = "epub" })
        paper:onTapSelect(nil, gesture)
        assert.equals(select(2, env.api.getDirAndPath("ATTACH02")), runtime.opened_path)
    end)
end)
