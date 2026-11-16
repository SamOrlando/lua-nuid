-- Plain-Lua test suite: `lua tests/test_nuid.lua` (Lua 5.1-5.4, LuaJIT)
package.path = "./?.lua;" .. package.path

local before = {}
for k in pairs(_G) do before[k] = true end

local nuid = require("nuid")
local pass, fail = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then pass = pass + 1 else fail = fail + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end
local function eq(a, b, m) if a ~= b then error((m or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2) end end

local DIG = nuid.DIGITS
local VAL = {}
for i = 1, #DIG do VAL[DIG:sub(i, i)] = i - 1 end

test("no global leaks", function()
    for k in pairs(_G) do assert(before[k], "leaked global " .. tostring(k)) end
end)

test("default length and alphabet", function()
    local g = nuid()
    for _ = 1, 1000 do
        local id = g:next()
        eq(#id, 22, "length")
        assert(id:match("^[0-9A-Za-z]+$"), "alphabet: " .. id)
    end
end)

test("__call, new() and module next()", function()
    local g = nuid.new()
    eq(#g(), 22); eq(#nuid.next(), 22)
    assert(nuid.next() ~= nuid.next())
end)

test("uniqueness 200k", function()
    local g, seen = nuid(), {}
    for _ = 1, 200000 do
        local id = g:next(); assert(not seen[id], "dup " .. id); seen[id] = true
    end
end)

test("distinct generators get distinct prefixes", function()
    local seen = {}
    for _ = 1, 1000 do
        local p = nuid():next():sub(1, 12); assert(not seen[p], "dup prefix"); seen[p] = true
    end
end)

test("sequence strictly increasing and increment in [33,333)", function()
    local g = nuid()
    assert(g.inc >= 33 and g.inc < 333, "inc " .. g.inc)
    local prev = g:next()
    for _ = 1, 10000 do
        local id = g:next()
        if id:sub(1, 12) == prev:sub(1, 12) then assert(id > prev, prev .. " !< " .. id) end
        prev = id
    end
end)

local function decode_halves(s, loLen)
    local hi, lo = 0, 0
    local h = #s - loLen
    for i = 1, h do hi = hi * 62 + VAL[s:sub(i, i)] end
    for i = h + 1, #s do lo = lo * 62 + VAL[s:sub(i, i)] end
    return hi, lo
end

test("exact encoding of the sequence (no float precision loss)", function()
    local g = nuid()
    for _ = 1, 2000 do
        local id = g:next()
        local hi, lo = decode_halves(id:sub(13), g.loLen)
        eq(hi, g.hi, "hi"); eq(lo, g.lo, "lo")
    end
    -- largest value just below 62^10 must encode as zzzzzzzzzz
    g.hi, g.hiStr, g.lo, g.inc = g.hiMax - 1, ("z"):rep(5), g.loMax - 2, 1
    eq(g:next():sub(13), ("z"):rep(10))
end)

test("rollover re-randomizes prefix and resets sequence", function()
    local g = nuid()
    local pre = g:next():sub(1, 12)
    g.hi, g.hiStr, g.lo = g.hiMax - 1, ("z"):rep(5), g.loMax - 1
    local id = g:next()
    eq(#id, 22)
    assert(id:sub(1, 12) ~= pre, "prefix not reset")
end)

test("custom lengths", function()
    for _, c in ipairs({ {8, 0}, {0, 10}, {12, 1}, {4, 16}, {20, 3} }) do
        local g = nuid({ preLen = c[1], seqLen = c[2] })
        local seen = {}
        for _ = 1, 500 do
            local id = g()
            eq(#id, c[1] + c[2], "len"); assert(id:match("^[0-9A-Za-z]*$"))
            if c[1] + c[2] >= 8 then assert(not seen[id], "dup"); seen[id] = true end
        end
    end
end)

test("pure random mode (seqLen=0) changes every call", function()
    local g = nuid({ preLen = 8, seqLen = 0 })
    assert(g() ~= g())
end)

test("custom increments", function()
    local g = nuid({ minInc = 1, maxInc = 2 })
    local a = g:next(); local b = g:next()
    eq(g.inc, 1)
    local _, la = decode_halves(a:sub(13), g.loLen); local _, lb = decode_halves(b:sub(13), g.loLen)
    assert(lb == la + 1 or lb == 0)
end)

test("invalid options raise", function()
    assert(not pcall(nuid, { seqLen = -1 }))
    assert(not pcall(nuid, { seqLen = 17 }))
    assert(not pcall(nuid, { minInc = 10, maxInc = 10 }))
end)

test("seed reseeds every live generator", function()
    local a = nuid({ preLen = 12, seqLen = 4 })
    local b = nuid({ preLen = 8, seqLen = 4 })
    local ap, bp = a:next():sub(1, 12), b:next():sub(1, 8)
    local gp = nuid.next():sub(1, 12)
    nuid.seed()
    assert(a:next():sub(1, 12) ~= ap, "generator a kept its prefix")
    assert(b:next():sub(1, 8) ~= bp, "generator b kept its prefix")
    assert(nuid.next():sub(1, 12) ~= gp, "global generator kept its prefix")
end)

test("prefix digit distribution roughly uniform", function()
    local g, counts = nuid({ preLen = 12, seqLen = 0 }), {}
    for _ = 1, 10000 do
        local id = g()
        for i = 1, 12 do local c = id:sub(i, i); counts[c] = (counts[c] or 0) + 1 end
    end
    local n = 0
    for _, v in pairs(counts) do n = n + 1; assert(v > 1300 and v < 2700, "skewed " .. v) end
    eq(n, 62)
end)

local has_ffi, ffi = pcall(require, "ffi")
if has_ffi then
    test("fork does not repeat generator or global ids", function()
        ffi.cdef[[
            int fork(void);
            int waitpid(int pid, int *status, int options);
        ]]
        local g = nuid({ preLen = 16, seqLen = 0 })
        local seq = nuid({ preLen = 12, seqLen = 10 })
        nuid.next()
        local path = os.tmpname()
        local pid = tonumber(ffi.C.fork())
        if not pid or pid < 0 then error("fork failed") end
        if pid == 0 then
            nuid.seed()
            local f = assert(io.open(path, "w"))
            f:write(g(), "\n", g(), "\n", seq(), "\n", seq(), "\n", nuid.next(), "\n", nuid.next(), "\n")
            f:close()
            os.exit(0)
        end
        local status = ffi.new("int[1]")
        ffi.C.waitpid(pid, status, 0)
        local parent = { g(), g(), seq(), seq(), nuid.next(), nuid.next() }
        local f = assert(io.open(path))
        local child = {}
        for line in f:lines() do child[#child + 1] = line end
        f:close()
        os.remove(path)
        eq(#child, 6, "child ids")
        for i = 1, 6 do
            assert(parent[i] ~= child[i], "repeated " .. parent[i])
        end
    end)
end

print(string.format("%s%s: %d passed, %d failed", _VERSION, jit and (" / " .. jit.version) or "", pass, fail))
os.exit(fail == 0 and 0 or 1)
