-- Compile only: checking files must never execute reader or live-test code.
for _, path in ipairs(arg) do
    local chunk, err = loadfile(path)
    assert(chunk, err)
end
