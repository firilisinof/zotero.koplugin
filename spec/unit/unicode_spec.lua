local Unicode = require("src.zoterounicode")

describe("Unicode position boundaries", function()
    it("counts supplementary characters as two UTF-16 units", function()
        assert.same({ [0] = 0, 1, 3, 4 }, Unicode.boundaries("a😀b"))
        assert.equals(3, Unicode.offset("a😀b", 2))
        assert.equals(2, Unicode.offset("a😀b", 3, true))
    end)
    it("supports empty text and the zero boundary", function()
        assert.equals(0, Unicode.offset("", 0))
        assert.equals(0, Unicode.offset("", 0, true))
    end)
    it("rejects split surrogates and invalid offsets", function()
        for _, offset in ipairs({ -1, 0.5, 4 }) do
            assert.has_error(function() Unicode.offset("😀", offset) end)
        end
        assert.has_error(function() Unicode.offset("😀", 1, true) end)
    end)
    it("rejects truncated, overlong, surrogate and out-of-range UTF-8", function()
        for _, bytes in ipairs({ "\240\159", "\192\128", "\237\160\128", "\244\144\128\128", "\226x\128" }) do
            assert.has_error(function() Unicode.boundaries(bytes) end)
        end
    end)
    it("aligns collapsed whitespace without fuzzy matching", function()
        assert.same({ [0] = 2, 3, 6, 7 }, Unicode.align("  a \n b ", "a b"))
        assert.is_nil(Unicode.align("abc", "abd"))
        assert.same({ [0] = 0, 1, 2 }, Unicode.align("é😀", "é😀"))
    end)
end)
