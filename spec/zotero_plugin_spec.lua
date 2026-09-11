--[[--
Specs for the KOReader widget in main.lua.

Only the initialisation and lazy browser guards are covered here. Real browser
widgets are covered by the navigation and position specs.
]]

require("commonrequire")

package.path = "plugins/zotero.koplugin/?.lua;" .. package.path

local UIManager = require("ui/uimanager")

describe("Zotero plugin widget", function()
    local Plugin

    setup(function()
        -- dofile rather than require, so each run re-evaluates the file instead
        -- of sharing a cached module with the other spec.
        Plugin = dofile("plugins/zotero.koplugin/main.lua")
    end)

    -- A stand-in for a mounted plugin, with the KOReader wiring stubbed out.
    local function new_instance(fields)
        local instance = {
            ui = { menu = { registerToMainMenu = function() end } },
            onDispatcherRegisterActions = function() end,
        }
        for key, value in pairs(fields or {}) do
            instance[key] = value
        end
        return setmetatable(instance, { __index = Plugin })
    end

    before_each(function()
        stub(UIManager, "show")
    end)

    after_each(function()
        UIManager.show:revert()
    end)

    -- Counts browser builds without constructing real widgets.
    local function counting_build(instance)
        instance.builds = 0
        instance.buildBrowser = function(self)
            self.builds = self.builds + 1
            self.browser, self.zotero_dialog = {}, {}
        end
        return instance
    end

    describe("init", function()
        it("reports success once the API is ready, without building the browser", function()
            local instance = counting_build(new_instance({ initAPI = function() end }))

            instance:init()

            assert.is_true(instance.initialized)
            assert.equals(0, instance.builds)
            assert.is_nil(instance.browser)
        end)

        it("stays uninitialized when setup fails", function()
            local instance = new_instance({
                initAPI = function() error("no network") end,
            })

            instance:init()

            assert.is_false(instance.initialized)
        end)

        it("does not raise while reporting a setup failure", function()
            local instance = new_instance({
                initAPI = function() error("no network") end,
            })

            assert.has_no_error(function() instance:init() end)
        end)
    end)

    describe("checkInitialized", function()
        it("passes once initialized, before any browser exists", function()
            local instance = new_instance({ initialized = true })

            assert.is_true(instance:checkInitialized())
            assert.stub(UIManager.show).was_not_called()
        end)

        it("fails when init never ran", function()
            local instance = new_instance({ initialized = false })

            assert.is_false(instance:checkInitialized())
            assert.stub(UIManager.show).was_called()
        end)
    end)

    describe("ensureBrowser", function()
        it("builds the browser once, on first use", function()
            local instance = counting_build(new_instance({ initialized = true }))

            assert.is_true(instance:ensureBrowser())
            assert.is_true(instance:ensureBrowser())

            assert.equals(1, instance.builds)
        end)

        it("logs and reports a build failure like an init failure", function()
            local instance = new_instance({ initialized = true,
                buildBrowser = function() error("no screen") end })
            stub(_G, "print")

            local built = instance:ensureBrowser()
            local logged = print.calls[1] and print.calls[1].vals[1]
            print:revert()

            assert.is_false(built)
            assert.is_nil(instance.browser)
            assert.stub(UIManager.show).was_called()
            assert.truthy(logged:find("zotero_browser_failed", 1, true))
            assert.truthy(logged:find("no screen", 1, true))
        end)
    end)

    describe("actions guarded by checkInitialized", function()
        it("does not crash opening the browser after a failed init", function()
            local instance = new_instance({ initialized = false })

            assert.has_no_error(function() instance:onZoteroOpenAction() end)
        end)

        it("does not crash opening the browser after a failed build", function()
            local instance = new_instance({ initialized = true,
                buildBrowser = function() error("no screen") end })
            stub(_G, "print")

            assert.has_no_error(function() instance:onZoteroOpenAction() end)
            print:revert()
        end)

        it("does not crash syncing after a failed init", function()
            local instance = new_instance({ initialized = false })

            assert.has_no_error(function() instance:onZoteroSyncAction() end)
        end)
    end)
end)
