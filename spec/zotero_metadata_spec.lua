require("commonrequire")
package.path = "plugins/zotero.koplugin/?.lua;" .. package.path
local Env = require("spec.support.zotero_env")

describe("Zotero display metadata", function()
    local env, api
    before_each(function()
        env = Env.new()
        env:library()
        api = env.api
    end)

    -- Presence is filled in for the rows a view actually shows, never cached in the index.
    local function presence(rows)
        api.markDownloaded(rows)
        return rows
    end

    it("uses publication metadata and the attachment media type in both views", function()
        for _, row in ipairs({ presence(api.displayCollection("COLLAAA1"))[3],
            presence(api.displaySearchResults("attention"))[1] }) do
            assert.equals("Attention Is All You Need", row.title)
            assert.equals("Vaswani et al.", row.author)
            assert.equals("2017", row.year)
            assert.equals("PDF", row.file_format)
            assert.is_true(row.downloadable)
            assert.is_false(row.downloaded)
        end
        assert.equals("EPUB", api.displaySearchResults("turing")[1].file_format)
        assert.is_false(api.displaySearchResults("linked")[1].downloadable)
    end)

    it("omits missing or blank authors and dates without changing the title", function()
        for _, meta in ipairs({ {}, { creatorSummary = "  ", parsedDate = "" } }) do
            local items = api.getItems()
            items.PARENT01.meta, items.PARENT01.data.date = meta, "undated"
            api.setItems(items)
            local row = api.displaySearchResults("attention")[1]
            assert.equals("Attention Is All You Need", row.title)
            assert.is_nil(row.author)
            assert.is_nil(row.year)
        end
    end)

    it("extracts the publication year from parsed dates or the publication date", function()
        local items = api.getItems()
        items.PARENT01.meta.parsedDate = "2017-06-12"
        items.PARENT01.data.date = "June 2018"
        api.setItems(items)
        assert.equals("2017", api.displaySearchResults("attention")[1].year)
        items.PARENT01.meta.parsedDate = nil
        api.setItems(items)
        assert.equals("2018", api.displaySearchResults("attention")[1].year)
        items.PARENT01.data.date = "12345"
        api.setItems(items)
        assert.is_nil(api.displaySearchResults("attention")[1].year)
    end)

    it("uses standalone and orphan titles, falling back to filenames", function()
        env:attachment("ORPHAN", "MISSING", "orphan.pdf")
        local items = api.getItems()
        items.ORPHAN.data.title = "Orphan title"
        api.setItems(items)
        assert.equals("Orphan title", api.displaySearchResults("orphan")[1].title)
        assert.equals("A Standalone Report", api.displaySearchResults("standalone")[1].title)
        items.ORPHAN.data.title, items.STANDAL1.data.title = "  ", nil
        api.setItems(items)
        local orphan = api.displaySearchResults("orphan.pdf")[1]
        local standalone = api.displaySearchResults("standalone-report.pdf")[1]
        assert.equals("orphan.pdf", orphan.title)
        assert.equals("standalone-report.pdf", standalone.title)
        assert.is_nil(standalone.author)
        assert.is_nil(standalone.year)
        local keys = {}
        for _, row in ipairs(api.displayCollection("COLLAAA1")) do keys[#keys + 1] = row.key end
        assert.same({ "COLLCCC3", "ATTACH01", "STANDAL1" }, keys)
    end)

    it("falls back when even publication titles and attachment filenames are absent", function()
        local items = api.getItems()
        items.PARENT01.data.title = ""
        api.setItems(items)
        assert.equals("Full Text PDF", api.displaySearchResults("vaswani")[1].title)
        items.PARENT01.data.title = nil
        items.ATTACH01.data.title, items.ATTACH01.data.filename = nil, nil
        api.setItems(items)
        local row = presence(api.displaySearchResults("vaswani"))[1]
        assert.is_nil(row.title)
        assert.is_false(row.downloaded)
    end)

    it("preserves author-first sorting, key ties and ordered search matching", function()
        env:attachment("ATTACH03", "PARENT01", "duplicate.pdf")
        local items = api.getItems()
        items.PARENT01.data.title = "A title before all others"
        api.setItems(items)
        local function keys(rows)
            local result = {}
            for _, row in ipairs(rows) do result[#result + 1] = row.key end
            return result
        end
        assert.same({ "COLLCCC3", "STANDAL1", "ATTACH01", "ATTACH03" }, keys(api.displayCollection("COLLAAA1")))
        assert.same({ "LINKED01", "STANDAL1", "ATTACH02", "ATTACH01", "ATTACH03" }, keys(api.displaySearchResults("")))
        assert.equals(2, #api.displaySearchResults("VASWANI title 3295222"))
        assert.equals(0, #api.displaySearchResults("title vaswani"))
        assert.equals(0, #api.displaySearchResults("2017"))
        assert.equals(0, #api.displaySearchResults("Full Text PDF"))
    end)

    it("keeps the DOI in search ordering without displaying it in the title", function()
        local items = api.getItems()
        items.OTHER = { key = "OTHER", meta = { creatorSummary = "Vaswani et al." },
            data = { itemType = "journalArticle", title = "Attention Is All You Need",
                DOI = "10.0000/earlier", collections = { "COLLAAA1" } } }
        api.setItems(items)
        env:attachment("ZZZZ", "OTHER", "other.pdf")
        local collection, search = api.displayCollection("COLLAAA1"), api.displaySearchResults("attention")
        assert.equals("ATTACH01", collection[3].key)
        assert.equals("ZZZZ", collection[4].key)
        assert.equals("ZZZZ", search[1].key)
        assert.equals("ATTACH01", search[2].key)
        assert.equals("Attention Is All You Need", search[1].title)
        assert.equals("ZZZZ", api.displaySearchResults("10.0000/earlier")[1].key)
    end)

    it("refreshes file presence on cached rows and isolates display metadata mutations", function()
        local cached = api.getIndex()
        local row = api.displaySearchResults("attention")[1]
        row.title, row.author = "edited", "edited"
        local path = env:file("ATTACH01")
        assert.is_true(presence(api.displaySearchResults("attention"))[1].downloaded)
        assert.is_true(presence(api.displayCollection("COLLAAA1"))[3].downloaded)
        os.remove(path)
        assert.is_false(presence(api.displaySearchResults("attention"))[1].downloaded)
        assert.equals("Attention Is All You Need", api.displaySearchResults("attention")[1].title)
        assert.equals(cached, api.getIndex())
        assert.is_nil(cached.searchable[4].downloaded)
    end)
end)
