-- Benchmark lats nuid against the most-downloaded UUID rock on LuaRocks.
-- lua-resty-jit-uuid 0.0.7-2 (thibaultcha): 2,845,716 downloads.
-- The rock named uuid (Tieske) is second at 1,465,986 and is not this run.
--
-- lats.nuid is this module (lats-lua/modules/nuid.lua -> lua-nuid/nuid.lua).
-- The first row is nuid() with the module's default preLen and seqLen.
-- The other rows are the preLen/seqLen choices around a 122-bit UUID v4:
--   12+8  (20 chars, 119.08 bits), 12+9 and 11+10 (21 chars, 125.04 bits),
--   12+10 (22 chars, 130.99 bits).
--
-- Run from the repo: luajit tests/bench_uuid.lua
-- Needs lua-resty-jit-uuid on package.path (luarocks install --local lua-resty-jit-uuid).

local script = arg and arg[0] or "tests/bench_uuid.lua"
local root = script:match("^(.*)/tests/[^/]+$") or "."
local home = os.getenv("HOME") or ""
package.path = root .. "/?.lua;"
    .. home .. "/.luarocks/share/lua/5.1/?.lua;"
    .. home .. "/.luarocks/share/lua/5.1/?/init.lua;"
    .. package.path

local nuid = require("nuid")
local uuid = require("resty.jit-uuid")
uuid.seed()

local ffi = require("ffi")
ffi.cdef[[
    typedef struct timespec {
        long tv_sec;
        long tv_nsec;
    } timespec;
    int clock_gettime(int clk_id, struct timespec *tp);
]]
local ts = ffi.new("struct timespec")
local function now_ns()
    if ffi.C.clock_gettime(1, ts) ~= 0 then error("clock_gettime failed") end
    return tonumber(ts.tv_sec) * 1e9 + tonumber(ts.tv_nsec)
end

local N = 1000000
local WARMUP = 20000
local ROUNDS = 7
local UNIQ = 200000
local byte = string.byte

local function bench(fn)
    local sink = 0
    for _ = 1, WARMUP do
        sink = sink + byte(fn(), 1)
    end
    local samples = {}
    for r = 1, ROUNDS do
        local t0 = now_ns()
        for _ = 1, N do
            sink = sink + byte(fn(), 1)
        end
        samples[r] = now_ns() - t0
    end
    table.sort(samples)
    return samples[math.ceil(#samples / 2)], sink
end

local function collisions(fn, n)
    local seen, dups = {}, 0
    for _ = 1, n do
        local id = fn()
        if seen[id] then dups = dups + 1 else seen[id] = true end
    end
    return dups
end

local function commas(n)
    local s = string.format("%.0f", n)
    while true do
        local nexts, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        s = nexts
        if k == 0 then return s end
    end
end

local LOG2_62 = math.log(62) / math.log(2)
local specs = {
    { pre = 12, seq = 8 },
    { pre = 12, seq = 9 },
    { pre = 11, seq = 10 },
    { pre = 12, seq = 10 },
}

local default_gen = nuid()
local rows = {
    {
        name = "nuid default",
        note = string.format("nuid(), preLen %d, seqLen %d", default_gen.preLen, default_gen.seqLen),
        bits = (default_gen.preLen + default_gen.seqLen) * LOG2_62,
        fn = function() return default_gen() end,
        check = function(id)
            return #id == default_gen.preLen + default_gen.seqLen
                and id:match("^[0-9A-Za-z]+$") ~= nil
        end,
    },
}
for i = 1, #specs do
    local spec = specs[i]
    local gen = nuid({ preLen = spec.pre, seqLen = spec.seq })
    local width = spec.pre + spec.seq
    rows[#rows + 1] = {
        name = string.format("nuid %d+%d", spec.pre, spec.seq),
        note = string.format("%d char prefix, %d char sequence", spec.pre, spec.seq),
        bits = width * LOG2_62,
        fn = function() return gen() end,
        check = function(id) return #id == width and id:match("^[0-9A-Za-z]+$") ~= nil end,
    }
end
rows[#rows + 1] = {
    name = "uuid v4",
    note = "36 chars, RFC 4122 version 4",
    bits = 122,
    fn = function() return uuid() end,
    check = function(id) return uuid.is_valid(id) end,
}

print(jit.version)
print(string.format("nuid %s    resty.jit-uuid %s", nuid._VERSION, uuid._VERSION))
print(string.format("%d calls x %d rounds, median, after %d warmup calls", N, ROUNDS, WARMUP))
print(string.format("%-12s %8s %10s %14s %12s %6s  %s",
    "generator", "bits", "ns/id", "ids/sec", "median ms", "chars", "sample"))

local results = {}
local failed = 0
for i = 1, #rows do
    local row = rows[i]
    local sample = row.fn()
    if not row.check(sample) then
        failed = failed + 1
        print("FAIL shape " .. row.name .. " " .. tostring(sample))
    end
    local median_ns, sink = bench(row.fn)
    if sink < 0 then print(sink) end
    local ns = median_ns / N
    local rate = N / (median_ns / 1e9)
    local dups = collisions(row.fn, UNIQ)
    if dups ~= 0 then
        failed = failed + 1
        print(string.format("FAIL collisions %s %d/%d", row.name, dups, UNIQ))
    end
    results[i] = {
        name = row.name, note = row.note, bits = row.bits,
        ns = ns, rate = rate, median_ns = median_ns, sample = sample, dups = dups,
    }
    print(string.format("%-12s %8.2f %10.1f %14s %12.2f %6d  %s",
        row.name, row.bits, ns, commas(rate), median_ns / 1e6, #sample, sample))
end

local base = results[#results]
print("")
print("Comparison")
print(string.format("Opponent is lua-resty-jit-uuid %s (LuaRocks download leader, %s).",
    uuid._VERSION, "2,845,716 downloads; Tieske uuid is 1,465,986"))
print(string.format("Each figure is the median of %d wall-time runs of %s ids on this machine.",
    ROUNDS, commas(N)))
local dup_parts = {}
for i = 1, #results do
    dup_parts[i] = string.format("%s %d", results[i].name, results[i].dups)
end
print(string.format("Uniqueness sample is %s ids. Collisions: %s.", commas(UNIQ), table.concat(dup_parts, ", ")))
print("")
for i = 1, #results - 1 do
    local r = results[i]
    print(string.format("%s is %.2fx the uuid v4 rate (%.1f ns vs %.1f ns) at %.2f bits against 122.",
        r.name, base.ns / r.ns, r.ns, base.ns, r.bits))
end
print("nuid default is nuid() with no options. The other nuid rows pass preLen and seqLen.")
print("uuid v4 is 16 bytes of math.random with version and variant bits, formatted as 36 hex characters. uuid.seed() ran once, outside the loop.")

os.exit(failed == 0 and 0 or 1)
