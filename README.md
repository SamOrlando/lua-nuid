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

Generators are not safe to share between OS threads (Lua states are
single-threaded anyway); they are fine to share between coroutines.

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

## License

[MIT](LICENSE)
