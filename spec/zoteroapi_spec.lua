--[[--
Specs for the Zotero API client.

Run with `make test` from the plugin directory, which shells out to
`kodev test front zoteroapi` in the KOReader checkout.

Every test runs offline: `ZoteroAPI.http` is swapped for a FakeHttp instance
serving the canned responses in spec/fixtures/.
]]

require("commonrequire")

-- The plugin is symlinked into the KOReader checkout as
-- plugins/zotero.koplugin, and the test runner's working directory is the
-- emulator's koreader directory. Left in place for the whole file so that
-- package.reload() keeps working in before_each.
package.path = "plugins/zotero.koplugin/?.lua;" .. package.path

local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local FakeHttp = require("spec.support.fake_http")
local Fixtures = require("spec.support.fixtures")

local USER_ID = "4242"
local API_KEY = "s3cret"

describe("Zotero API client", function()
    local ZoteroAPI
    local fake
    local run = 0

    -- A directory per test, so nothing leaks between them. KO_HOME is wiped by
    -- the test runner before each session, so there is nothing to clean up.
    local function new_zotero_dir()
        run = run + 1
        local root = DataStorage:getDataDir() .. "/zotero_spec"
        lfs.mkdir(root)
        local dir = root .. "/run" .. run
        lfs.mkdir(dir)
        return dir
    end

    local function keyed(entries)
        local map = {}
        for _, entry in ipairs(entries) do
            map[entry.key] = entry
        end
        return map
    end

    -- Populates the local cache as a completed sync would have left it.
    local function load_library()
        local items = keyed(Fixtures.decode("items_page1.json"))
        for key, item in pairs(keyed(Fixtures.decode("items_page2.json"))) do
            items[key] = item
        end
        items["DELETED1"] = nil -- a sync drops trashed items
        ZoteroAPI.setItems(items)
        ZoteroAPI.setCollections(keyed(Fixtures.decode("collections.json")))
    end

    local function set_credentials()
        ZoteroAPI.setUserID(USER_ID)
        ZoteroAPI.setAPIKey(API_KEY)
    end

    local function texts_of(entries)
        local result = {}
        for i, entry in ipairs(entries) do
            result[i] = entry.text
        end
        return result
    end

    local function file_contents(path)
        local f = io.open(path, "r")
        if f == nil then return nil end
        local content = f:read("*all")
        f:close()
        return content
    end

    -- Serves both paginated collections a full sync walks through.
    local function stub_full_sync()
        fake:on("HEAD", "/items%?", { headers = { ["total-results"] = "150" } })
        fake:on("GET", "/items%?.*start=0$", {
            headers = { ["last-modified-version"] = "1214" },
            body = Fixtures.raw("items_page1.json"),
        })
        fake:on("GET", "/items%?.*start=100$", {
            headers = { ["last-modified-version"] = "1214" },
            body = Fixtures.raw("items_page2.json"),
        })
        fake:on("HEAD", "/collections%?", { headers = { ["total-results"] = "3" } })
        fake:on("GET", "/collections%?.*start=0$", {
            headers = { ["last-modified-version"] = "1240" },
            body = Fixtures.raw("collections.json"),
        })
    end

    before_each(function()
        -- API keeps its parsed library in module-level fields that init() does
        -- not clear, so the module itself has to be reloaded per test.
        ZoteroAPI = package.reload("zoteroapi")
        fake = FakeHttp.new()
        ZoteroAPI.http = fake
        ZoteroAPI.init(new_zotero_dir())
    end)

    describe("settings", function()
        it("round-trips the account credentials", function()
            set_credentials()

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
            set_credentials()

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

    describe("fetchCollectionSize", function()
        it("reads the total-results header", function()
            fake:on("HEAD", "/items", { headers = { ["total-results"] = "42" } })

            local size, e = ZoteroAPI.fetchCollectionSize("https://api.zotero.org/users/4242/items", {})

            assert.is_nil(e)
            assert.is_equal(42, size)
        end)

        it("fails when the header is missing", function()
            fake:on("HEAD", "/items", { headers = {} })

            local size, e = ZoteroAPI.fetchCollectionSize("https://api.zotero.org/users/4242/items", {})

            assert.is_nil(size)
            assert.is_equal("Error: could not determine number of items in library", e)
        end)

        it("propagates a transport failure", function()
            fake:on("HEAD", "/items", { error = "connection refused" })

            local size, e = ZoteroAPI.fetchCollectionSize("https://api.zotero.org/users/4242/items", {})

            assert.is_nil(size)
            assert.is_equal("Error: connection refused", e)
        end)

        it("propagates an unsuccessful status code", function()
            fake:on("HEAD", "/items", { code = 403, headers = {} })

            local size, e = ZoteroAPI.fetchCollectionSize("https://api.zotero.org/users/4242/items", {})

            assert.is_nil(size)
            assert.is_equal("Error: API responded with status code 403", e)
        end)
    end)

    describe("fetchCollectionPaginated", function()
        local URL = "https://api.zotero.org/users/4242/items?since=0"

        it("returns every entry when given no callback", function()
            fake:on("HEAD", "/items%?", { headers = { ["total-results"] = "5" } })
            fake:on("GET", "/items%?", { body = Fixtures.raw("items_page1.json") })

            local items, e = ZoteroAPI.fetchCollectionPaginated(URL, {})

            assert.is_nil(e)
            assert.is_equal(5, #items)
            assert.is_equal("PARENT01", items[1].key)
        end)

        it("requests one page per hundred entries", function()
            fake:on("HEAD", "/items%?", { headers = { ["total-results"] = "150" } })
            fake:on("GET", "/items%?.*start=0$", { body = Fixtures.raw("items_page1.json") })
            fake:on("GET", "/items%?.*start=100$", { body = Fixtures.raw("items_page2.json") })

            local items, e = ZoteroAPI.fetchCollectionPaginated(URL, {})

            assert.is_nil(e)
            assert.is_equal(10, #items)
            assert.is_equal(2, fake:callCount("&start="))
        end)

        it("hands each page to the callback and returns the library version", function()
            fake:on("HEAD", "/items%?", { headers = { ["total-results"] = "5" } })
            fake:on("GET", "/items%?", {
                headers = { ["last-modified-version"] = "1214" },
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
            fake:on("HEAD", "/items%?", { headers = { ["total-results"] = "1" } })
            fake:on("GET", "/items%?", { body = "<html>gateway timeout</html>" })

            local items, e = ZoteroAPI.fetchCollectionPaginated(URL, {})

            assert.is_nil(items)
            assert.is_equal("Error: failed to parse JSON in response", e)
        end)

        it("propagates a failure while determining the size", function()
            fake:on("HEAD", "/items%?", { error = "connection refused" })

            local items, e = ZoteroAPI.fetchCollectionPaginated(URL, {})

            assert.is_nil(items)
            assert.is_equal("Error: connection refused", e)
        end)
    end)

    describe("syncAllItems", function()
        it("refuses to run without credentials", function()
            assert.is_equal("Error: must set User ID", ZoteroAPI.syncAllItems())
            assert.is_equal(0, fake:callCount())
        end)

        it("stores items and collections keyed by their Zotero key", function()
            set_credentials()
            stub_full_sync()

            assert.is_nil(ZoteroAPI.syncAllItems())

            local items = ZoteroAPI.getItems()
            assert.is_equal("Attention Is All You Need", items["PARENT01"].data.title)
            assert.is_equal("application/pdf", items["ATTACH01"].data.contentType)

            local collections = ZoteroAPI.getCollections()
            assert.is_equal("Papers", collections["COLLAAA1"].data.name)
            assert.is_equal("COLLAAA1", collections["COLLCCC3"].data.parentCollection)
        end)

        it("drops items the server marks as deleted", function()
            set_credentials()
            stub_full_sync()

            assert.is_nil(ZoteroAPI.syncAllItems())

            assert.is_nil(ZoteroAPI.getItems()["DELETED1"])
        end)

        it("drops items whose deleted flag is a boolean rather than 1", function()
            set_credentials()
            fake:on("HEAD", "/items%?", { headers = { ["total-results"] = "1" } })
            fake:on("GET", "/items%?", {
                body = [==[
                    [{"key":"GONE0001","version":9,
                      "data":{"key":"GONE0001","version":9,"itemType":"note","deleted":true}}]
                ]==],
            })
            fake:on("HEAD", "/collections%?", { headers = { ["total-results"] = "0" } })
            fake:on("GET", "/collections%?", { body = "[]" })

            assert.is_nil(ZoteroAPI.syncAllItems())

            assert.is_nil(ZoteroAPI.getItems()["GONE0001"])
        end)

        it("keeps items that were synced earlier", function()
            set_credentials()
            load_library()
            fake:on("HEAD", "/items%?", { headers = { ["total-results"] = "0" } })
            fake:on("GET", "/items%?", { body = "[]" })
            fake:on("HEAD", "/collections%?", { headers = { ["total-results"] = "0" } })
            fake:on("GET", "/collections%?", { body = "[]" })

            assert.is_nil(ZoteroAPI.syncAllItems())

            assert.is_not_nil(ZoteroAPI.getItems()["PARENT01"])
        end)

        it("records the library version reported by the collections fetch", function()
            set_credentials()
            stub_full_sync()

            assert.is_nil(ZoteroAPI.syncAllItems())

            assert.is_equal("1240", ZoteroAPI.getLibraryVersion())
        end)

        it("asks the server only for changes since the stored version", function()
            set_credentials()
            ZoteroAPI.setLibraryVersion("1100")
            stub_full_sync()

            ZoteroAPI.syncAllItems()

            assert.is_not_nil(string.find(fake:urls()[1], "since=1100", 1, true))
        end)

        it("propagates an error from the items fetch", function()
            set_credentials()
            fake:on("HEAD", "/items%?", { error = "connection refused" })

            assert.is_equal("Error: connection refused", ZoteroAPI.syncAllItems())
        end)

        it("writes the library to disk so a later run can read it back", function()
            set_credentials()
            stub_full_sync()
            ZoteroAPI.syncAllItems()

            local reloaded = package.reload("zoteroapi")
            reloaded.init(ZoteroAPI.zotero_dir)

            assert.is_equal("Attention Is All You Need", reloaded.getItems()["PARENT01"].data.title)
            assert.is_equal("Papers", reloaded.getCollections()["COLLAAA1"].data.name)
        end)
    end)

    describe("resetSyncState", function()
        it("empties the library and rewinds the version", function()
            load_library()
            ZoteroAPI.setLibraryVersion("1240")

            ZoteroAPI.resetSyncState()

            assert.is_nil(next(ZoteroAPI.getItems()))
            assert.is_nil(next(ZoteroAPI.getCollections()))
            assert.is_equal(0, ZoteroAPI.getLibraryVersion())
        end)
    end)

    describe("displayCollection", function()
        before_each(load_library)

        it("lists the top level collections at the root", function()
            assert.are.same(
                { "Papers/", "Zettelkasten/" },
                texts_of(ZoteroAPI.displayCollection(nil))
            )
        end)

        it("lists subcollections before items, each group sorted by name", function()
            assert.are.same(
                { "Subfolder/", "A Standalone Report", "Vaswani et al. - Attention Is All You Need" },
                texts_of(ZoteroAPI.displayCollection("COLLAAA1"))
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
            local texts = texts_of(ZoteroAPI.displayCollection("COLLAAA1"))

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
                texts_of(ZoteroAPI.displayCollection("COLLCCC3"))
            )
        end)

        it("returns nothing for an empty collection", function()
            assert.are.same({}, ZoteroAPI.displayCollection("COLLBBB2"))
        end)
    end)

    describe("displaySearchResults", function()
        before_each(load_library)

        it("matches the title", function()
            assert.are.same(
                { "Petzold - The Annotated Turing" },
                texts_of(ZoteroAPI.displaySearchResults("annotated"))
            )
        end)

        it("matches the first author", function()
            local texts = texts_of(ZoteroAPI.displaySearchResults("vaswani"))

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
                texts_of(ZoteroAPI.displaySearchResults("standalone"))
            )
        end)

        it("returns every readable attachment for an empty query", function()
            assert.is_equal(4, #ZoteroAPI.displaySearchResults(""))
        end)

        it("returns nothing when there is no match", function()
            assert.are.same({}, ZoteroAPI.displaySearchResults("nonexistent"))
        end)
    end)

    describe("getDirAndPath", function()
        before_each(load_library)

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

    describe("downloadAndGetPath", function()
        before_each(function()
            set_credentials()
            load_library()
        end)

        it("refuses to run without credentials", function()
            ZoteroAPI.setAPIKey("")

            local path, e = ZoteroAPI.downloadAndGetPath("ATTACH01")

            assert.is_nil(path)
            assert.is_equal("Error: must set API Key", e)
        end)

        it("rejects a key that is not in the library", function()
            local path, e = ZoteroAPI.downloadAndGetPath("NOSUCHKY")

            assert.is_nil(path)
            assert.is_equal("Error: the requested file can not be found in the database", e)
        end)

        it("rejects an item that is not an attachment", function()
            local path, e = ZoteroAPI.downloadAndGetPath("PARENT01")

            assert.is_nil(path)
            assert.is_equal("Error: this item is not an attachment", e)
        end)

        it("rejects a linked attachment", function()
            local path, e = ZoteroAPI.downloadAndGetPath("LINKED01")

            assert.is_nil(path)
            assert.is_equal(
                "Error: this item is a linked attachment. Linked attachments are currently unsupported.",
                e
            )
        end)

        it("rejects an attachment with an unsupported link mode", function()
            local path, e = ZoteroAPI.downloadAndGetPath("EMBEDIMG")

            assert.is_nil(path)
            assert.is_equal("Error: unsupported link mode 'embedded_image'.", e)
        end)

        it("downloads the file and records its version", function()
            fake:on("GET", "/items/ATTACH01/file", { body = "%PDF-1.4 pretend" })

            local path, e = ZoteroAPI.downloadAndGetPath("ATTACH01")

            assert.is_nil(e)
            assert.is_equal("%PDF-1.4 pretend", file_contents(path))
            assert.is_equal("1201", file_contents(ZoteroAPI.storage_dir .. "/PARENT01/version"))
        end)

        it("announces the download before making the request", function()
            fake:on("GET", "/items/ATTACH01/file", { body = "%PDF-1.4 pretend" })

            local calls_when_announced
            ZoteroAPI.downloadAndGetPath("ATTACH01", function()
                calls_when_announced = fake:callCount()
            end)

            assert.is_equal(0, calls_when_announced)
        end)

        it("skips the request when the local copy is current", function()
            fake:on("GET", "/items/ATTACH01/file", { body = "%PDF-1.4 pretend" })
            local path = ZoteroAPI.downloadAndGetPath("ATTACH01")

            local again, e = ZoteroAPI.downloadAndGetPath("ATTACH01")

            assert.is_nil(e)
            assert.is_equal(path, again)
            assert.is_equal(1, fake:callCount())
        end)

        it("downloads again when the server has a newer version", function()
            fake:on("GET", "/items/ATTACH01/file", { body = "%PDF-1.4 pretend" })
            ZoteroAPI.downloadAndGetPath("ATTACH01")

            local items = ZoteroAPI.getItems()
            items["ATTACH01"].version = 1300

            assert.is_nil(select(2, ZoteroAPI.downloadAndGetPath("ATTACH01")))
            assert.is_equal(2, fake:callCount())
            assert.is_equal("1300", file_contents(ZoteroAPI.storage_dir .. "/PARENT01/version"))
        end)

        it("propagates a failed download", function()
            fake:on("GET", "/items/ATTACH01/file", { code = 404, body = "" })

            local path, e = ZoteroAPI.downloadAndGetPath("ATTACH01")

            assert.is_nil(path)
            assert.is_equal("Error: API responded with status code 404", e)
        end)
    end)

    describe("downloadAndGetPath over WebDAV", function()
        local ZIP_URL = "/zotero/ATTACH01%.zip"
        local attachment_dir, attachment_path

        before_each(function()
            set_credentials()
            load_library()
            ZoteroAPI.toggleWebDAVEnabled()
            ZoteroAPI.setWebDAVUrl("https://cloud.example.org/zotero")
            ZoteroAPI.setWebDAVUser("lucas")
            ZoteroAPI.setWebDAVPassword("hunter2")
            attachment_dir, attachment_path = ZoteroAPI.getDirAndPath("ATTACH01")
        end)

        it("fetches the archive named after the attachment key", function()
            fake:on("GET", ZIP_URL, { body = Fixtures.raw("attachment.zip") })

            ZoteroAPI.downloadAndGetPath("ATTACH01")

            assert.is_equal("https://cloud.example.org/zotero/ATTACH01.zip", fake:urls()[1])
        end)

        it("unpacks the attachment out of the archive", function()
            fake:on("GET", ZIP_URL, { body = Fixtures.raw("attachment.zip") })

            local path, e = ZoteroAPI.downloadAndGetPath("ATTACH01")

            assert.is_nil(e)
            assert.is_equal(attachment_path, path)
            assert.is_equal("%PDF-1.4 pretend", file_contents(path))
            assert.is_equal("1201", file_contents(attachment_dir .. "/version"))
        end)

        it("deletes the archive once it is unpacked", function()
            fake:on("GET", ZIP_URL, { body = Fixtures.raw("attachment.zip") })

            ZoteroAPI.downloadAndGetPath("ATTACH01")

            assert.is_nil(lfs.attributes(attachment_dir .. "/ATTACH01.zip"))
        end)

        it("reports an archive it cannot unpack", function()
            fake:on("GET", ZIP_URL, { body = "this is not a zip file" })

            local path, e = ZoteroAPI.downloadAndGetPath("ATTACH01")

            assert.is_nil(path)
            assert.is_equal("Unzipping failed", e)
        end)

        it("deletes the archive even when unpacking fails", function()
            fake:on("GET", ZIP_URL, { body = "this is not a zip file" })

            ZoteroAPI.downloadAndGetPath("ATTACH01")

            assert.is_nil(lfs.attributes(attachment_dir .. "/ATTACH01.zip"))
        end)

        it("does not record a version when unpacking fails", function()
            fake:on("GET", ZIP_URL, { body = "this is not a zip file" })

            ZoteroAPI.downloadAndGetPath("ATTACH01")

            assert.is_nil(file_contents(attachment_dir .. "/version"))
        end)

        it("propagates a failed download", function()
            fake:on("GET", ZIP_URL, { code = 404, body = "" })

            local path, e = ZoteroAPI.downloadAndGetPath("ATTACH01")

            assert.is_nil(path)
            assert.is_equal("Download failed with status code 404", e)
        end)

        it("reports a missing WebDAV url", function()
            ZoteroAPI.getSettings():delSetting("webdav_url")

            local path, e = ZoteroAPI.downloadAndGetPath("ATTACH01")

            assert.is_nil(path)
            assert.is_equal("WebDAV url not set", e)
            assert.is_equal(0, fake:callCount())
        end)

        it("sends basic auth built from the stored credentials", function()
            fake:on("GET", ZIP_URL, { body = Fixtures.raw("attachment.zip") })

            ZoteroAPI.downloadAndGetPath("ATTACH01")

            local sha2 = require("ffi/sha2")
            assert.is_equal(
                "Basic " .. sha2.bin_to_base64("lucas:hunter2"),
                fake.calls[1].headers["Authorization"]
            )
        end)
    end)

    describe("checkWebDAV", function()
        it("reports a missing URL", function()
            assert.is_equal("No WebDAV URL provided", ZoteroAPI.checkWebDAV())
        end)

        it("accepts a multi-status response", function()
            ZoteroAPI.setWebDAVUrl("https://cloud.example.org/zotero")
            fake:on("PROPFIND", "/zotero", { code = 207, headers = {} })

            assert.is_nil(ZoteroAPI.checkWebDAV())
        end)

        it("reports bad credentials", function()
            ZoteroAPI.setWebDAVUrl("https://cloud.example.org/zotero")
            fake:on("PROPFIND", "/zotero", { code = 401, headers = {} })

            assert.is_equal(
                "Reached server, but access forbidden. Check username and password.",
                ZoteroAPI.checkWebDAV()
            )
        end)

        it("sends basic auth built from the stored credentials", function()
            ZoteroAPI.setWebDAVUrl("https://cloud.example.org/zotero")
            ZoteroAPI.setWebDAVUser("lucas")
            ZoteroAPI.setWebDAVPassword("hunter2")
            fake:on("PROPFIND", "/zotero", { code = 207, headers = {} })

            ZoteroAPI.checkWebDAV()

            local sha2 = require("ffi/sha2")
            assert.is_equal(
                "Basic " .. sha2.bin_to_base64("lucas:hunter2"),
                fake.calls[1].headers["Authorization"]
            )
        end)
    end)
end)
