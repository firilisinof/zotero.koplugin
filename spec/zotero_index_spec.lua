-- Offline regression specs for the public API, run with make test.
require("commonrequire")
package.path = "plugins/zotero.koplugin/?.lua;" .. package.path
local Env = require("spec.support.zotero_env")
local Fixtures = require("spec.support.fixtures")
local Util = require("zoteroutil")
local lfs = require("libs/libkoreader-lfs")
local USER_ID, API_KEY = "4242", "s3cret"

describe("Zotero API client", function()
    local env, ZoteroAPI, fake
    before_each(function()
        env = Env.new()
        ZoteroAPI, fake = env.api, env.http
    end)

    describe("displayCollection", function()
        before_each(function() env:library() end)

        it("lists the top level collections at the root", function()
            assert.are.same(
                { "Papers/", "Zettelkasten/" },
                Env.texts(ZoteroAPI.displayCollection(nil))
            )
        end)

        it("lists subcollections before items, each group sorted by name", function()
            assert.are.same(
                { "Subfolder/", "A Standalone Report", "Vaswani et al. - Attention Is All You Need" },
                Env.texts(ZoteroAPI.displayCollection("COLLAAA1"))
            )
        end)

        it("names an attachment after its parent's author and title", function()
            local entries = ZoteroAPI.displayCollection("COLLAAA1")

            assert.is_equal("ATTACH01", entries[3].key)
            assert.is_equal("Vaswani et al. - Attention Is All You Need", entries[3].text)
        end)

        it("names a standalone attachment after its own title", function()
            local entries = ZoteroAPI.displayCollection("COLLAAA1")

            assert.is_equal("STANDAL1", entries[2].key)
        end)

        it("skips attachments whose media type is not readable", function()
            local texts = Env.texts(ZoteroAPI.displayCollection("COLLAAA1"))

            -- SNAPSHT1 is text/html and belongs to a PARENT01 in this collection.
            for _, text in ipairs(texts) do
                assert.is_not_equal("Snapshot", text)
            end
        end)

        it("marks collections so the browser can descend into them", function()
            local entries = ZoteroAPI.displayCollection("COLLAAA1")

            assert.is_true(entries[1].collection)
            assert.is_equal("COLLCCC3", entries[1].key)
            assert.is_nil(entries[2].collection)
        end)

        it("lists a subcollection's own items", function()
            assert.are.same(
                { "A Linked Paper", "Petzold - The Annotated Turing" },
                Env.texts(ZoteroAPI.displayCollection("COLLCCC3"))
            )
        end)

        it("returns nothing for an empty collection", function()
            assert.are.same({}, ZoteroAPI.displayCollection("COLLBBB2"))
        end)
    end)

    describe("displaySearchResults", function()
        before_each(function() env:library() end)

        it("matches the title", function()
            assert.are.same(
                { "Petzold - The Annotated Turing" },
                Env.texts(ZoteroAPI.displaySearchResults("annotated"))
            )
        end)

        it("matches the first author", function()
            local texts = Env.texts(ZoteroAPI.displaySearchResults("vaswani"))

            assert.is_equal(1, #texts)
            assert.is_equal("Vaswani et al. - Attention Is All You Need - 10.5555/3295222", texts[1])
        end)

        it("matches the DOI", function()
            assert.is_equal(1, #ZoteroAPI.displaySearchResults("3295222"))
        end)

        it("ignores case", function()
            assert.is_equal(1, #ZoteroAPI.displaySearchResults("VASWANI"))
        end)

        it("treats spaces as gaps, so words may be far apart", function()
            assert.is_equal(1, #ZoteroAPI.displaySearchResults("vaswani attention"))
        end)

        it("respects word order", function()
            assert.is_equal(0, #ZoteroAPI.displaySearchResults("attention vaswani"))
        end)

        it("matches a standalone attachment on its own title", function()
            assert.are.same(
                { "A Standalone Report" },
                Env.texts(ZoteroAPI.displaySearchResults("standalone"))
            )
        end)

        it("returns every readable attachment for an empty query", function()
            assert.is_equal(4, #ZoteroAPI.displaySearchResults(""))
        end)

        it("returns nothing when there is no match", function()
            assert.are.same({}, ZoteroAPI.displaySearchResults("nonexistent"))
        end)

        it("matches a hyphenated term literally", function()
            -- A hyphen is a Lua pattern quantifier, so an unescaped query for
            -- "all-you" used to match nothing at all.
            ZoteroAPI.setItems({
                P = { key = "P", version = 1, meta = { creatorSummary = "Ben-Kiki" },
                      data = { key = "P", itemType = "journalArticle",
                               title = "Well-Known Text", DOI = "", collections = {} } },
                A = { key = "A", version = 1, meta = {},
                      data = { key = "A", itemType = "attachment", linkMode = "imported_file",
                               contentType = "application/pdf", filename = "a.pdf",
                               parentItem = "P" } },
            })

            assert.is_equal(1, #ZoteroAPI.displaySearchResults("ben-kiki"))
            assert.is_equal(1, #ZoteroAPI.displaySearchResults("well-known"))
            assert.is_equal(1, #ZoteroAPI.displaySearchResults("ben-kiki well-known"))
            assert.is_equal(0, #ZoteroAPI.displaySearchResults("ben-kuki"))
        end)

        it("does not choke on other pattern characters", function()
            for _, query in ipairs({ "50%", "c++", "(draft)", "a.b", "[note]", "what?", "x$" }) do
                assert.has_no_error(function()
                    ZoteroAPI.displaySearchResults(query)
                end, "query: " .. query)
            end
        end)
    end)

    describe("buildSearchPattern", function()
        it("escapes pattern characters", function()
            assert.is_equal("ben%-kiki", ZoteroAPI.buildSearchPattern("Ben-Kiki"))
            assert.is_equal("50%%", ZoteroAPI.buildSearchPattern("50%"))
        end)

        it("joins words with a gap", function()
            assert.is_equal("one.*two", ZoteroAPI.buildSearchPattern("one two"))
        end)

        it("collapses runs of whitespace", function()
            assert.is_equal("one.*two", ZoteroAPI.buildSearchPattern("  one   two  "))
        end)

        it("stays unanchored rather than wrapping in .*", function()
            -- A leading ".*" matches the same strings but backtracks from every
            -- position, which dominated the cost of a search.
            assert.is_equal("", ZoteroAPI.buildSearchPattern(""))
            assert.is_truthy(string.match("a paper about cats", ZoteroAPI.buildSearchPattern("paper")))
            assert.is_truthy(string.match("anything at all", ZoteroAPI.buildSearchPattern("")))
        end)
    end)

    describe("attachments with an unusable parent", function()
        it("hides an orphaned attachment from collection listings", function()
            ZoteroAPI.setItems({
                ORPHAN01 = { key = "ORPHAN01", version = 1, meta = {},
                    data = { key = "ORPHAN01", itemType = "attachment",
                             linkMode = "imported_file", contentType = "application/pdf",
                             filename = "orphan.pdf", title = "Orphaned Attachment",
                             parentItem = "MISSING1", collections = { "COLLAAA1" } } },
            })
            ZoteroAPI.setCollections(Env.keyed(Fixtures.decode("collections.json")))

            assert.are.same({ "Subfolder/" }, Env.texts(ZoteroAPI.displayCollection("COLLAAA1")))
        end)

        it("still finds an orphaned attachment by its own title", function()
            ZoteroAPI.setItems({
                ORPHAN01 = { key = "ORPHAN01", version = 1, meta = {},
                    data = { key = "ORPHAN01", itemType = "attachment",
                             linkMode = "imported_file", contentType = "application/pdf",
                             filename = "orphan.pdf", title = "Orphaned Attachment",
                             parentItem = "MISSING1", collections = { "COLLAAA1" } } },
            })

            assert.are.same(
                { "Orphaned Attachment" },
                Env.texts(ZoteroAPI.displaySearchResults("orphaned"))
            )
        end)

        it("does not crash when the parent belongs to no collection", function()
            ZoteroAPI.setItems({
                P = { key = "P", version = 1, meta = { creatorSummary = "Author" },
                      data = { key = "P", itemType = "journalArticle", title = "Untitled" } },
                A = { key = "A", version = 1, meta = {},
                      data = { key = "A", itemType = "attachment", linkMode = "imported_file",
                               contentType = "application/pdf", filename = "a.pdf",
                               parentItem = "P" } },
            })
            ZoteroAPI.setCollections(Env.keyed(Fixtures.decode("collections.json")))

            assert.has_no_error(function() ZoteroAPI.displayCollection("COLLAAA1") end)
        end)
    end)

    describe("getDirAndPath", function()
        before_each(function() env:library() end)

        it("files an attachment under its parent item's key", function()
            local dir, path = ZoteroAPI.getDirAndPath("ATTACH01")

            assert.is_equal(ZoteroAPI.storage_dir .. "/PARENT01", dir)
            assert.is_equal(dir .. "/Vaswani et al. - 2017 - Attention Is All You Need.pdf", path)
        end)

        it("files a standalone attachment under its own key", function()
            local dir, path = ZoteroAPI.getDirAndPath("STANDAL1")

            assert.is_equal(ZoteroAPI.storage_dir .. "/STANDAL1", dir)
            assert.is_equal(dir .. "/standalone-report.pdf", path)
        end)

        it("returns nothing for an unknown key", function()
            local dir, path = ZoteroAPI.getDirAndPath("NOSUCHKY")

            assert.is_nil(dir)
            assert.is_nil(path)
        end)
    end)

end)
