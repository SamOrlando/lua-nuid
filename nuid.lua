local ffi = require("ffi")
local C = ffi.C
local floor = math.floor
local concat = table.concat

ffi.cdef[[
	void srand(unsigned int seed);
	int rand(void);
	typedef long long int64_t;  // Define a 64-bit integer type
]]
C.srand(ffi.cast("unsigned int", os.time()))
local function rand() return C.rand() end
local function rand64()
	local high = rand()  -- Generate the high 32 bits
    local low = rand()   -- Generate the low 32 bits
    return ffi.new("int64_t", high) * (2^32) + low
end

local digits = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
local base = #digits
local digitBytes = ffi.new("uint8_t[?]", base + 1)
ffi.copy(digitBytes, digits)

local _M = {}
_M.__index = _M

local function nuid(opts)
	if type(opts) ~= "table" then opts = {} end
	local o = setmetatable({
		preLen = opts.preLen or 14, -- set 14 to meet 22=14+8 
		seqLen = opts.seqLen or 8, -- set to 8 or lower to prevent lua number failures (52bit rep)
		minInc = opts.minInc or 33,
		maxInc = opts.maxInc or 333,
	}, _M)
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
	self.maxSeq = self.seqLen > 0 and base ^ self.seqLen or 1
	self.seq = self.seqLen > 0 and tonumber(rand64()) % self.maxSeq or 1
	self.inc = rand() % (self.maxInc - self.minInc + 1) + self.minInc
end

function _M:next()
	if self.seqLen > 0 then
		self.seq = self.seq + self.inc
		if self.seq >= self.maxSeq then
			self:randomizePrefix()
			self:resetSequential()
		end
	elseif self.preLen > 0 then
		self:randomizePrefix()
	end

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
