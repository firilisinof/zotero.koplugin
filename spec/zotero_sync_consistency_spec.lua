require("commonrequire")
package.path = "plugins/zotero.koplugin/?.lua;" .. package.path
local Env = require("spec.support.zotero_env")

local function page(version, body, count)
    return { headers = { ["last-modified-version"] = version, ["total-results"] = tostring(count or 0) },
        body = body or "[]" }
end

local function deletions(version, body)
    return { headers = { ["last-modified-version"] = version }, body = body or '{"items":[],"collections":[]}' }
end

describe("Zotero consistent metadata snapshots", function()
    local env, api, http
    before_each(function()
        env = Env.new()
        env:credentials()
        env:library()
        api, http = env.api, env.http
        api.setLibraryVersion("1200")
        api.setLastSync(7)
        api.saveModifiedItems()
    end)

    local function unchangedPages(version)
        http:on("GET", "/items%?", page(version))
        http:on("GET", "/collections%?", page(version))
    end

    local function assertPreserved()
        assert.is_not_nil(api.getItems().PARENT01)
        assert.is_not_nil(api.getCollections().COLLAAA1)
        assert.equal("1200", api.getLibraryVersion())
        assert.equal(7, api.getLastSync())
        for _, path in pairs(api.getSyncStage()) do assert.is_nil(api.util.read(path)) end
    end

    it("removes permanently deleted items and collections while preserving files and sidecars", function()
        local path = env:file("ATTACH01", "local document", 1201)
        assert.is_nil(api.util.write(path .. ".sidecar", "reading settings"))
        unchangedPages("1300")
        env:deletedRoute("1300", '{"items":["PARENT01","ATTACH01"],"collections":["COLLAAA1"]}')
        assert.is_nil(api.syncAllItems())
        api.init(api.zotero_dir)
        assert.is_nil(api.getItems().PARENT01)
        assert.is_nil(api.getItems().ATTACH01)
        assert.is_nil(api.getCollections().COLLAAA1)
        assert.is_not_nil(api.getCollections().COLLBBB2)
        assert.equal("local document", api.util.read(path))
        assert.equal("reading settings", api.util.read(path .. ".sidecar"))
        assert.equal("1300", api.getLibraryVersion())
        assert.truthy(http:urls()[3]:find("/deleted?since=1200", 1, true))
    end)

    it("applies deletions to a staged delta without losing other updates", function()
        http:on("GET", "/items%?", page("1300", '[{"key":"NEWITEM1","version":1300,"data":{"title":"New"}}]', 1))
        http:on("GET", "/collections%?", page("1300"))
        env:deletedRoute("1300", '{"items":["PARENT01","UNKNOWN1"],"collections":[]}')
        assert.is_nil(api.syncAllItems())
        assert.is_nil(api.getItems().PARENT01)
        assert.equal("New", api.getItems().NEWITEM1.data.title)
    end)

    it("keeps unchanged caches and index when deletion keys are already absent", function()
        -- First compact the fixture cache.
        unchangedPages("1300")
        env:deletedRoute("1300", '{"items":["UNKNOWN1"],"collections":["UNKNOWN2"]}')
        assert.is_nil(api.syncAllItems())
        local index = api.getIndex()
        assert.is_nil(api.syncAllItems())
        assert.is_true(rawequal(index, api.getIndex()))
    end)

    for _, failure in ipairs({
        { code = 403 }, { error = "offline" },
        deletions("1300", "not JSON"), deletions("1300", '{"items":[],"collections":null}'),
        deletions("1300", '{"items":[false],"collections":[]}'),
        deletions(nil),
    }) do
        it("retains live caches and cursor when deletion retrieval fails: " .. tostring(failure.body or failure.error or failure.code), function()
            local before = api.util.read(api.getCachePath("items"))
            unchangedPages("1300")
            http:on("GET", "/deleted%?", failure)
            assert.is_not_nil(api.syncAllItems())
            assert.equal(before, api.util.read(api.getCachePath("items")))
            assertPreserved()
        end)
    end

    it("restarts all pages from the saved cursor and discards entries from an inconsistent attempt", function()
        local transient = '[{"key":"GHOST001","version":1300,"data":{"title":"Transient"}}]'
        local stable = '[{"key":"NEWITEM1","version":1301,"data":{"title":"Stable"}}]'
        http:onSequence("GET", "/items%?.*start=0$", { page("1300", transient, 101), page("1301", stable, 101) })
        http:on("GET", "/items%?.*start=100$", page("1301", "[]", 101))
        http:on("GET", "/collections%?", page("1301"))
        env:deletedRoute("1301")
        assert.is_nil(api.syncAllItems())
        assert.is_nil(api.getItems().GHOST001)
        assert.equal("Stable", api.getItems().NEWITEM1.data.title)
        assert.equal("1301", api.getLibraryVersion())
        assert.equal(4, http:callCount("/items%?"))
        for _, url in ipairs(http:urls()) do assert.truthy(url:find("since=1200", 1, true)) end
    end)

    it("bounds retries when every pagination attempt races a change", function()
        http:on("GET", "/items%?.*start=0$", page("1300", "[]", 101))
        http:on("GET", "/items%?.*start=100$", page("1301", "[]", 101))
        assert.is_not_nil(api.syncAllItems())
        assert.equal(6, http:callCount())
        assertPreserved()
    end)

    it("retries when collections observe a newer library version", function()
        http:onSequence("GET", "/items%?", { page("1300"), page("1301") })
        http:on("GET", "/collections%?", page("1301"))
        env:deletedRoute("1301")
        assert.is_nil(api.syncAllItems())
        assert.equal(2, http:callCount("/items%?"))
        assert.equal("1301", api.getLibraryVersion())
    end)

    it("restarts after a deletion-feed race and does not retain a stale tombstone", function()
        http:onSequence("GET", "/items%?", { page("1300"), page("1302") })
        http:onSequence("GET", "/collections%?", { page("1300"), page("1302") })
        http:onSequence("GET", "/deleted%?", {
            deletions("1301", '{"items":["PARENT01"],"collections":[]}'), deletions("1302"),
        })
        assert.is_nil(api.syncAllItems())
        assert.is_not_nil(api.getItems().PARENT01)
        assert.equal("1302", api.getLibraryVersion())
    end)

    it("rejects a page with no library version without advancing state", function()
        http:on("GET", "/items%?", page(nil))
        assert.is_not_nil(api.syncAllItems())
        assert.equal(1, http:callCount())
        assertPreserved()
    end)
end)
