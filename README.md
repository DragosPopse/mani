# mani
Mani is an odin-to-lua exporter that generates Lua C API bindings for your odin source files. This project is WIP, and doesn't have many features yet. The attributes API is subject to considerable amount of changes

```odin 
package main

import "core:fmt"
import "shared:lua"
import "shared:luaL"
import "shared:mani"

@(lua_export = "my_nice_fn")
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

## Features
- Global function declarations via `@lua_export = "lua_function_name"`. Functions support multiple parameters and return values.
- Parameters and results can be all primitive lua types (ints, floats, booleans). There is no support for userdata and lightuserdata yet. 
- The string support is still WIP due to the fact it requires conversion from `string` to `cstring`. 

## Usage
- Install https://github.com/DragosPopse/odin-lua
- Place the contents of the shared directory in ODIN_ROOT/shared collection
- Build `generator` directory `odin build generator -ignore-unknown-attributes -out:build/mani.exe`
- The output executable accepts a directory as parameter `mani path/to/src`
- The output of `mani` is a `*.generated.odin` file for each package encountered in the directory and it's subdirectories
- When initializing the lua state, call `mani.export_all` in order to hook all the code generated to your lua state
- Build your source with the `-ignore-unkown-attributes` flag

```odin
import lua "shared:lua"
import luaL "shared:luaL"
import mani "shared:mani"
main :: proc() {
    L := luaL.newstate()
    mani.export_all(L, mani.global_state)
}
```

### Details
  - Below is the generated package file produced from the code above 
```odin
import c "core:c"
import runtime "core:runtime"
import fmt "core:fmt"
import lua "shared:lua"
import luaL "shared:luaL"
import luax "shared:luax"
import mani "shared:mani"
test_mani :: proc "c" (L: ^lua.State) -> c.int {
    context = runtime.default_context()

    var: int
    
    luax.get(L, 1, &var)
    result1, result2 := test(var)

    luax.push(L, result1)
    luax.push(L, result2)
    
    return 2
}

@(init)
test_mani_init :: proc() {
    mani.add_function(test_mani, "my_nice_fn")
}
```
