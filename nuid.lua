-- nuid.lua
-- High-performance NATS Unique Identifier (NUID) generator for LuaJIT.
--
-- 12-char crypto-style prefix (entropy-friendly) + 10-char sequential
-- counter that advances by a pseudo-random increment.  Total 22 base-62
-- characters.  Matches the algorithm used by nats-io/nuid (Go reference).
--
-- Configurable lengths are retained for flexibility; defaults match the
-- official implementation.

local ffi = require("ffi")
local bit = require("bit")
local C   = ffi.C

ffi.cdef[[
    void srand(unsigned int seed);
    int  rand(void);
    typedef unsigned long long uint64_t;
    double floor(double x);
]]

-- Mix time + a little extra entropy (still not cryptographic, but better
-- than a single os.time() call).
C.srand(ffi.cast("unsigned int",
    (os.time() % 0x7fffffff) * 1103515245 + (os.clock() * 1e6)))

local bit_lshift = bit.lshift
local ffi_cast   = ffi.cast
local ffi_string = ffi.string
local ffi_copy   = ffi.copy
local floor      = C.floor

local function rand()  return C.rand() end

-- 64-bit value from two 31-bit C.rand() calls
local function rand64()
    local high = bit_lshift(ffi_cast("uint64_t", rand()), 32)
    local low  = ffi_cast("uint64_t", rand())
    return high + low
end

local digits     = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
local base       = #digits          -- 62
local digitBytes = ffi.new("uint8_t[?]", base)
ffi_copy(digitBytes, digits)

local _M = {}
_M.__index = _M

local function nuid(opts)
    if type(opts) ~= "table" then opts = {} end

    local preLen = opts.preLen or 12
    local seqLen = opts.seqLen or 10
    local minInc = opts.minInc or 33
    local maxInc = opts.maxInc or 333   -- exclusive upper bound in official Go

    -- Exact 62^seqLen as uint64 (successive multiply, no float power)
    local maxSeq = ffi.new("uint64_t", 1)
    for _ = 1, seqLen do
        maxSeq = maxSeq * base
    end

    local totalLen = preLen + seqLen
    local o = setmetatable({
        preLen   = preLen,
        seqLen   = seqLen,
        minInc   = minInc,
        maxInc   = maxInc,
        maxSeq   = maxSeq,
        totalLen = totalLen,
        -- single reusable output buffer (biggest perf win)
        buf      = ffi.new("char[?]", totalLen + 1),
    }, _M)

    o:resetSequential()
    o:randomizePrefix()
    return o
end

function _M:randomizePrefix()
    local preLen = self.preLen
    local buf    = self.buf
    if preLen < 1 then return end
    for i = 0, preLen - 1 do
        buf[i] = digitBytes[rand() % base]
    end
end

function _M:resetSequential()
    -- Official range is [minInc, maxInc) → 33 … 332
    self.seq = rand64() % self.maxSeq
    self.inc = (rand() % (self.maxInc - self.minInc)) + self.minInc
end

function _M:next()
    local seqLen = self.seqLen
    local buf    = self.buf
    local total  = self.totalLen
    local preLen = self.preLen

    if seqLen > 0 then
        self.seq = self.seq + self.inc
        if self.seq >= self.maxSeq then
            self:randomizePrefix()
            self:resetSequential()
        end

        -- Encode sequential counter (low digits first)
        local seq = self.seq
        for i = total - 1, preLen, -1 do
            local rem = tonumber(seq % base)
            seq = floor(seq / base)          -- integer division via floor
            buf[i] = digitBytes[rem]
        end
    else
        -- pure random prefix mode
        self:randomizePrefix()
    end

    return ffi_string(buf, total)
end

-- Allow `nid()` syntax
_M.__call = _M.next

return nuid