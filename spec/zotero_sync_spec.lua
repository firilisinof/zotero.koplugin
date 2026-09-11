-- Offline specs for the compact item cache written by syncAllItems.
require("commonrequire")
package.path = "plugins/zotero.koplugin/?.lua;" .. package.path
local Env = require("spec.support.zotero_env")
local FakeHttp = require("spec.support.fake_http")
local lfs = require("libs/libkoreader-lfs")

describe("Zotero item cache sync", function()
    local env, api, fake
    before_each(function()
        env = Env.new()
        api, fake = env.api, env.http
        env:credentials()
    end)

    local function reloadedAPI()
        local reloaded = package.reload("zoteroapi")
        reloaded.init(api.zotero_dir)
        return reloaded
    end

    local function emptyDeltaRoutes()
        local headers = { ["total-results"] = "0", ["last-modified-version"] = "1300" }
        fake:on("GET", "/items%?", { headers = headers, body = "[]" })
        fake:on("GET", "/collections%?", { headers = headers, body = "[]" })
    end

    -- Routes match in registration order, so a later sync needs a server of its own.
    local function freshServer()
        env.http = FakeHttp.new()
        api.http, fake = env.http, env.http
    end

    -- Util.write replaces files by rename, so every rewrite gets a new inode.
    local function cacheInode(name)
        return lfs.attributes(api.zotero_dir .. "/" .. name .. ".json", "ino")
    end

    local function itemsDelta(body)
        fake:on("GET", "/items%?", { headers = { ["total-results"] = "1", ["last-modified-version"] = "1301" }, body = body })
        fake:on("GET", "/collections%?", { headers = { ["total-results"] = "0", ["last-modified-version"] = "1301" }, body = "[]" })
    end

    local function addAnnotation(key)
        local items = api.getItems()
        items[key] = { key = key, version = 1210, data = {
            itemType = "annotation", parentItem = "ATTACH01", annotationText = "Cached before trimming" } }
        api.setItems(items)
    end

    describe("compact cache", function()
        it("excludes annotations from the items request only", function()
            env:fullSyncRoutes()

            assert.is_nil(api.syncAllItems())

            local urls = fake:urls()
            assert.truthy(urls[1]:find("/items?since=0&includeTrashed=true&itemType=-annotation&", 1, true))
            assert.truthy(urls[3]:find("/collections?", 1, true))
            assert.falsy(urls[3]:find("itemType", 1, true))
        end)

        it("stores only the fields the plugin reads", function()
            env:fullSyncRoutes()

            assert.is_nil(api.syncAllItems())

            local items = reloadedAPI().getItems()
            assert.same({ key = "PARENT01", version = 1200,
                meta = { creatorSummary = "Vaswani et al.", parsedDate = "2017" },
                data = { itemType = "journalArticle", title = "Attention Is All You Need", date = "2017",
                    DOI = "10.5555/3295222", collections = { "COLLAAA1" }, tags = {} } }, items.PARENT01)
            assert.same({ key = "ATTACH01", version = 1201, data = {
                itemType = "attachment", parentItem = "PARENT01", linkMode = "imported_file", title = "Full Text PDF",
                contentType = "application/pdf", filename = "Vaswani et al. - 2017 - Attention Is All You Need.pdf",
                md5 = "5d41402abc4b2a76b9719d911017c592", tags = {} } }, items.ATTACH01)
        end)

        it("never stores an annotation the server returns", function()
            fake:on("GET", "/items%?", { headers = { ["total-results"] = "1" }, body = [==[
                [{"key":"ANNOT001","version":1210,
                  "data":{"key":"ANNOT001","itemType":"annotation","parentItem":"ATTACH01"}}]
            ]==] })
            fake:on("GET", "/collections%?", { headers = { ["total-results"] = "0" }, body = "[]" })

            assert.is_nil(api.syncAllItems())

            assert.is_nil(api.getItems().ANNOT001)
        end)

        it("prunes annotations and full objects cached before trimming", function()
            env:library()
            addAnnotation("ANNOT001")
            emptyDeltaRoutes()

            assert.is_nil(api.syncAllItems())

            local items = reloadedAPI().getItems()
            assert.is_nil(items.ANNOT001)
            assert.is_nil(items.PARENT01.library)
            assert.is_nil(items.PARENT01.meta.numChildren)
            assert.is_nil(items.PARENT01.data.creators)
            assert.is_nil(items.ATTACH01.data.mtime)
            assert.equal("Attention Is All You Need", items.PARENT01.data.title)
        end)

        it("browses, searches and reads notes from the pruned cache as before", function()
            env:library()
            local collection = api.displayCollection("COLLAAA1")
            local search = api.displaySearchResults("")
            local notes = api.getItemNotes("ATTACH01")
            emptyDeltaRoutes()

            assert.is_nil(api.syncAllItems())

            local reloaded = reloadedAPI()
            assert.same(collection, reloaded.displayCollection("COLLAAA1"))
            assert.same(search, reloaded.displaySearchResults(""))
            assert.same(notes, reloaded.getItemNotes("ATTACH01"))
        end)
    end)

    describe("unchanged deltas", function()
        before_each(function()
            env:fullSyncRoutes()
            assert.is_nil(api.syncAllItems())
            freshServer()
        end)

        it("keep both caches and the index but still record the sync", function()
            local items, collections, index = cacheInode("items"), cacheInode("collections"), api.getIndex()
            api.setLastSync(1)
            emptyDeltaRoutes()

            assert.is_nil(api.syncAllItems())

            assert.equal(items, cacheInode("items"))
            assert.equal(collections, cacheInode("collections"))
            assert.is_true(rawequal(index, api.getIndex()))
            assert.equal("1300", api.getLibraryVersion())
            assert.is_true(api.getLastSync() > 1)
        end)

        it("ignore entries the server repeats at known versions", function()
            local items, collections, index = cacheInode("items"), cacheInode("collections"), api.getIndex()
            env:fullSyncRoutes()

            assert.is_nil(api.syncAllItems())

            assert.equal(items, cacheInode("items"))
            assert.equal(collections, cacheInode("collections"))
            assert.is_true(rawequal(index, api.getIndex()))
        end)

        it("still rewrite only the cache holding a new version", function()
            local items, collections, index = cacheInode("items"), cacheInode("collections"), api.getIndex()
            itemsDelta([==[[{"key":"PARENT01","version":1301,
                "data":{"itemType":"journalArticle","title":"Renamed","collections":["COLLAAA1"]}}]]==])

            assert.is_nil(api.syncAllItems())

            assert.are_not.equal(items, cacheInode("items"))
            assert.equal(collections, cacheInode("collections"))
            assert.is_false(rawequal(index, api.getIndex()))
            assert.equal("Renamed", reloadedAPI().getItems().PARENT01.data.title)
        end)

        it("still rewrite the items cache when a known item is deleted", function()
            local items = cacheInode("items")
            itemsDelta([==[[{"key":"NOTE0001","version":1301,"data":{"itemType":"note","deleted":1}}]]==])

            assert.is_nil(api.syncAllItems())

            assert.are_not.equal(items, cacheInode("items"))
            assert.is_nil(reloadedAPI().getItems().NOTE0001)
        end)
    end)
end)
