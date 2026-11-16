# lua-nuid

Pure-Lua port of the [NATS NUID](https://github.com/nats-io/nuid) unique
identifier generator. Works on **Lua 5.1, 5.2, 5.3, 5.4 and LuaJIT** — no FFI
or C modules required.

A NUID is 22 base-62 characters:

* 12 characters of random prefix (read from `/dev/urandom` when available)
* 10 characters of a sequence starting at a random value and advancing by a
  random increment in `[33, 333)`
* when the sequence overflows `62^10`, the prefix is re-randomized and the
  sequence and increment are reset (identical to the Go reference)

## Installation

```sh
luarocks make nuid-1.0.0-1.rockspec   # or just copy nuid.lua into your project
```

## Usage

```lua
local nuid = require("nuid")

local gen = nuid()            -- or nuid.new()
print(gen:next())             -- e.g. nataW3t1nKzs3iOIofD1Om
print(gen())                  -- generators are callable

print(nuid.next())            -- shared default generator, like Go's nuid.Next()
```

Inbox example:

```lua
local mailbox_nuid      = nuid()
local mailbox_nuid_tail = nuid({ preLen = 8, seqLen = 0 })   -- pure random
local function create_inbox()
  return "_INBOX." .. mailbox_nuid() .. "." .. mailbox_nuid_tail()
end
-- _INBOX.AKVlRx7reWcacdtRxHYjnc.nNWzXCMR
```

### Options

```lua
nuid({
  preLen = 12,  -- random prefix length (>= 0)
  seqLen = 10,  -- sequence length (0..16); 0 = new random prefix every call
  minInc = 33,  -- minimum increment (inclusive)
  maxInc = 333, -- maximum increment (exclusive)
})
```

Invalid options raise an error.

## API

| Call | Description |
|---|---|
| `nuid(opts)` / `nuid.new(opts)` | create a generator |
| `gen:next()` / `gen()` | next ID |
| `gen:randomizePrefix()` | pick a new random prefix |
| `gen:resetSequential()` | pick a new random sequence start and increment |
| `nuid.next()` | next ID from a lazily created shared generator |
| `nuid.seed()` | reseed every live generator after `fork` |

Generators are not safe to share between OS threads (Lua states are
single-threaded anyway); they are fine to share between coroutines.

`fork` copies every generator and the `/dev/urandom` buffer. Call
`nuid.seed()` in the child before the next id. That reopens the random source
and re-randomizes each live generator. A child that skips it repeats the
parent's ids.

## Implementation notes

`62^10` exceeds the 2^53 integer precision of doubles, so the sequence is
held as two exact halves (`hi`, `lo`, base `62^5`). This keeps the math exact
on every Lua version without FFI `uint64_t`. Only the low half is re-encoded
on most calls; the high half's string is cached.

## Tests

```sh
for l in lua5.1 lua5.2 lua5.3 lua5.4 luajit; do $l tests/test_nuid.lua; done
# or: luarocks test
```

## Benchmark

`tests/bench_uuid.lua` times sequential NUIDs against
[lua-resty-jit-uuid](https://luarocks.org/modules/thibaultcha/lua-resty-jit-uuid)
0.0.7, the most-downloaded UUID rock on LuaRocks (2,845,716 downloads).
UUID v4 has 122 bits of unique data. Each base-62 character holds 5.954 bits,
so 20 characters are 119.08 bits and 21 characters are 125.04 bits.

```sh
luarocks install lua-resty-jit-uuid
luajit tests/bench_uuid.lua
```

One run on LuaJIT 2.1.1724512491. Each figure is the median of 7 wall-time
rounds of 1,000,000 ids after 20,000 warmup calls. A separate sample of
200,000 ids had 0 collisions for every generator.

| Generator | bits | ns/id | ids/sec | chars | vs UUID v4 |
|---|---:|---:|---:|---:|---:|
| `nuid()` default | 130.99 | 127.5 | 7,841,297 | 22 | 4.69× |
| `nuid` 12+8 | 119.08 | 125.6 | 7,961,890 | 20 | 4.76× |
| `nuid` 12+9 | 125.04 | 151.9 | 6,583,046 | 21 | 3.94× |
| `nuid` 11+10 | 125.04 | 152.1 | 6,572,733 | 21 | 3.93× |
| `nuid` 12+10 | 130.99 | 150.8 | 6,630,888 | 22 | 3.97× |
| UUID v4 | 122.00 | 598.2 | 1,671,680 | 36 | 1× |

`nuid()` takes the module defaults, `preLen` 12 and `seqLen` 10, which is the
same generator as the `12+10` row. A head-to-head of only those two stayed
within 126–135 ns/id. The wider gap in the table is from running every row in
one process. `12+8` stops short of 122 bits. `12+9` and `11+10` both clear it.

## License

[MIT](LICENSE)
