local FakeReader = {}
FakeReader.__index = FakeReader

function FakeReader.new(path)
    return setmetatable({ document = { file = path }, events = {} }, FakeReader)
end

function FakeReader:onClose()
    table.insert(self.events, "saved and closed")
    self.document = nil
end

function FakeReader:showFileManager(path, selected)
    table.insert(self.events, "file manager")
    self.file_manager_path, self.selected_files = path, selected
end

function FakeReader:onHome()
    local path = self.document.file
    self:onClose()
    self:showFileManager(path)
end

function FakeReader:reloadDocument(after_close, seamless, after_open)
    local path = self.document.file
    self:onClose()
    if after_close then after_close(path) end
    self.reopened = FakeReader.new(path)
    self.seamless = seamless
    if after_open then after_open(self.reopened) end
end

return FakeReader
