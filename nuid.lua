-- nuid.lua
-- NATS Unique Identifier (NUID) generator in pure Lua.
--
-- Port of https://github.com/nats-io/nuid (Go reference):
--   * 12 base-62 characters of random prefix (from a CSPRNG when available)
--   * 10 base-62 characters of a sequence that starts at a random value and
--     advances by a random increment in [minInc, maxInc)
--   * when the sequence reaches 62^seqLen the prefix is re-randomized and
--     the sequence/increment are reset
--   => 22 characters total
--
-- Works on Lua 5.1, 5.2, 5.3, 5.4 and LuaJIT. No compiled module.
-- Fork copies a generator's prefix, sequence, and the /dev/urandom buffer.
-- The child calls nuid.seed() before taking an id. That reopens the CSPRNG
-- and re-randomizes every live generator, so workers do not share ids.
--
-- 62^10 (~8.4e17) does not fit in a double's 53-bit mantissa, and Lua 5.1 /
-- LuaJIT have no native 64-bit integers, so the sequence is kept as two
-- halves (hi, lo) in base 62^loLen. Every value stays well below 2^53,
-- so arithmetic is exact on every Lua version.

local floor      = math.floor
local byte, sub  = string.byte, string.sub
local concat     = table.concat
local io_open    = io.open
local setmetatable, type, error, tostring = setmetatable, type, error, tostring

local DIGITS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
local BASE   = 62

local DIGIT = {}            -- [0..61] -> one-character string
for i = 0, BASE - 1 do DIGIT[i] = sub(DIGITS, i + 1, i + 1) end

local MAX_HALF = 8          -- 62^8 ~ 2.2e14 < 2^53; caps seqLen at 16

---------------------------------------------------------------------------
-- Randomness
---------------------------------------------------------------------------
-- Prefer the OS CSPRNG (like Go's crypto/rand). Bytes are read in blocks so
-- the hot path (pure-random mode, seqLen = 0) does not hit the OS each call.
local urandom = io_open and io_open("/dev/urandom", "rb")
local rbuf, rpos, RBLOCK = "", 1, 4096

local function seed_fallback(pid)
    -- Lua 5.4 seeds math.random randomly at startup; for older versions mix
    -- several weak sources rather than a lone os.time().
    if not _VERSION:find("5%.4") then
        local addr = tonumber(tostring({}):match("0x(%x+)") or "0", 16) or 0
        math.randomseed((os.time() + floor(os.clock() * 1e6) + addr + (pid or 0)) % 2147483647)
    end
end
if not urandom then seed_fallback() end

local random = math.random

local function reopen_urandom()
    if urandom then pcall(urandom.close, urandom) end
    urandom = io_open and io_open("/dev/urandom", "rb") or nil
    rbuf, rpos = "", 1
end

local function rand_byte()
    if urandom then
        if rpos > #rbuf then
            rbuf = urandom:read(RBLOCK)
            if not rbuf or #rbuf == 0 then
                urandom, rbuf = nil, ""
                seed_fallback()
                return random(0, 255)
            end
            rpos = 1
        end
        local b = byte(rbuf, rpos)
        rpos = rpos + 1
        return b
    end
    return random(0, 255)
end

-- Uniform integer in [0, n), n <= 2^48. Uses rejection sampling (no bias).
local function rand_below(n)
    if n <= 1 then return 0 end
    local range, nbytes = 256, 1
    while range < n do range, nbytes = range * 256, nbytes + 1 end
    local limit = range - range % n
    while true do
        local v = 0
        for _ = 1, nbytes do v = v * 256 + rand_byte() end
        if v < limit then return v % n end
    end
end

---------------------------------------------------------------------------
-- Generator
---------------------------------------------------------------------------
local Nuid = {}
Nuid.__index = Nuid

-- Encode non-negative integer v as exactly len base-62 digits (big-endian).
local tmp = {}
local function encode(v, len)
    for i = len, 1, -1 do
        local q = floor(v / BASE)
        tmp[i] = DIGIT[v - q * BASE]
        v = q
    end
    return concat(tmp, "", 1, len)
end

local function pow62(n)
    local r = 1
    for _ = 1, n do r = r * BASE end
    return r
end

-- One concatenation for the low half. loLen is 1..8. Big-endian, same as encode.
local function emit1(pre, hi, v)
    return pre .. hi .. DIGIT[v % BASE]
end
local function emit2(pre, hi, v)
    local a = v % BASE; v = floor(v / BASE)
    return pre .. hi .. DIGIT[v % BASE] .. DIGIT[a]
end
local function emit3(pre, hi, v)
    local a = v % BASE; v = floor(v / BASE)
    local b = v % BASE; v = floor(v / BASE)
    return pre .. hi .. DIGIT[v % BASE] .. DIGIT[b] .. DIGIT[a]
end
local function emit4(pre, hi, v)
    local a = v % BASE; v = floor(v / BASE)
    local b = v % BASE; v = floor(v / BASE)
    local c = v % BASE; v = floor(v / BASE)
    return pre .. hi .. DIGIT[v % BASE] .. DIGIT[c] .. DIGIT[b] .. DIGIT[a]
end
local function emit5(pre, hi, v)
    local a = v % BASE; v = floor(v / BASE)
    local b = v % BASE; v = floor(v / BASE)
    local c = v % BASE; v = floor(v / BASE)
    local d = v % BASE; v = floor(v / BASE)
    return pre .. hi .. DIGIT[v % BASE] .. DIGIT[d] .. DIGIT[c] .. DIGIT[b] .. DIGIT[a]
end
local function emit6(pre, hi, v)
    local a = v % BASE; v = floor(v / BASE)
    local b = v % BASE; v = floor(v / BASE)
    local c = v % BASE; v = floor(v / BASE)
    local d = v % BASE; v = floor(v / BASE)
    local e = v % BASE; v = floor(v / BASE)
    return pre .. hi .. DIGIT[v % BASE] .. DIGIT[e] .. DIGIT[d] .. DIGIT[c] .. DIGIT[b] .. DIGIT[a]
end
local function emit7(pre, hi, v)
    local a = v % BASE; v = floor(v / BASE)
    local b = v % BASE; v = floor(v / BASE)
    local c = v % BASE; v = floor(v / BASE)
    local d = v % BASE; v = floor(v / BASE)
    local e = v % BASE; v = floor(v / BASE)
    local f = v % BASE; v = floor(v / BASE)
    return pre .. hi .. DIGIT[v % BASE] .. DIGIT[f] .. DIGIT[e] .. DIGIT[d] .. DIGIT[c] .. DIGIT[b] .. DIGIT[a]
end
local function emit8(pre, hi, v)
    local a = v % BASE; v = floor(v / BASE)
    local b = v % BASE; v = floor(v / BASE)
    local c = v % BASE; v = floor(v / BASE)
    local d = v % BASE; v = floor(v / BASE)
    local e = v % BASE; v = floor(v / BASE)
    local f = v % BASE; v = floor(v / BASE)
    local g = v % BASE; v = floor(v / BASE)
    return pre .. hi .. DIGIT[v % BASE] .. DIGIT[g] .. DIGIT[f] .. DIGIT[e] .. DIGIT[d] .. DIGIT[c] .. DIGIT[b] .. DIGIT[a]
end
local EMIT = { emit1, emit2, emit3, emit4, emit5, emit6, emit7, emit8 }

-- Weak, so a discarded generator can be collected. seed() copies the keys out first.
local live = setmetatable({}, { __mode = "k" })

local function new(opts)
    if type(opts) ~= "table" then opts = {} end
    local preLen = opts.preLen or 12
    local seqLen = opts.seqLen or 10
    local minInc = opts.minInc or 33
    local maxInc = opts.maxInc or 333   -- exclusive, as in Go

    if preLen < 0 or seqLen < 0 or preLen % 1 ~= 0 or seqLen % 1 ~= 0 then
        error("nuid: preLen and seqLen must be non-negative integers", 2)
    end
    if seqLen > 2 * MAX_HALF then
        error("nuid: seqLen must be <= " .. (2 * MAX_HALF), 2)
    end
    if seqLen > 0 and not (minInc >= 1 and maxInc > minInc) then
        error("nuid: require 1 <= minInc < maxInc", 2)
    end

    local loLen = seqLen - floor(seqLen / 2)   -- lo gets the larger half
    local hiLen = seqLen - loLen
    local self = setmetatable({
        preLen = preLen,
        seqLen = seqLen,
        minInc = minInc,
        maxInc = maxInc,
        totalLen = preLen + seqLen,
        loLen = loLen,
        hiLen = hiLen,
        loMax = pow62(loLen),
        hiMax = pow62(hiLen),
        emit = EMIT[loLen],
        pre = "",
    }, Nuid)
    self:randomizePrefix()
    self:resetSequential()
    live[self] = true
    return self
end

function Nuid:randomizePrefix()
    local n = self.preLen
    for i = 1, n do tmp[i] = DIGIT[rand_byte() % BASE] end   -- same as Go
    self.pre = concat(tmp, "", 1, n)
end

function Nuid:resetSequential()
    if self.seqLen == 0 then return end
    self.hi  = rand_below(self.hiMax)
    self.lo  = rand_below(self.loMax)
    self.inc = self.minInc + rand_below(self.maxInc - self.minInc)
    self.hiStr = encode(self.hi, self.hiLen)
end

-- Current sequence value as a number (exact only while < 2^53; informational).
function Nuid:seqValue()
    return (self.hi or 0) * (self.loMax or 1) + (self.lo or 0)
end

function Nuid:next()
    if self.seqLen == 0 then          -- pure random mode
        self:randomizePrefix()
        return self.pre
    end
    local lo = self.lo + self.inc
    local loMax = self.loMax
    if lo >= loMax then
        local carry = floor(lo / loMax)
        lo = lo - carry * loMax
        local hi = self.hi + carry
        if hi >= self.hiMax then       -- rollover: new prefix + new sequence
            self:randomizePrefix()
            self:resetSequential()
            lo = self.lo
        else
            self.hi = hi
            self.hiStr = encode(hi, self.hiLen)
        end
    end
    self.lo = lo
    return self.emit(self.pre, self.hiStr, lo)
end

Nuid.__call = Nuid.next

-- Module: callable for backward compatibility (`require("nuid")(opts)`).
local M = setmetatable({
    new = new,
    _VERSION = "1.0.0",
    DIGITS = DIGITS,
}, { __call = function(_, opts) return new(opts) end })

-- Call in the child after fork, before the next id. Fork copied every generator.
function M.seed()
    reopen_urandom()
    if not urandom then seed_fallback() end
    local list, n = {}, 0
    for g in pairs(live) do
        n = n + 1
        list[n] = g
    end
    for i = 1, n do
        list[i]:randomizePrefix()
        list[i]:resetSequential()
    end
end

-- Shared default generator, mirroring Go's nuid.Next().
local global
function M.next()
    global = global or new()
    return global:next()
end

return M
