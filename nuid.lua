local _M = {}
_M.__index = _M

local ffi = require("ffi")
local C = ffi.C
local bit_rshift = require("bit").rshift

ffi.cdef[[
	void srand(unsigned int seed);
	int rand(void);
]]
C.srand(os.time())
local function rand() return C.rand() end

local digits = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

local function nuid(opts)
	if type(opts) ~= "table" then opts = {} end
	local o = setmetatable({
		digits = opts.digits or digits,
		base = opts.base or 62,
		preLen = opts.preLen or 12,
		seqLen = opts.seqLen or 10,
		minInc = opts.minInc or 33,
		maxInc = opts.maxInc or 333,
	}, _M)
	o.totalLen = o.preLen + o.seqLen
	o.maxSeq = o.base ^ o.seqLen
	o:resetSequential()
	o:randomizePrefix()
	return o
end

function _M:randomizePrefix()
	local pre = ffi.new("char[?]", self.preLen)
	local digits = self.digits
	for i = 0, self.preLen - 1 do
		pre[i] = digits:byte((rand() % self.base) + 1)
	end
	self.pre = ffi.string(pre, self.preLen)
end

function _M:resetSequential()
	self.seq = rand() % self.maxSeq
	self.inc = self.minInc + (rand() % (self.maxInc - self.minInc))
end

function _M:next()
	self.seq = self.seq + self.inc
	if self.seq >= self.maxSeq then
		self:randomizePrefix()
		self:resetSequential()
	end

	local b = ffi.new("char[?]", self.totalLen)
	ffi.copy(b, self.pre)

	local seq, digits, base, rem = self.seq, self.digits, self.base, 1
    for i = self.totalLen - 1, self.preLen, -1 do
        rem = seq % self.base
        seq = bit_rshift(seq, 1)
        b[i] = digits:byte(rem + 1)
    end

	return ffi.string(b, self.totalLen)
end
_M.__call = _M.next

-- Test
-- local n, total = 1, 0
-- while n < 1500 do
--	local s, nid = 1, nuid()
--	--print("-- new nuid: " .. nid())
--	while s < 10000 do
--		nid()
--		s = s + 1
--	end
--	n = n + 1
--end

--# time luajit modules/nuid.lua (i7-4790K)
--real    0m1.326s
--user    0m1.326s
--sys     0m0.000s

return nuid
