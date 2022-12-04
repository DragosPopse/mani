package test 


import "core:fmt"
import "shared:lua"
import "shared:luaL"
import "shared:mani"
import "core:c"
import "core:strings"



@(LuaExport = {
    Name = "half_object", // maybe use this as metatable name
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
    Getters = {

    },
    Setters = {
        
    },
})
HalfObject :: struct {
    value: int, 
    hidden: int,
}


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

@(LuaExport = {
    Name = "vec2f64",
    Type = {Light, Full},
    SwizzleTypes = {Vec3, Vec4},
    Fields = xyrg,
    Metamethods = {
        __tostring = vec2_tostring,
    },
})
Vec2 :: [2]int 

@(LuaExport = {
    Name = "vec3f64",
    Type = {Light, Full},
    Style = {Vector, Color},
    SwizzleTypes = {Vec2, Vec4},
    Fields = xyzrgb,
    Metamethods = {
        __tostring = vec3_tostring,
    },
})
Vec3 :: [3]int

// This works nice
@(LuaExport = {
    Name = "vec4f64",
    Type = {Light, Full},
    Style = {Vector, Color},
    SwizzleTypes = {Vec2, Vec3},
    Fields = xyzwrgba,
    Methods = {
        vec4_tostring = "stringify",
    },
    Metamethods = {
        __tostring = vec4_tostring,
    },
})
Vec4 :: [4]int  


// This seems to not generate correct intellisense
@(LuaExport)
make_vec4 :: proc(x: int, y: int, z: int, w: int) -> Vec4 {
    return {x, y, z, w}
}

@(LuaExport)
vec4_tostring :: proc(v: Vec4) -> string {
    return fmt.tprintf("{{%d, %d, %d, %d}}", v.x, v.y, v.z, v.w)
}

@(LuaExport)
vec3_tostring :: proc(v: Vec3) -> string {
    return fmt.tprintf("{{%d, %d, %d}}", v.x, v.y, v.z)
}

@(LuaExport)
vec2_tostring :: proc(v: Vec2) -> string {
    return fmt.tprintf("{{%d, %d}}", v.x, v.y)
}



// LuaImport should work with tables(maps) and other data types

str1 := "MyName"
str2 := "MySecondName"
mapping := map[proc()]string {
    test_proc = str1,
    test_proc2 = str2,
}

// Option A 
mapping2 := map[rawptr]string {}
test_proc: proc() 
my_impl :: proc() {
    fmt.printf("My string be %s\n", mapping2[&test_proc])
}

test_proc2: proc()
my_impl2 :: proc() {
    fmt.printf("My string be %s\n", mapping2[&test_proc2])
}

// Option B
@(LuaImport = {
    GlobalSymbol = "Update", // This could be optional. If left empty it would just be a wrapper around C api calls
})
update :: proc(dt: f64) -> (int, int) { 
    val1, val2 := _mani_update(dt)
    // do some for processing
    return val1, val2 
}

main :: proc() { 
    test_proc = my_impl
    test_proc2 = my_impl2
    // I need to init here
    mapping2[rawptr(my_impl)] = str1
    mapping2[cast(rawptr)my_impl2] = str2
    test_proc()
    test_proc2()

    L := luaL.newstate()
    luaL.openlibs(L)
  
    mani.init(L, &mani.global_state)
    obj := make_object(20)
    

    v: Vec3 = {1, 2, 3}
    mani.set_global(L, "g_vec", &v)

    if luaL.dofile(L, "test/test.lua") != lua.OK {
        fmt.printf("LuaError: %s\n", lua.tostring(L, -1))
    }

    fmt.printf("Odin: %s\n", vec3_tostring(v))
    
}