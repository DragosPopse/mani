package test 

import "core:fmt"
import "shared:lua"
import "shared:luaL"
import "shared:mani"


@(LuaExport = {
    Name = "half_object",
    Mode = { Ref, Copy },
    Fields = {
        value = "val",
    },
    Methods = {
        half_object_print = "print", // I could store a map of ProcExports inside the generator
    },
    Metamethods = {
        //__tostring = half_object_print,
    },
})
HalfObject :: struct {
    value: int, // This could work
    hidden: int,
}

@(LuaExport)
make_object :: proc(v: int) -> HalfObject {
    return {
        value = v,
        hidden = v + 1,
    }
}

@(LuaExport)
mod_object :: proc(o: ^HalfObject, v: int) {
    o.value = v
}


@(LuaExport = {
    Name = "print_object",
})
half_object_print :: proc(using v: HalfObject) {
    fmt.printf("My value is %d, and my hidden is %d\n", value, hidden)
}

main :: proc() {
    using fmt

    L := luaL.newstate()
    luaL.openlibs(L)
    mani.export_all(L, mani.global_state)
    obj := make_object(32)
    
    if luaL.dofile(L, "test/test.lua") != lua.OK {
        fmt.printf("LuaError: %s", lua.tostring(L, -1))
    }
    //half_object_print(obj)
}