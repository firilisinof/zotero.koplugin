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

    describe("init", function()
        it("drops the library cached from a previous directory", function()
            env:library()
            assert.is_not_nil(ZoteroAPI.getItems()["PARENT01"])

            ZoteroAPI.init(Env.newDirectory())

            assert.is_nil(next(ZoteroAPI.getItems()))
            assert.is_nil(next(ZoteroAPI.getCollections()))
        end)

        it("creates the storage directory", function()
            assert.is_not_nil(lfs.attributes(ZoteroAPI.storage_dir))
        end)
    end)

    describe("settings", function()
        it("round-trips the account credentials", function()
            env:credentials(USER_ID, API_KEY)

            assert.is_equal(USER_ID, ZoteroAPI.getUserID())
            assert.is_equal(API_KEY, ZoteroAPI.getAPIKey())
        end)

        it("round-trips the WebDAV credentials", function()
            ZoteroAPI.setWebDAVUrl("https://cloud.example.org/remote.php/dav/zotero")
            ZoteroAPI.setWebDAVUser("lucas")
            ZoteroAPI.setWebDAVPassword("hunter2")

            assert.is_equal("https://cloud.example.org/remote.php/dav/zotero", ZoteroAPI.getWebDAVUrl())
            assert.is_equal("lucas", ZoteroAPI.getWebDAVUser())
            assert.is_equal("hunter2", ZoteroAPI.getWebDAVPassword())
        end)

        it("has WebDAV disabled until toggled", function()
            assert.is_false(ZoteroAPI.getWebDAVEnabled())

            ZoteroAPI.toggleWebDAVEnabled()

            assert.is_true(ZoteroAPI.getWebDAVEnabled())
        end)

        it("starts at library version 0", function()
            assert.is_equal("0", ZoteroAPI.getLibraryVersion())
        end)

        it("round-trips the filter tag", function()
            assert.is_equal("", ZoteroAPI.getFilterTag())

            ZoteroAPI.setFilterTag("to-read")

            assert.is_equal("to-read", ZoteroAPI.getFilterTag())
        end)
    end)

    describe("ensureKeyAndID", function()
        it("reports a missing user ID", function()
            assert.is_equal("Error: must set User ID", ZoteroAPI.ensureKeyAndID())
        end)

        it("reports a missing API key", function()
            ZoteroAPI.setUserID(USER_ID)

            assert.is_equal("Error: must set API Key", ZoteroAPI.ensureKeyAndID())
        end)

        it("returns the credentials once both are set", function()
            env:credentials(USER_ID, API_KEY)

            local e, api_key, user_id = ZoteroAPI.ensureKeyAndID()

            assert.is_nil(e)
            assert.is_equal(API_KEY, api_key)
            assert.is_equal(USER_ID, user_id)
        end)
    end)

    describe("verifyResponse", function()
        it("accepts a successful request", function()
            assert.is_nil(ZoteroAPI.verifyResponse(1, 200))
        end)

        it("reports a transport failure", function()
            assert.is_equal("Error: connection refused", ZoteroAPI.verifyResponse(nil, "connection refused"))
        end)

        it("reports an unsuccessful status code", function()
            assert.is_equal("Error: API responded with status code 403", ZoteroAPI.verifyResponse(1, 403))
        end)
    end)

    describe("cutDecimalPlaces", function()
        it("truncates towards zero", function()
            assert.is_equal(3.1415, ZoteroAPI.cutDecimalPlaces(math.pi, 4))
            assert.is_equal(10, ZoteroAPI.cutDecimalPlaces(10.12341234, 0))
        end)

        it("leaves shorter numbers alone", function()
            assert.is_equal(10, ZoteroAPI.cutDecimalPlaces(10, 4))
        end)
    end)

    describe("timestamps", function()
        it("reads a KOReader timestamp as local time and prints it as UTC", function()
            local expected = os.date("!%Y-%m-%dT%H:%M:%SZ", os.time({
                year = 2022, month = 9, day = 22, hour = 18, min = 9, sec = 12,
            }))

            assert.is_equal(expected, ZoteroAPI.addTimezone("2022-09-22 18:09:12"))
        end)

        it("compares a Zotero timestamp against a KOReader one", function()
            local at_12 = ZoteroAPI.addTimezone("2022-09-22 18:09:12")
            local at_13 = ZoteroAPI.addTimezone("2022-09-22 18:09:13")

            assert.is_equal(0, ZoteroAPI.compareTimestamps(at_12, "2022-09-22 18:09:12"))
            assert.is_equal(-1, ZoteroAPI.compareTimestamps(at_12, "2022-09-22 18:09:13"))
            assert.is_equal(1, ZoteroAPI.compareTimestamps(at_13, "2022-09-22 18:09:12"))
        end)
    end)

    describe("socket timeouts", function()
        local socketutil = require("socketutil")

        it("restores the default timeout after a request", function()
            fake:on("GET", "/items", { headers = { ["total-results"] = "0" }, body = "[]" })

            ZoteroAPI.fetchCollectionPaginated("https://api.zotero.org/users/4242/items?since=0", {})

            assert.is_equal(socketutil.DEFAULT_BLOCK_TIMEOUT, socketutil.block_timeout)
        end)

        it("restores the default timeout even when the request fails", function()
            fake:on("GET", "/items", { error = "connection refused" })

            ZoteroAPI.fetchCollectionPaginated("https://api.zotero.org/users/4242/items?since=0", {})

            assert.is_equal(socketutil.DEFAULT_BLOCK_TIMEOUT, socketutil.block_timeout)
        end)

        it("bounds a download so a stalled server cannot hang the reader", function()
            env:credentials(USER_ID, API_KEY)
            env:library()
            local seen
            fake:on("GET", "/items/ATTACH01/file", { body = "x" })
            local plain_request = fake.request
            fake.request = function(reqt)
                seen = socketutil.block_timeout
                return plain_request(reqt)
            end

            ZoteroAPI.downloadAndGetPath("ATTACH01")

            assert.is_equal(socketutil.FILE_BLOCK_TIMEOUT, seen)
            assert.is_equal(socketutil.DEFAULT_BLOCK_TIMEOUT, socketutil.block_timeout)
        end)
    end)

    describe("fetchCollectionPaginated", function()
        local URL = "https://api.zotero.org/users/4242/items?since=0"

        it("returns every entry when given no callback", function()
            fake:on("GET", "/items%?", {
                headers = { ["total-results"] = "5" },
                body = Fixtures.raw("items_page1.json"),
            })

            local items, e = ZoteroAPI.fetchCollectionPaginated(URL, {})

            assert.is_nil(e)
            assert.is_equal(5, #items)
            assert.is_equal("PARENT01", items[1].key)
        end)

        it("requests one page per hundred entries", function()
            fake:on("GET", "/items%?.*start=0$", {
                headers = { ["total-results"] = "150" },
                body = Fixtures.raw("items_page1.json"),
            })
            fake:on("GET", "/items%?.*start=100$", {
                headers = { ["total-results"] = "150" },
                body = Fixtures.raw("items_page2.json"),
            })

            local items, e = ZoteroAPI.fetchCollectionPaginated(URL, {})

            assert.is_nil(e)
            assert.is_equal(10, #items)
            assert.is_equal(2, fake:callCount())
        end)

        it("does not ask for a page past the end of an exact multiple", function()
            fake:on("GET", "/items%?", {
                headers = { ["total-results"] = "100" },
                body = Fixtures.raw("items_page1.json"),
            })

            ZoteroAPI.fetchCollectionPaginated(URL, {})

            assert.is_equal(1, fake:callCount())
        end)

        it("reads the collection size from the page itself", function()
            fake:on("GET", "/items%?", { headers = { ["total-results"] = "0" }, body = "[]" })

            local items, e = ZoteroAPI.fetchCollectionPaginated(URL, {})

            assert.is_nil(e)
            assert.are.same({}, items)
            -- No separate HEAD request to size the collection first.
            assert.is_equal(1, fake:callCount())
            assert.is_equal("GET", fake.calls[1].method)
        end)

        it("hands each page to the callback and returns the library version", function()
            fake:on("GET", "/items%?", {
                headers = { ["total-results"] = "5", ["last-modified-version"] = "1214" },
                body = Fixtures.raw("items_page1.json"),
            })

            local pages = {}
            local version, e = ZoteroAPI.fetchCollectionPaginated(URL, {}, function(entries)
                table.insert(pages, entries)
            end)

            assert.is_nil(e)
            assert.is_equal("1214", version)
            assert.is_equal(1, #pages)
            assert.is_equal(5, #pages[1])
        end)

        it("reports malformed JSON", function()
            fake:on("GET", "/items%?", {
                headers = { ["total-results"] = "1" },
                body = "<html>gateway timeout</html>",
            })

            local items, e = ZoteroAPI.fetchCollectionPaginated(URL, {})

            assert.is_nil(items)
            assert.is_equal("Error: failed to parse JSON in response", e)
        end)

        it("reports a page without a usable size", function()
            fake:on("GET", "/items%?", { headers = {}, body = "[]" })

            local items, e = ZoteroAPI.fetchCollectionPaginated(URL, {})

            assert.is_nil(items)
            assert.is_equal("Error: could not determine number of items in library", e)
        end)

        it("propagates a transport failure without touching the missing headers", function()
            fake:on("GET", "/items%?", { error = "connection refused" })

            local items, e = ZoteroAPI.fetchCollectionPaginated(URL, {})

            assert.is_nil(items)
            assert.is_equal("Error: connection refused", e)
        end)

        it("propagates an unsuccessful status code", function()
            fake:on("GET", "/items%?", { code = 403, headers = {}, body = "" })

            local items, e = ZoteroAPI.fetchCollectionPaginated(URL, {})

            assert.is_nil(items)
            assert.is_equal("Error: API responded with status code 403", e)
        end)
    end)

    describe("syncAllItems", function()
        it("refuses to run without credentials", function()
            assert.is_equal("Error: must set User ID", ZoteroAPI.syncAllItems())
            assert.is_equal(0, fake:callCount())
        end)

        it("stores items and collections keyed by their Zotero key", function()
            env:credentials(USER_ID, API_KEY)
            env:fullSyncRoutes()

            assert.is_nil(ZoteroAPI.syncAllItems())

            local items = ZoteroAPI.getItems()
            assert.is_equal("Attention Is All You Need", items["PARENT01"].data.title)
            assert.is_equal("application/pdf", items["ATTACH01"].data.contentType)

            local collections = ZoteroAPI.getCollections()
            assert.is_equal("Papers", collections["COLLAAA1"].data.name)
            assert.is_equal("COLLAAA1", collections["COLLCCC3"].data.parentCollection)
        end)

        it("drops items the server marks as deleted", function()
            env:credentials(USER_ID, API_KEY)
            env:fullSyncRoutes()

            assert.is_nil(ZoteroAPI.syncAllItems())

            assert.is_nil(ZoteroAPI.getItems()["DELETED1"])
        end)

        it("drops items whose deleted flag is a boolean rather than 1", function()
            env:credentials(USER_ID, API_KEY)
            fake:on("GET", "/items%?", {
                headers = { ["total-results"] = "1" },
                body = [==[
                    [{"key":"GONE0001","version":9,
                      "data":{"key":"GONE0001","version":9,"itemType":"note","deleted":true}}]
                ]==],
            })
            fake:on("GET", "/collections%?", { headers = { ["total-results"] = "0" }, body = "[]" })

            assert.is_nil(ZoteroAPI.syncAllItems())

            assert.is_nil(ZoteroAPI.getItems()["GONE0001"])
        end)

        it("keeps items that were synced earlier", function()
            env:credentials(USER_ID, API_KEY)
            env:library()
            fake:on("GET", "/items%?", { headers = { ["total-results"] = "0" }, body = "[]" })
            fake:on("GET", "/collections%?", { headers = { ["total-results"] = "0" }, body = "[]" })

            assert.is_nil(ZoteroAPI.syncAllItems())

            assert.is_not_nil(ZoteroAPI.getItems()["PARENT01"])
        end)

        it("records the earlier of the two reported library versions", function()
            -- The items fetch reports 1214 and the collections fetch 1240.
            -- Storing 1240 would make the next sync ask for changes since then
            -- and permanently miss anything modified in between.
            env:credentials(USER_ID, API_KEY)
            env:fullSyncRoutes()

            assert.is_nil(ZoteroAPI.syncAllItems())

            assert.is_equal("1214", ZoteroAPI.getLibraryVersion())
        end)

        it("asks the server only for changes since the stored version", function()
            env:credentials(USER_ID, API_KEY)
            ZoteroAPI.setLibraryVersion("1100")
            env:fullSyncRoutes()

            ZoteroAPI.syncAllItems()

            assert.is_not_nil(string.find(fake:urls()[1], "since=1100", 1, true))
        end)

        it("propagates an error from the items fetch", function()
            env:credentials(USER_ID, API_KEY)
            fake:on("GET", "/items%?", { error = "connection refused" })

            assert.is_equal("Error: connection refused", ZoteroAPI.syncAllItems())
        end)

        it("writes the library to disk so a later run can read it back", function()
            env:credentials(USER_ID, API_KEY)
            env:fullSyncRoutes()
            ZoteroAPI.syncAllItems()

            local reloaded = package.reload("zoteroapi")
            reloaded.init(ZoteroAPI.zotero_dir)

            assert.is_equal("Attention Is All You Need", reloaded.getItems()["PARENT01"].data.title)
            assert.is_equal("Papers", reloaded.getCollections()["COLLAAA1"].data.name)
        end)
    end)

    describe("earlierVersion", function()
        it("picks the lower of two versions", function()
            assert.is_equal("1214", ZoteroAPI.earlierVersion("1214", "1240"))
            assert.is_equal("1214", ZoteroAPI.earlierVersion("1240", "1214"))
        end)

        it("compares numerically rather than as text", function()
            assert.is_equal("99", ZoteroAPI.earlierVersion("99", "100"))
        end)

        it("falls back to whichever version is present", function()
            assert.is_equal("1240", ZoteroAPI.earlierVersion(nil, "1240"))
            assert.is_equal("1214", ZoteroAPI.earlierVersion("1214", nil))
        end)
    end)

    describe("resetSyncState", function()
        it("empties the library and rewinds the version", function()
            env:library()
            ZoteroAPI.setLibraryVersion("1240")

            ZoteroAPI.resetSyncState()

            assert.is_nil(next(ZoteroAPI.getItems()))
            assert.is_nil(next(ZoteroAPI.getCollections()))
            assert.is_equal(0, ZoteroAPI.getLibraryVersion())
        end)
    end)

end)
