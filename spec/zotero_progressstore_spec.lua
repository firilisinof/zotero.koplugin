-- Offline specs for the parent-owned progress and highlight outbox cache.
require("commonrequire")
package.path = "plugins/zotero.koplugin/?.lua;" .. package.path
local Env = require("spec.support.zotero_env")
local FakeStoreDisk = require("spec.support.fake_store_disk")
local Store = require("zoteroprogressstore")

describe("Zotero outbox store", function()
    local root, disk, store, identity, other

    local function newStore(files)
        return Store.new({ zotero_dir = root, util = files or disk })
    end

    before_each(function()
        identity = { owner = "4242", library = "users/4242", key = "ATTACH01", md5 = "abc", path = "/tmp/a.pdf" }
        other = { owner = "4242", library = "users/4242", key = "ATTACH02", md5 = "def", path = "/tmp/b.pdf" }
        root = Env.newDirectory()
        disk = FakeStoreDisk.new()
        store = newStore()
    end)

    it("reads the file once and writes each change through", function()
        store:capture(identity, 4, 3)
        store:capture(other, 2, 1)
        store:get(identity); store:load(); store:get(other)
        assert.equals(1, disk.reads)
        assert.equals(2, disk.writes)
        local reopened = newStore(FakeStoreDisk.new())
        assert.same(store:get(identity), reopened:get(identity))
        assert.same(store:get(other), reopened:get(other))
    end)

    it("hands out and keeps independent copies", function()
        local record = store:capture(identity, 4, 3)
        record.value = 99
        record.identity.md5 = "changed"
        local copy = store:get(identity)
        copy.pending = false
        store:load().records[Store.key(identity)].generation = 50
        local saved = store:get(identity)
        assert.equals(3, saved.value)
        assert.equals("abc", saved.identity.md5)
        assert.is_true(saved.pending)
        assert.equals(1, saved.generation)
    end)

    -- A highlight journal keeps record.delivery.before pointing at record.entries. Capturing a
    -- local edit into entries must not rewrite that import baseline, as the JSON round trip
    -- this cache replaced never did.
    it("separates fields that shared one table, like the file did", function()
        local entries = { one = { text = "first" } }
        store:put({ identity = identity, generation = 1,
            entries = entries, delivery = { before = entries, after = {} } })
        local record = store:get(identity)
        record.entries.one.text = "edited locally"
        record.entries.two = { text = "added locally" }
        assert.equals("first", record.delivery.before.one.text)
        assert.is_nil(record.delivery.before.two)
        assert.same({ one = { text = "first" } }, store:load().records[Store.key(identity)].entries)
    end)

    it("rejects the acknowledgment of a snapshot overtaken by a newer capture", function()
        store:capture(identity, 4, 3)
        local snapshot = store:get(identity)
        store:capture(identity, 6, 5)
        assert.is_false(store:ack(snapshot, { version = 7, value = 3 }))
        assert.is_true(store:get(identity).pending)
        assert.is_true(store:ack(store:get(identity), { version = 8, value = 5 }))
        assert.is_false(store:get(identity).pending)
    end)

    it("skips the write when a record is unchanged", function()
        store:capture(identity, 4, 3)
        store:put(store:get(identity))
        store:capture(identity, 4, 3)
        assert.equals(1, disk.writes)
        local record = store:get(identity)
        record.native = 5
        store:put(record)
        assert.equals(2, disk.writes)
    end)

    it("keeps memory matching the disk when a write fails", function()
        store:capture(identity, 4, 3)
        disk.fail_writes = true
        local ok, err = pcall(store.capture, store, identity, 6, 5)
        assert.is_false(ok)
        assert.truthy(err:find(Store.key(identity), 1, true))
        assert.truthy(err:find("no space left", 1, true))
        assert.has_error(function() store:capture(other, 2, 1) end)
        assert.equals(3, store:get(identity).value)
        assert.is_nil(store:get(other))
        local reopened = newStore(FakeStoreDisk.new())
        assert.same(store:get(identity), reopened:get(identity))
    end)

    it("does not cache an invalid file", function()
        assert.is_nil(require("zoteroutil").write(root .. "/reading-progress.json", "invalid"))
        assert.has_error(function() store:get(identity) end)
        assert.has_error(function() store:get(identity) end)
        assert.equals(2, disk.reads)
    end)
end)
