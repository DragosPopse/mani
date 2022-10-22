package test

@(lua_export = "myfn", f = 2)
another_Fn :: proc(my_param1: string, my_param2: int) -> (res: int, res2: int) {
    return 0, 2
}