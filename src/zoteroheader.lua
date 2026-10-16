local VerticalGroup = require("ui/widget/verticalgroup")
local TitleBar = require("ui/widget/titlebar")
local ButtonTable = require("ui/widget/buttontable")
local _ = require("gettext")

local Header = VerticalGroup:extend{}

--- Keep navigation visible above every native menu page. Example: Header:new{ browser = browser, width = 600 }.
function Header:init()
    local browser = self.browser
    self.caption = TitleBar:new{ width = self.width, title = _("Zotero"), fullscreen = true,
        close_callback = function() browser:onCloseAllMenus() end, show_parent = browser }
    self.controls = ButtonTable:new{ width = self.width, show_parent = browser, buttons = { {
        { id = "home", text = _("Home"), callback = function() browser:onHome() end },
        { id = "back", text = _("Back"), callback = function() browser:onReturn() end },
        { id = "search", text = _("Search"), callback = function() browser:onLeftButtonTap() end },
    } } }
    self[1], self[2] = self.caption, self.controls
end

--- Include the controls in menu pagination measurements. Example: header:getHeight().
---@return number
function Header:getHeight()
    return self:getSize().h
end

--- Update location without rebuilding the controls. Example: header:setTitle("Papers", true).
---@param title string
---@param no_refresh boolean|nil
function Header:setTitle(title, no_refresh)
    self.caption:setTitle(title, no_refresh)
end

--- Expose each control to native keyboard focus. Example: header:generateVerticalLayout().
---@return table[]
function Header:generateVerticalLayout()
    local layout = self.caption:generateVerticalLayout()
    for _, button in ipairs(self.controls.buttons_layout[1]) do table.insert(layout, { button }) end
    return layout
end

return Header
