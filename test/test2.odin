package test

import "core:c"
import "core:fmt"



@(LuaExport, Name = "AnotherFN")
another_Fn :: proc(my_param1: string, my_param2: c.int) -> c.int {
    return 0
}


@(LuaExport, AllowRef, AllowCopy) // If no LuaFields is specified, make all
TestObject :: struct {
    value: int, // Comment in struct
}


@(LuaExport = {
    Name = "half_object",
    Mode = { Ref, Copy },
    Fields = {
        value = "val",
    },
    Methods = {
        //half_object_print = "print",  
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
make_object :: proc(v: int) -> (r: HalfObject) {
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