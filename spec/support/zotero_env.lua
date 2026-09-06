local DataStorage = require("datastorage")
local FakeHttp = require("spec.support.fake_http")
local Fixtures = require("spec.support.fixtures")
local Env = {}
Env.__index = Env
local serial = 0
local Util = require("zoteroutil")

-- A directory per test keeps real file I/O independent. The test runner removes
-- KO_HOME before each session, so no cleanup can touch a real library.
function Env.newDirectory()
    serial = serial + 1
    local root = DataStorage:getDataDir() .. "/zotero_features/" .. serial
    assert(Util.mkdir(root))
    return root
end

function Env.new()
    -- API is a singleton module. Reload it so module state cannot leak between tests.
    local api = package.reload("zoteroapi")
    local root = Env.newDirectory()
    api.init(root)
    api.http = FakeHttp.new()
    return setmetatable({ api = api, http = api.http, root = root }, Env)
end

function Env:credentials(identifier, key)
    self.api.setUserID(identifier or "4242")
    self.api.setAPIKey(key or "offline-test-key")
end

function Env:library()
    local items, collections = {}, {}
    for _, name in ipairs({ "items_page1.json", "items_page2.json" }) do
        for _, item in ipairs(Fixtures.decode(name)) do items[item.key] = item end
    end
    items.DELETED1 = nil
    for _, collection in ipairs(Fixtures.decode("collections.json")) do collections[collection.key] = collection end
    self.api.setItems(items)
    self.api.setCollections(collections)
end

function Env:syncRoutes()
    self.http:on("GET", "/items%?", {
        headers = { ["total-results"] = "1", ["last-modified-version"] = "1230" },
        body = Fixtures.raw("items_page1.json"),
    })
    self.http:on("GET", "/collections%?", {
        headers = { ["total-results"] = "3", ["last-modified-version"] = "1240" },
        body = Fixtures.raw("collections.json"),
    })
end

function Env:file(key, contents, version)
    local directory, path = self.api.getDirAndPath(key)
    assert(self.api.util.mkdir(directory))
    local err = self.api.util.write(path, contents or "cached")
    assert(not err, err)
    if version then
        err = self.api.util.write(self.api.getVersionPath(key), tostring(version))
        assert(not err, err)
    end
    return path
end

function Env:attachment(key, parent, filename, version)
    local items = self.api.getItems()
    items[key] = { key = key, version = version or 1, data = {
        itemType = "attachment", parentItem = parent, filename = filename, title = key,
        contentType = "application/pdf", linkMode = "imported_file", tags = {}, collections = { "COLLAAA1" },
    } }
    self.api.setItems(items)
    return items[key]
end

function Env:fullSyncRoutes()
    self.http:on("GET", "/items%?.*start=0$", {
        headers = { ["total-results"] = "150", ["last-modified-version"] = "1214" },
        body = Fixtures.raw("items_page1.json"),
    })
    self.http:on("GET", "/items%?.*start=100$", {
        headers = { ["total-results"] = "150", ["last-modified-version"] = "1214" },
        body = Fixtures.raw("items_page2.json"),
    })
    self.http:on("GET", "/collections%?.*start=0$", {
        headers = { ["total-results"] = "3", ["last-modified-version"] = "1240" },
        body = Fixtures.raw("collections.json"),
    })
end

function Env.keyed(entries)
    local items = {}
    for _, item in ipairs(entries) do items[item.key] = item end
    return items
end

function Env.texts(entries)
    local texts = {}
    for index, item in ipairs(entries) do texts[index] = item.text end
    return texts
end

return Env
