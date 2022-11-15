package test 

import "core:fmt"
import "shared:lua"
import "shared:luaL"
import "shared:mani"

main :: proc() {
    using fmt

    L := luaL.newstate()
    luaL.openlibs(L)
    mani.export_all(L, mani.global_state)

    if luaL.dofile(L, "test/test.lua") != lua.OK {
        fmt.printf("LuaError: %s", lua.tostring(L, -1))
    }
}