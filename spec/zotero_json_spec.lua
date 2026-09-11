-- Offline specs for rapidjson compatibility with files LuaJSON wrote before the switch.
require("commonrequire")
package.path = "plugins/zotero.koplugin/?.lua;" .. package.path
local Env = require("spec.support.zotero_env")
local Store = require("zoteroprogressstore")
local Helpers = require("zoterohighlightutil")
local Util = require("zoteroutil")
local LuaJSON = require("json")
local rapidjson = require("rapidjson")
local util = require("util")

describe("Zotero JSON files", function()
    local env, api
    before_each(function()
        env = Env.new()
        api = env.api
    end)

    -- What the previous release did: decode with LuaJSON, then write with LuaJSON.
    local function writeLegacy(name, value)
        assert.is_nil(Util.write(api.zotero_dir .. "/" .. name, LuaJSON.encode(value)))
    end

    local function pdfPart(page)
        return { pos0 = { page = page, x = 10, y = 20, zoom = 1, rotation = 0 },
            pos1 = { page = page, x = 30, y = 40, zoom = 1, rotation = 0 }, pboxes = { { x = 9, y = 19, w = 22, h = 22 } } }
    end

    local function twoPageHighlight()
        return { pos0 = pdfPart(4).pos0, pos1 = pdfPart(5).pos1, pboxes = pdfPart(4).pboxes,
            ext = { [4] = pdfPart(4), [5] = pdfPart(5) }, drawer = "lighten", color = "yellow", text = "Across pages",
            datetime = "2026-09-11 10:00:00", page = 4 }
    end

    it("re-encodes LuaJSON output unchanged, including false, null and empty containers", function()
        local legacy = LuaJSON.encode(LuaJSON.decode('{"parentCollection":false,"parsed":null,"tags":[],"relations":{}}'))

        local decoded = Util.decode(legacy)

        assert.is_true(decoded.parentCollection == false)
        assert.equal(rapidjson.null, decoded.parsed)
        assert.equal("[]", Util.encode(decoded.tags))
        assert.equal("{}", Util.encode(decoded.relations))
        assert.equal("[]", Util.encode(util.tableDeepCopy(decoded).tags))
        assert.same(LuaJSON.decode(legacy), LuaJSON.decode(Util.encode(decoded)))
    end)

    it("browses an item and collection cache LuaJSON wrote", function()
        env:library()
        local collections = api.displayCollection(nil)
        local rows = api.displayCollection("COLLAAA1")
        for _, name in ipairs({ "items.json", "collections.json" }) do
            writeLegacy(name, LuaJSON.decode(Util.read(api.zotero_dir .. "/" .. name)))
        end

        local reloaded = package.reload("zoteroapi")
        reloaded.init(api.zotero_dir)

        assert.same(collections, reloaded.displayCollection(nil))
        assert.same(rows, reloaded.displayCollection("COLLAAA1"))
    end)

    it("reads a reading-progress outbox LuaJSON wrote", function()
        local identity = { owner = "4242", library = "users/4242", key = "ATTACH01", path = "/books/a.pdf",
            md5 = "5d41402abc4b2a76b9719d911017c592", format = "application/pdf", key_hash = "hash" }
        local record = { identity = identity, generation = 3, native = 17, value = 16, pending = true, status = "pending" }
        writeLegacy("reading-progress.json", { schema = 1, records = { [Store.key(identity)] = record } })

        assert.same(record, Store.new(api):get(identity))
    end)

    it("matches a highlight journal LuaJSON wrote against the same reader highlight", function()
        local item, legacy_fields = twoPageHighlight(), twoPageHighlight()
        -- The old Helpers.native copied each field through LuaJSON, turning page keys into strings.
        legacy_fields.datetime, legacy_fields.page = nil, nil
        local legacy_native = LuaJSON.decode(LuaJSON.encode(legacy_fields))
        writeLegacy("highlights.json", { schema = 1, records = { ["4242/users/4242/ATTACH01"] = {
            identity = { owner = "4242", library = "users/4242", key = "ATTACH01" },
            entries = { fixture = { key = "ABCD2345", native = legacy_native, base = false } } } } })

        local entry = Store.new(api, "highlights.json"):load().records["4242/users/4242/ATTACH01"].entries.fixture

        assert.same(pdfPart(5), entry.native.ext["5"])
        assert.is_true(Helpers.equal(entry.native, Helpers.native(item)))
    end)

    it("keeps multi-page PDF parts when a highlight snapshot is persisted", function()
        local snapshot = Helpers.native(twoPageHighlight())

        local persisted = Util.decode(Util.encode(snapshot))

        assert.same({ ["4"] = pdfPart(4), ["5"] = pdfPart(5) }, persisted.ext)
        assert.is_true(Helpers.equal(snapshot, persisted))
    end)

    it("raises on malformed JSON without echoing its contents", function()
        local ok, err = pcall(Util.decode, '{"key":"s3cret"')

        assert.is_false(ok)
        assert.truthy(tostring(err):find("expected a JSON document in 15 bytes", 1, true))
        assert.falsy(tostring(err):find("s3cret", 1, true))
    end)
end)
