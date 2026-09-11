-- Offline specs for library sync in a non-modal child, committed only by the parent.
require("commonrequire")
package.path = "plugins/zotero.koplugin/?.lua;" .. package.path
local Env = require("spec.support.zotero_env")
local FakeHttp = require("spec.support.fake_http")
local FakeUI = require("spec.support.fake_ui")
local Browser = require("zoterobrowser")
local SyncJob = require("zoterosyncjob")
local Plugin = dofile("plugins/zotero.koplugin/main.lua")
local lfs = require("libs/libkoreader-lfs")

describe("Zotero background library sync", function()
    local env, api, runtime, browser, plugin, refreshes

    local function newPlugin(plugin_browser)
        return setmetatable({ api = api, runtime = runtime, browser = plugin_browser,
            initialized = true, zotero_dialog = {} }, { __index = Plugin })
    end

    -- Records whether the sync still held the operation lock at each refresh.
    local function recordRefreshes(target)
        local seen = {}
        target.refresh = function(self)
            table.insert(seen, api.operation or false)
            return Browser.refresh(self)
        end
        return seen
    end

    before_each(function()
        env = Env.new()
        api = env.api
        env:credentials()
        env:library()
        api.setLibraryVersion("1100")
        api.setLastSync(500)
        api.saveModifiedItems()
        runtime = FakeUI.new()
        browser = runtime:newBrowser(Browser, api)
        refreshes = recordRefreshes(browser)
        plugin = newPlugin(browser)
        plugin:attachSyncJob(SyncJob.new(api, runtime))
    end)

    -- Util.write and the commit replace files by rename, so every replacement gets a new inode.
    local function inode(name)
        return lfs.attributes(api.getCachePath(name), "ino")
    end

    local function stagedFiles()
        local found = {}
        for _, path in pairs(api.getSyncStage()) do
            if lfs.attributes(path) then table.insert(found, path) end
            if lfs.attributes(path .. ".tmp") then table.insert(found, path .. ".tmp") end
        end
        return found
    end

    local function snapshot()
        return { items = inode("items"), collections = inode("collections"),
            version = api.getLibraryVersion(), last_sync = api.getLastSync() }
    end

    local function assertUntouched(before)
        assert.same(before, snapshot())
        assert.same({}, stagedFiles())
        assert.is_nil(api.operation)
        assert.same({}, refreshes)
        assert.is_not_nil(api.getItems().PARENT02)
    end

    local function useFreshServer()
        env.http = FakeHttp.new()
        api.http = env.http
    end

    it("stages in the child and commits in the parent only after the result returns", function()
        env:syncRoutes()
        local before, index = snapshot(), api.getIndex()
        plugin:onZoteroSyncAction()
        local progress = runtime:last()
        assert.truthy(progress.text:find("tap to cancel", 1, true))

        local job = runtime.worker:next()
        local result = job.task()
        assert.same(before, snapshot())
        assert.is_true(rawequal(index, api.getIndex()))
        local staged = lfs.attributes(api.getSyncStage().items, "ino")
        assert.is_not_nil(staged)
        assert.equals("sync", api.operation)

        runtime.worker:deliver(job, result)
        assert.equals(staged, inode("items"))
        assert.equals(before.collections, inode("collections"))
        assert.is_nil(api.items)
        assert.is_nil(api.index)
        assert.equals("1230", api.getLibraryVersion())
        assert.is_true(api.getLastSync() > 500)
        assert.equals("Full Text PDF", api.getItems().ATTACH01.data.title)
        assert.same({}, stagedFiles())
        assert.is_nil(api.operation)
        assert.same({ false }, refreshes)
        assert.equals(progress, runtime.closed[1])
        assert.equals("Success.", runtime:last().text)
    end)

    it("writes only staged files and returns a small result from the child", function()
        env:syncRoutes()
        local settings = api.util.read(api.zotero_dir .. "/meta.lua")
        plugin:onZoteroSyncAction()
        local result = runtime.worker:next().task()
        assert.same({ items = { changed = true, version = "1230" },
            collections = { changed = false, version = "1240" } }, result)
        assert.equals(settings, api.util.read(api.zotero_dir .. "/meta.lua"))
        assert.equals(1, #stagedFiles())
    end)

    it("keeps the cache and removes staged files when a later fetch fails", function()
        env.http:on("GET", "/collections%?", { code = 500 })
        env:syncRoutes()
        local before = snapshot()
        plugin:onZoteroSyncAction()
        runtime:work()
        assertUntouched(before)
        assert.truthy(runtime:last().text:find("500", 1, true))
    end)

    it("keeps the cache when the progress message is tapped away", function()
        local before = snapshot()
        plugin:onZoteroSyncAction()
        -- A child killed mid-write leaves a finished stage and an unfinished replacement.
        local stage = api.getSyncStage()
        assert.is_nil(api.util.write(stage.items, "partial"))
        assert.is_nil(api.util.write(stage.collections .. ".tmp", "partial"))
        runtime:tapClose(runtime:last())
        assert.is_true(runtime.jobs[1].done)
        assertUntouched(before)
        assert.truthy(runtime:last().text:find("cancelled", 1, true))
    end)

    it("keeps the cache when the child outlives its own time limit", function()
        env:syncRoutes()
        local before = snapshot()
        plugin:onZoteroSyncAction()
        -- A first sync of a large library needs far longer than a position exchange.
        assert.is_true(runtime.jobs[1].limit >= 600)
        runtime.worker:expire()
        assertUntouched(before)
        assert.truthy(runtime:last().text:find("timed out", 1, true))
    end)

    it("cancels an automatic sync silently on suspend", function()
        env:syncRoutes()
        api.setSyncOnOpen(true)
        local before = snapshot()
        plugin:maybeAutoSync("open")
        plugin:onSuspend()
        assertUntouched(before)
        assert.equals(0, #runtime.shown)
    end)

    for _, change in ipairs({
        { name = "API key", apply = function() api.setAPIKey("another-key") end },
        { name = "library", apply = function() api.getSettings():saveSetting("user_id", "999") end },
    }) do
        it("discards the result when the " .. change.name .. " changes during sync", function()
            env:syncRoutes()
            local before = snapshot()
            plugin:onZoteroSyncAction()
            local job = runtime.worker:next()
            local result = job.task()
            change.apply()
            runtime.worker:deliver(job, result)
            assertUntouched(before)
            assert.truthy(runtime:last().text:find("account changed", 1, true))
        end)
    end

    it("keeps browsing and local reading available during an automatic sync", function()
        api.setSyncOnOpen(true)
        plugin:maybeAutoSync("open")
        assert.equals("sync", api.operation)
        assert.equals(0, #runtime.shown)
        assert.equals(0, runtime.wraps)
        browser:displayCollection("COLLAAA1")
        assert.equals("Subfolder/", browser.rows[1].text)
        local path = env:file("ATTACH01")
        browser:onMenuSelect({ key = "ATTACH01" })
        assert.equals(path, runtime.opened_path)
        env:syncRoutes()
        runtime:work()
        assert.is_nil(api.operation)
        assert.same({ false }, refreshes)
        assert.equals(0, #runtime.shown)
    end)

    it("rebuilds from version 0 without clearing the cache, committing only on success", function()
        env.http:on("GET", "/collections%?", { code = 500 })
        env:syncRoutes()
        local before = snapshot()
        plugin:onZoteroSyncAction(true)
        assert.is_not_nil(api.getItems().PARENT02)
        runtime:work()
        assert.truthy(env.http:urls()[1]:find("since=0", 1, true))
        assertUntouched(before)

        useFreshServer()
        env:syncRoutes()
        plugin:onZoteroSyncAction(true)
        runtime:work()
        assert.truthy(env.http:urls()[1]:find("since=0", 1, true))
        assert.is_not_nil(api.getItems().PARENT01)
        assert.is_nil(api.getItems().PARENT02)
        assert.equals("1230", api.getLibraryVersion())
        assert.same({}, stagedFiles())
    end)

    it("releases the lock and reports when the worker cannot start", function()
        runtime.worker.refuse = true
        local before = snapshot()
        plugin:onZoteroSyncAction()
        assertUntouched(before)
        assert.truthy(runtime:last().text:find("Could not start", 1, true))
        assert.equals(runtime.shown[1], runtime.closed[1])
    end)

    it("removes stage files a killed child left before starting another", function()
        assert.is_nil(api.util.write(api.getSyncStage().items, "stale"))
        api.setSyncOnStartup(true)
        plugin:maybeAutoSync("startup")
        assert.equals(1, #runtime.jobs)
        assert.same({}, stagedFiles())
    end)

    it("reports a failed commit without stamping the sync", function()
        env:syncRoutes()
        -- A directory in place of items.json makes the rename fail.
        assert(os.remove(api.getCachePath("items")))
        assert(lfs.mkdir(api.getCachePath("items")))
        plugin:onZoteroSyncAction()
        runtime:work()
        assert.truthy(runtime:last().text:find("Could not replace", 1, true))
        assert.equals("1100", api.getLibraryVersion())
        assert.equals(500, api.getLastSync())
        assert.same({}, stagedFiles())
        assert.is_nil(api.operation)
        assert.same({}, refreshes)
    end)

    it("refreshes the newest plugin instance when a sync outlives the one that started it", function()
        env:syncRoutes()
        plugin:onZoteroSyncAction()
        local newer_browser = runtime:newBrowser(Browser, api)
        local newer_refreshes = recordRefreshes(newer_browser)
        newPlugin(newer_browser):attachSyncJob(plugin.sync_job)
        runtime:work()
        assert.same({ false }, newer_refreshes)
        assert.same({}, refreshes)
    end)

    it("refuses a second sync while one is running", function()
        plugin:onZoteroSyncAction()
        plugin:onZoteroSyncAction()
        assert.equals(1, #runtime.jobs)
        assert.truthy(runtime:last().text:find("already running", 1, true))
    end)
end)
