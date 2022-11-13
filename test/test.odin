// Will this work??
package test


//@param my_param1 string 
//@param my_param2 integer i can even rename them in lua
//@return MyResult1 integer
//@return MyResult2 integer
@(lua_export = "inlua_name_myfn")
my_function :: proc(my_param1: string, my_param2: int) -> (res1: int, res2: int) {
    return 0, 2
}


@(LuaExport = "MyEmptyFn")
@(Test = {
    name = "this",
    val1 = 32,
    val2 = val1,
})
empty_fn :: proc "contextless" () { 
    // This is an inline comment
}

@(ShouldIgnore)
should_ignore :: proc() {
    
}