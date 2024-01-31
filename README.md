# Lua NUID Generator

A Lua module for generating highly performant, unique identifiers (NUIDs) using LuaJIT's FFI (Foreign Function Interface) for enhanced numerical precision and efficiency.

## Features

- Generates unique identifiers combining random and sequential components.
- Leverages LuaJIT's FFI for 64-bit arithmetic, ensuring precise handling of large numbers.
- Customizable length for the random prefix and sequential part.
- Efficient string handling and generation.

## Requirements

- LuaJIT

## Installation

Simply include the `nuid.lua` file in your Lua project and require it in your script.

## Usage

```lua
local nuid = require("nuid")

-- Create a new NUID generator with default settings
local generator = nuid()

-- Generate a new unique identifier
local id = generator:next()
print(id)
```

### Customization

You can customize the length of the prefix and sequential part as well as the minimum and maximum increment values.

```lua
local generator = nuid({
    preLen = 12,  -- Length of the random prefix
    seqLen = 10,  -- Length of the sequential part
    minInc = 33,  -- Minimum increment for the sequential part
    maxInc = 333  -- Maximum increment for the sequential part
})
```

## API Reference

- `nuid(opts)`: Creates a new NUID generator. `opts` is an optional table for customization.
- `generator:next()`: Generates and returns a new unique identifier.

## How It Works

The module utilizes LuaJIT's FFI to interface with C standard library functions for random number generation and floor operation. It combines a random prefix (generated using a 64-bit random number) with a sequential number that increments with each call to `:next()`. This approach ensures a high degree of uniqueness for each generated identifier.

## License

This module is available under the [MIT License](LICENSE).
