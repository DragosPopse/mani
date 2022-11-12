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


@(LuaExport, Name = "half_object", AllowCopy, AllowRef)
@(LuaFields, 
    value = "Value") 
HalfObject :: struct {
    value: f64 `@(LuaExport)`, // This could work
    hidden: int,
}


half_object_print :: proc(using v: HalfObject) {
    fmt.printf("My value is %f, and my hidden is %d\n", value, hidden)
}