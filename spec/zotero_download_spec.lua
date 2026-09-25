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

    describe("downloadAndGetPath", function()
        before_each(function()
            env:credentials(USER_ID, API_KEY)
            env:library()
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
            assert.is_equal("Error: the requested file can not be found in the database: NOSUCHKY", e)
        end)

        it("rejects an item that is not an attachment", function()
            local path, e = ZoteroAPI.downloadAndGetPath("PARENT01")

            assert.is_nil(path)
            assert.is_equal("Error: this item is not an attachment: PARENT01", e)
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
            assert.is_equal("%PDF-1.4 pretend", Util.read(path))
            assert.is_equal("1201", Util.read(ZoteroAPI.storage_dir .. "/PARENT01/.zotero-ATTACH01.version"))
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
            assert.is_equal("1300", Util.read(ZoteroAPI.storage_dir .. "/PARENT01/.zotero-ATTACH01.version"))
        end)

        it("propagates a failed download", function()
            fake:on("GET", "/items/ATTACH01/file", { code = 404, body = "" })

            local path, e = ZoteroAPI.downloadAndGetPath("ATTACH01")

            assert.is_nil(path)
            assert.is_equal("Error: API responded with status code 404", e)
        end)

        it("keeps the existing local copy when a re-download fails", function()
            fake:on("GET", "/items/ATTACH01/file", { body = "%PDF-1.4 pretend" })
            local path = ZoteroAPI.downloadAndGetPath("ATTACH01")

            -- The server now has a newer version but is answering with an
            -- error page rather than the file.
            ZoteroAPI.getItems()["ATTACH01"].version = 1300
            fake.routes = {}
            fake:on("GET", "/items/ATTACH01/file", {
                code = 500,
                body = "<html>500 Internal Server Error</html>",
            })

            local retry, e = ZoteroAPI.downloadAndGetPath("ATTACH01")

            assert.is_nil(retry)
            assert.is_equal("Error: API responded with status code 500", e)
            assert.is_equal("%PDF-1.4 pretend", Util.read(path))
        end)

        it("leaves no partial file behind after a failed download", function()
            fake:on("GET", "/items/ATTACH01/file", { code = 500, body = "boom" })

            local _, dir_path = ZoteroAPI.getDirAndPath("ATTACH01")
            ZoteroAPI.downloadAndGetPath("ATTACH01")

            assert.is_nil(lfs.attributes(dir_path .. ".part"))
        end)

        it("does not record a version when the download fails", function()
            fake:on("GET", "/items/ATTACH01/file", { code = 500, body = "boom" })

            ZoteroAPI.downloadAndGetPath("ATTACH01")

            assert.is_nil(Util.read(ZoteroAPI.storage_dir .. "/PARENT01/.zotero-ATTACH01.version"))
        end)
    end)

    describe("downloadAndGetPath over WebDAV", function()
        local ZIP_URL = "/zotero/ATTACH01%.zip"
        local attachment_dir, attachment_path

        before_each(function()
            env:credentials(USER_ID, API_KEY)
            env:library()
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
            assert.is_equal("%PDF-1.4 pretend", Util.read(path))
            assert.is_equal("1201", Util.read(attachment_dir .. "/.zotero-ATTACH01.version"))
        end)

        it("deletes the archive once it is unpacked", function()
            fake:on("GET", ZIP_URL, { body = Fixtures.raw("attachment.zip") })

            ZoteroAPI.downloadAndGetPath("ATTACH01")

            assert.is_nil(lfs.attributes(attachment_dir .. "/ATTACH01.zip"))
        end)

        it("replaces a copy an earlier download left behind", function()
            -- unzip stops to ask before replacing an existing file, and on a
            -- reader nothing ever answers, so the app hangs.
            fake:on("GET", ZIP_URL, { body = Fixtures.raw("attachment.zip") })
            lfs.mkdir(attachment_dir)
            local stale = io.open(attachment_path, "wb")
            stale:write("STALE CONTENT")
            stale:close()

            local path, e = ZoteroAPI.downloadAndGetPath("ATTACH01")

            assert.is_nil(e)
            assert.is_equal("%PDF-1.4 pretend", Util.read(path))
        end)

        it("re-downloads over the old file when the server has a newer version", function()
            fake:on("GET", ZIP_URL, { body = Fixtures.raw("attachment.zip") })
            ZoteroAPI.downloadAndGetPath("ATTACH01")
            ZoteroAPI.getItems()["ATTACH01"].version = 1300

            local path, e = ZoteroAPI.downloadAndGetPath("ATTACH01")

            assert.is_nil(e)
            assert.is_equal("%PDF-1.4 pretend", Util.read(path))
            assert.is_equal("1300", Util.read(attachment_dir .. "/.zotero-ATTACH01.version"))
        end)

        it("extracts under the recorded filename even when the entry is named differently", function()
            -- The archive holds "some-other-name.pdf", which used to leave the
            -- attachment unreachable under the name Zotero recorded.
            fake:on("GET", ZIP_URL, { body = Fixtures.raw("attachment_misnamed.zip") })

            local path, e = ZoteroAPI.downloadAndGetPath("ATTACH01")

            assert.is_nil(e)
            assert.is_equal(attachment_path, path)
            assert.is_equal("%PDF-1.4 pretend", Util.read(path))
        end)

        it("reports an archive it cannot unpack", function()
            fake:on("GET", ZIP_URL, { body = "this is not a zip file" })

            local path, e = ZoteroAPI.downloadAndGetPath("ATTACH01")

            assert.is_nil(path)
            assert.is_truthy(e:find("Could not open the downloaded archive", 1, true))
        end)

        it("deletes the archive even when unpacking fails", function()
            fake:on("GET", ZIP_URL, { body = "this is not a zip file" })

            ZoteroAPI.downloadAndGetPath("ATTACH01")

            assert.is_nil(lfs.attributes(attachment_dir .. "/ATTACH01.zip"))
        end)

        it("does not record a version when unpacking fails", function()
            fake:on("GET", ZIP_URL, { body = "this is not a zip file" })

            ZoteroAPI.downloadAndGetPath("ATTACH01")

            assert.is_nil(Util.read(attachment_dir .. "/.zotero-ATTACH01.version"))
        end)

        it("propagates a failed download", function()
            fake:on("GET", ZIP_URL, { code = 404, body = "" })

            local path, e = ZoteroAPI.downloadAndGetPath("ATTACH01")

            assert.is_nil(path)
            assert.is_equal("Download failed with status code 404", e)
        end)

        it("leaves no archive behind after a failed download", function()
            fake:on("GET", ZIP_URL, { code = 404, body = "" })

            ZoteroAPI.downloadAndGetPath("ATTACH01")

            assert.is_nil(lfs.attributes(attachment_dir .. "/ATTACH01.zip"))
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

        it("reports a URL that points at nothing", function()
            ZoteroAPI.setWebDAVUrl("https://cloud.example.org/zotero")
            fake:on("PROPFIND", "/zotero", { code = 404, headers = {} })

            assert.is_equal(
                "Reached server, but the folder was not found. Check the WebDAV URL.",
                ZoteroAPI.checkWebDAV()
            )
        end)

        it("reports any other status rather than claiming success", function()
            ZoteroAPI.setWebDAVUrl("https://cloud.example.org/zotero")
            fake:on("PROPFIND", "/zotero", { code = 500, headers = {} })

            assert.is_equal(
                "Unexpected response from server: status code 500",
                ZoteroAPI.checkWebDAV()
            )
        end)

        it("reports a server it cannot reach", function()
            ZoteroAPI.setWebDAVUrl("https://cloud.example.org/zotero")
            fake:on("PROPFIND", "/zotero", { error = "host not found" })

            assert.is_equal("Could not reach the server: host not found", ZoteroAPI.checkWebDAV())
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
