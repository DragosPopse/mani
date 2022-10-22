package test

import c "core:c"
import runtime "core:runtime"
import fmt "core:fmt"
import lua "shared:lua"
import luaL "shared:luaL"
import luax "shared:luax"
import mani "shared:mani"
my_function_mani :: proc "c" (L: ^lua.State) -> c.int {
    context = runtime.default_context()

    my_param1: string
    my_param2: int
    
    luax.get(L, 1, &my_param1)
    luax.get(L, 2, &my_param2)
    res, res2 := my_function(my_param1, my_param2)

    luax.push(L, res)
    luax.push(L, res2)
    
    return 2
}

@(init)
my_function_mani_init :: proc() {
    fmt.printf("Init happening\n")
    mani.add_function(my_function_mani, "myfn2")
}

another_Fn_mani :: proc "c" (L: ^lua.State) -> c.int {
    context = runtime.default_context()

    my_param1: string
    my_param2: int
    
    luax.get(L, 1, &my_param1)
    luax.get(L, 2, &my_param2)
    res, res2 := another_Fn(my_param1, my_param2)

    luax.push(L, res)
    luax.push(L, res2)
    
    return 2
}

@(init)
another_Fn_mani_init :: proc() {
    fmt.printf("Init happening\n")
    mani.add_function(another_Fn_mani, "myfn")
}

