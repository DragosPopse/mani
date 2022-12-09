# mani
Mani is an odin-to-lua exporter that generates Lua C API bindings for your odin source files. This project is WIP, and doesn't have many features yet. The attributes API is subject to considerable amount of changes

```odin 
package main

import "core:fmt"
import "shared:lua"
import "shared:luaL"
import "shared:mani"

@(LuaExport = {
    Name = "my_nice_fn",
})
test :: proc(var: int) -> (result1: int, result2: int) {
    fmt.printf("Lua: Var is %d\n", var)
    result1 = 60 + var
    result2 = 40 + var
    return
}

main :: proc() {
    L := luaL.newstate()
    mani.export_all(L, mani.global_state)
}
```
```lua
-- lua code
res1, res2 = my_nice_fn(3)
print("Results from Call: " .. res1 .. " " .. res2)
```

## Getting Started
- Install https://github.com/DragosPopse/odin-lua
- Place the contents of the shared directory in `%ODIN_ROOT%/shared` folder or a collection of your choice. If `ODIN_ROOT` is configured, you can just call `copy_to_shared.bat`
- Build `generator` directory `odin build generator -out:build/mani.exe`
- Create a `.json` file with the configuration of the generator. See !(mani_config.json) for all the available options
- The output executable accepts a json as parameter `mani config.json`. You can specify `--show-timings` for benchmarking the performance of the generation. 
- The output of `mani` is a source file `*.(config.odin_ext)` and a LSP file `*(config.lua_ext)` for each package encountered in the directory and it's subdirectories.
- When initializing the lua state, call `mani.export_all` in order to hook all the code generated to your lua state
```odin
import lua "shared:lua"
import luaL "shared:luaL"
import mani "shared:mani"
main :: proc() {
    L := luaL.newstate()
    mani.export_all(L, mani.global_state)
}
```
- Build your source with the `-ignore-unkown-attributes` flag

## Overview



