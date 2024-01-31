local ffi = require("ffi")
local C = ffi.C
local ffi_cast = ffi.cast
ffi.cdef[[
	void srand(unsigned int seed);
	int rand(void);
	typedef long long int64_t;
	double floor(double x);
]]
C.srand(ffi.cast("unsigned int", os.time()))
local bit_lshift = require('bit').lshift
local function rand() return C.rand() end
local function floor(x) return C.floor(x) end
local function rand64()
    local high = bit_lshift(ffi_cast("int64_t", rand()), 32)
    local low = ffi_cast("int64_t", rand())
    return high + low
end
local concat = table.concat
local tonumber = tonumber
local digits = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
local base = #digits
local digitBytes = ffi.new("uint8_t[?]", base + 1)
ffi.copy(digitBytes, digits)

local _M = {}
_M.__index = _M

local function nuid(opts)
	if type(opts) ~= "table" then opts = {} end
	local o = setmetatable({
		preLen = opts.preLen or 12,
		seqLen = opts.seqLen or 10, 
		minInc = opts.minInc or 33,
		maxInc = opts.maxInc or 333,
	}, _M)
	o.maxSeq = ffi.new("int64_t", base ^ o.seqLen)
	o.totalLen = o.preLen + o.seqLen
	o:resetSequential()
	o:randomizePrefix()
	return o
end

function _M:randomizePrefix()
	if self.preLen < 1 then
		self.pre = ""
		return
	end
	local pre = ffi.new("char[?]", self.preLen + 1)
	for i = 0, self.preLen - 1 do
		pre[i] = digitBytes[rand() % base]
	end
	self.pre = ffi.string(pre, self.preLen + 1)
end

function _M:resetSequential()
	self.seq = rand64() % self.maxSeq
	self.inc = rand() % (self.maxInc - self.minInc + 1) + self.minInc
end

function _M:next()
	if self.seqLen > 0 then
		self.seq = self.seq + self.inc
		if self.seq >= self.maxSeq then
			self:randomizePrefix()
			self:resetSequential()
		end
	else self:randomizePrefix()	end

	local str = ffi.new("char[?]", self.totalLen + 1)
	ffi.copy(str, self.pre)

	if self.seqLen > 0 then
		local seq, rem = self.seq, nil
		for i = self.totalLen - 1, self.preLen, -1 do
			rem = seq % base
			seq = floor(seq / base)
			str[i] = digitBytes[rem]
		end
	end

	return ffi.string(str, self.totalLen)
end
_M.__call = _M.next

return nuid
