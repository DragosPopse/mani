package test

import "core:c"

@(LuaExport, Name = "AnotherFN")
another_Fn :: proc(my_param1: string, my_param2: c.int) -> c.int {
    return 0
}