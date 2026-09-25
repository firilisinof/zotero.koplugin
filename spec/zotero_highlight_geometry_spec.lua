require("commonrequire")
package.path = "plugins/zotero.koplugin/?.lua;" .. package.path
local Codec = require("zoterohighlightcodec")
local PDF = require("zoteropdf")
local Util = require("zoteroutil")
local Range = require("zoterocfirange")
local Fixtures = require("spec.support.fixtures")
local Identity = require("zoteroprogressidentity")

describe("Zotero highlight geometry", function()
    it("matches independent transforms for crop offsets, all rotations, inheritance and UserUnit", function()
        local path = Fixtures.dir .. "positions/geometry.pdf"
        local checksum = Identity.checksum(path, true)
        local codec = Codec.open({ path = path, format = "application/pdf" })
        local expected = {
            { 1, 0, 0, -1, -30, 560 }, { 0, 1, 1, 0, -60, -30 },
            { -1, 0, 0, 1, 330, -60 }, { 0, -1, -1, 0, 560, 330 },
            { 0, -2, -2, 0, 1120, 660 },
        }
        for page, matrix in ipairs(expected) do
            assert.same(matrix, codec.pdf:matrix(page))
            local rects = { { 50, 500, 180, 514 }, { 50, 470, 155, 484 } }
            local native = codec.pdf:decodeBoxes(page, rects)
            assert.same(rects, codec.pdf:encodeBoxes(page, native.pboxes))
        end
        codec:close(); assert.equals(checksum, Identity.checksum(path, true))
    end)
    it("round-trips consecutive-page PDF highlights after JSON persistence", function()
        local codec = Codec.open({ path = Fixtures.dir .. "positions/geometry.pdf", format = "application/pdf" })
        -- Pages 1 and 2 form a Lua sequence, pages 3 and 4 do not. Encoders treat them differently.
        for _, page_index in ipairs({ 0, 2 }) do
            local value = { text = "Two pages", comment = "", color = "#ffd400", kind = "highlight",
                position = { pageIndex = page_index, rects = { { 50, 500, 180, 514 } }, nextPageRects = { { 50, 470, 155, 484 } } } }
            -- Persist through the journal's real encoder: an in-memory copy would hide lost page keys.
            local native = Util.decode(Util.encode(codec:decode(value)))
            assert.same(value, codec:encode(native))
        end
        codec:close()
    end)
    it("rejects degenerate, nonfinite and malformed rectangles", function()
        for _, rect in ipairs({ {}, {1,2,0,3}, {1,2,1,4}, {0,0,math.huge,5} }) do
            assert.has_error(function() PDF.rect(rect, {1,0,0,1,0,0}) end)
        end
    end)
    it("handles shared-text and cross-node CFI ranges with exact Unicode boundaries", function()
        local codec = Codec.open({ path = Fixtures.dir .. "positions/sample.epub", format = "application/epub+zip" }, 20260812)
        local native = { pos0 = "/body/DocFragment[1]/body/p[1]/text().6", pos1 = "/body/DocFragment[1]/body/p[2]/em/text().10",
            text = "selection", drawer = "lighten", color = "yellow" }
        local value = codec:encode(native)
        local decoded = codec:decode(value)
        assert.equals(codec.document:getTextFromXPointers(native.pos0, native.pos1), codec.document:getTextFromXPointers(decoded.pos0, decoded.pos1))
        assert.same(value, codec:encode(decoded))
        assert.truthy(codec:fields(value).annotationSortIndex:match('^00000|%d%d%d%d%d%d%d%d$'))
        codec:close()
    end)
    it("parses CFI common-text offsets and escaped assertions without splitting them", function()
        local first, last = Range.split('epubcfi(/6/2[id^,value]!/4/2/1,:1,:4)')
        assert.equals('epubcfi(/6/2[id^,value]!/4/2/1:1)', first)
        assert.equals('epubcfi(/6/2[id^,value]!/4/2/1:4)', last)
    end)
    it("preserves exact imported PDF boxes and releases the instance hook", function()
        local View = require("zoterohighlightpdfview")
        local Reader = require("spec.support.fake_highlight_reader")
        local reader = Reader.new(Fixtures.dir .. "positions/sample.pdf", "pdf")
        local item = reader:highlight("pdf")
        item.zotero_highlight_id = "fixture"
        View.remember(item)
        local original = reader.document.getPageBoxesFromPositions
        View.bind(reader)
        local boxes = reader.document:getPageBoxesFromPositions(1, item.pos0, item.pos1)
        assert.equals(item.pboxes[1].w, boxes[1].w)
        assert.equals(item.pboxes[1].h, boxes[1].h)
        View.unbind(reader)
        assert.equals(original, reader.document.getPageBoxesFromPositions)
        reader:close()
    end)

end)
