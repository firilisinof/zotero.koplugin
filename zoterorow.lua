-- Metadata content inside KOReader's MenuItem. Menu keeps gestures, shortcuts and focus.
local BD = require("ui/bidi")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local OverlapGroup = require("ui/widget/overlapgroup")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local _ = require("gettext")
local Row = {}

--- Localize file presence separately from bibliographic metadata. Example: Row.status(entry).
---@param entry ZoteroRow
---@return string
function Row.status(entry)
    if entry.downloaded then return _("Downloaded") end
    if entry.downloadable == false then return _("Unavailable") end
    return _("Not downloaded")
end

--- Omit missing authors and dates without dangling separators. Example: Row.byline(entry).
---@param entry ZoteroRow
---@return string
function Row.byline(entry)
    if not entry.author and not entry.year then return "" end
    if entry.author and entry.year then return BD.auto(entry.author) .. " · " .. BD.auto(entry.year) end
    return BD.auto(entry.author or entry.year)
end

---@param face table
---@return number
local function statusWidth(face)
    local width = 0
    for _, text in ipairs({ _("Downloaded"), _("Not downloaded"), _("Unavailable"), "EPUB" }) do
        local label = TextWidget:new{ text = text, face = face }
        width = math.max(width, label:getSize().w)
        label:free()
    end
    return width
end

--- Measure actual fonts before choosing page capacity. Example: Row.metrics(22, 18).
---@param title_size number
---@param info_size number
---@return table
function Row.metrics(title_size, info_size)
    local title_face, info_face = Font:getFace("smallinfofont", title_size), Font:getFace("cfont", info_size)
    local title = TextBoxWidget:new{ text = "Ag\nAg", face = title_face, bold = true, width = 10000 }
    local info = TextWidget:new{ text = "Ag", face = info_face }
    local metrics = {
        title_face = title_face, info_face = info_face,
        title_height = title:getSize().h, title_line_height = title:getLineHeight(),
        info_height = info:getSize().h, right_width = statusWidth(info_face),
        gap = Size.padding.small, padding = Size.padding.default,
    }
    metrics.min_height = metrics.title_height + metrics.gap + metrics.info_height + 2 * metrics.padding
    title:free()
    info:free()
    return metrics
end

---@param entry ZoteroRow
---@param width number
---@param metrics table
---@return table
local function titleWidget(entry, width, metrics)
    return TextBoxWidget:new{
        text = BD.auto(entry.file_format and (entry.title or _("Untitled")) or entry.text),
        face = metrics.title_face, bold = true, width = width,
        height = 2 * metrics.title_line_height, height_adjust = true,
        height_overflow_show_ellipsis = true, alignment = "left",
    }
end

---@param text string
---@param width number
---@param metrics table
---@return table
local function infoWidget(text, width, metrics)
    return TextWidget:new{ text = text, face = metrics.info_face, max_width = width }
end

---@param widget table
---@param x number
---@param y number
---@return table
local function at(widget, x, y)
    widget.overlap_offset = { x, y }
    return widget
end

---@param item table
---@param metrics table
---@return table
local function metadataContent(item, metrics)
    local width, height = item.content_width, item.dimen.h - item.linesize
    local right_width = math.min(metrics.right_width, math.floor(width * 0.4))
    local left_width = width - right_width - Size.span.horizontal_default
    local title = titleWidget(item.entry, left_width, metrics)
    local byline = infoWidget(Row.byline(item.entry), left_width, metrics)
    local format = infoWidget(item.entry.file_format, right_width, metrics)
    local status = infoWidget(Row.status(item.entry), right_width, metrics)
    local top = math.floor((height - title:getSize().h - metrics.gap - metrics.info_height) / 2)
    local bottom = top + title:getSize().h + metrics.gap
    item.metadata_widgets = { title = title, byline = byline, format = format, status = status }
    return OverlapGroup:new{
        dimen = Geom:new{ w = width, h = height }, allow_mirroring = false,
        at(title, 0, top), at(byline, 0, bottom),
        at(format, width - format:getSize().w, top), at(status, width - status:getSize().w, bottom),
    }
end

---@param item table
---@param metrics table
---@return table
local function navigationContent(item, metrics)
    local width, height = item.content_width, item.dimen.h - item.linesize
    local title = titleWidget(item.entry, width, metrics)
    local subtitle = infoWidget(BD.auto(item.entry.subtitle), width, metrics)
    local top = math.floor((height - title:getSize().h - metrics.gap - metrics.info_height) / 2)
    item.navigation_widgets = { title = title, subtitle = subtitle }
    return OverlapGroup:new{
        dimen = Geom:new{ w = width, h = height }, allow_mirroring = false,
        at(title, 0, top), at(subtitle, 0, top + title:getSize().h + metrics.gap),
    }
end

--- Replace only content, retaining native MenuItem interaction. Example: Row.decorate(item, metrics).
---@param item table
---@param metrics table
function Row.decorate(item, metrics)
    if not item.entry.file_format and not item.entry.subtitle then return end
    local content = item.entry.subtitle and navigationContent(item, metrics) or metadataContent(item, metrics)
    item._underline_container[1]:free()
    item._underline_container[1] = content
end

return Row
