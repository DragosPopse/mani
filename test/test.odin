package test


@(lua_export = "inlua_name_myfn")
my_function :: proc(my_param1: string, my_param2: int) -> (res1: int, res2: int) {
    return 0, 2
}