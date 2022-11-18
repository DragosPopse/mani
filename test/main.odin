package test 

import "core:fmt"
import "shared:lua"
import "shared:luaL"
import "shared:mani"


@(LuaExport = {
    //Name = "half_object", // maybe use this as metatable name
    Type = { Full, Light },
    Fields = {
        value = "val",
    },
    Methods = {
        // this could also be { print = half_object_print }
        // would allow reuse of functions
        // { "print" = half_object_print } would require some changes in parser
        half_object_print = "print",  
        mod_object = "mod",
    },
    Metamethods = {
        __tostring = half_object_tostring,
    },
})
HalfObject :: struct {
    value: int, 
    hidden: int,
}

//@param v integer The integer used to make the object
//@return HalfObject result The object that was made
@(LuaExport)
make_object :: proc(v: int) -> (result: HalfObject) {
    return {
        value = v,
        hidden = v + 1,
    }
}

@(LuaExport)
mod_object :: proc(o: ^HalfObject, v: int) {
    o.value = v
}

@(LuaExport)
half_object_tostring :: proc(using v: HalfObject) -> string {
    return fmt.tprintf("HalfObject {{%d, %d}}", value, hidden)
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
    obj := make_object(20)
    
    mani.set_global(L, "global_obj", &obj)


    if luaL.dofile(L, "test/test.lua") != lua.OK {
        fmt.printf("LuaError: %s\n", lua.tostring(L, -1))
    }

    half_object_print(obj)
}