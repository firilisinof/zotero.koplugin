--[[--
Specs for the KOReader widget in main.lua.

Only the initialisation guards are covered here. The browser and the dialogs
need a running UI, so they are left to manual testing in the emulator.
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

    describe("init", function()
        it("reports success once the browser exists", function()
            local instance = new_instance({
                initAPIAndBrowser = function(self) self.browser = {} end,
            })

            instance:init()

            assert.is_true(instance.initialized)
        end)

        it("stays uninitialized when setup fails", function()
            local instance = new_instance({
                initAPIAndBrowser = function() error("no network") end,
            })

            instance:init()

            assert.is_false(instance.initialized)
        end)

        it("does not raise while reporting a setup failure", function()
            local instance = new_instance({
                initAPIAndBrowser = function() error("no network") end,
            })

            assert.has_no_error(function() instance:init() end)
        end)
    end)

    describe("checkInitialized", function()
        it("passes when the browser is ready", function()
            local instance = new_instance({ initialized = true, browser = {} })

            assert.is_true(instance:checkInitialized())
            assert.stub(UIManager.show).was_not_called()
        end)

        it("fails when init never ran", function()
            local instance = new_instance({ initialized = false })

            assert.is_false(instance:checkInitialized())
            assert.stub(UIManager.show).was_called()
        end)

        it("fails when the browser is missing despite the initialized flag", function()
            local instance = new_instance({ initialized = true, browser = nil })

            assert.is_false(instance:checkInitialized())
        end)
    end)

    describe("actions guarded by checkInitialized", function()
        it("does not crash opening the browser after a failed init", function()
            local instance = new_instance({ initialized = true, browser = nil })

            assert.has_no_error(function() instance:onZoteroOpenAction() end)
        end)

        it("does not crash syncing after a failed init", function()
            local instance = new_instance({ initialized = true, browser = nil })

            assert.has_no_error(function() instance:onZoteroSyncAction() end)
        end)
    end)
end)
