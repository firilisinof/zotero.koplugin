local ReaderReturn = {}

--- Bind library return to this successfully opened reader only. Example: ReaderReturn.bind(reader, callback).
---@param reader table
---@param callback function
function ReaderReturn.bind(reader, callback)
    local show_files = reader.showFileManager
    local reload = reader.reloadDocument
    local returned = false
    -- KOReader's Home, file-browser menu and end-of-book actions all call this
    -- after onClose has saved the document. Switching books and quitting do not.
    reader.showFileManager = function(current, ...)
        show_files(current, ...)
        if returned then return end
        returned = true
        callback()
    end
    -- Layout/provider reloads replace ReaderUI, but remain the same reading session.
    reader.reloadDocument = function(current, after_close, seamless, after_open)
        return reload(current, after_close, seamless, function(reopened)
            if after_open then after_open(reopened) end
            ReaderReturn.bind(reopened, callback)
        end)
    end
end

return ReaderReturn
