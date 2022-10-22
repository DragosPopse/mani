package test


@(lua_export = "myfn2", f = 2)
my_function :: proc(my_param1: string, my_param2: int) -> (res: int, res2: int) {
    return 0, 2
}