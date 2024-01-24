local bit = require("bit")
local ffi = require("ffi")
local C = ffi.C

ffi.cdef[[
	void srand(unsigned int seed);
	int rand(void);
]]
C.srand(os.time())
local function rand()
    return C.rand()
end

local digits = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
local base = 62
local preLen = 12
local seqLen = 10
local maxSeq = 839299365868340224
local minInc = 33
local maxInc = 333
local totalLen = preLen + seqLen

local _M = {}

function _M:randomizePrefix()
    local pre = ffi.new("char[?]", preLen)
    for i = 0, preLen - 1 do
        pre[i] = digits:byte(rand() % base + 1)
    end
    self.pre = ffi.string(pre, preLen)
end

function _M:resetSequential()
    self.seq = rand() % maxSeq
    self.inc = minInc + rand() % (maxInc - minInc)
end

function _M:__call()
    local n = setmetatable({}, _M)
    n:resetSequential()
    n:randomizePrefix()
    return n
end

function _M:next()
    self.seq = self.seq + self.inc
    if self.seq >= maxSeq then
        self:randomizePrefix()
        self:resetSequential()
    end
    local seq = self.seq

    local b = ffi.new("char[?]", totalLen)
    ffi.copy(b, self.pre)

    for i = totalLen - 1, preLen, -1 do
        local index = seq % base + 1
        b[i] = digits:byte(index)
        seq = bit.rshift(seq, base)
    end

    return ffi.string(b, totalLen)
end

-- Test
print(_M():next())
print(_M():next())


return _M
