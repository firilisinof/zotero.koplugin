local Reader = {}
Reader.__index = Reader

function Reader.new(path, page, count)
    local self = setmetatable({ page = page or 1, pages = count or 20, saved = 0 }, Reader)
    self.document = { file = path, getPageCount = function() return self.pages end }
    self.paging = {
        getLastProgress = function() return self.page end,
        onGotoPage = function(_, value) self.page = value end,
    }
    return self
end
function Reader:saveSettings() self.saved = self.saved + 1 end
return Reader
