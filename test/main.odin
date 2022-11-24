package test 

import "core:fmt"
import "shared:lua"
import "shared:luaL"
import "shared:mani"
import "core:c"


//@field val integer The value of the object
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
    Getters = {

    },
    Setters = {
        
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

generate_vecs :: proc($FullName: cstring, tostring: lua.CFunction, $VecType: typeid, $VecLen: int, $ElemType: typeid, $AllowedVals: string, 
    $Vec2Type: typeid,
    $Vec3Type: typeid,
    $Vec4Type: typeid) {
    expStruct: mani.StructExport
    expStruct.pkg = "test"
    expStruct.odin_name = cast(mani.OdinName)FullName
    expStruct.lua_name = cast(mani.LuaName)FullName
    expStruct.type = VecType
    
    
    copyMeta: mani.MetatableData
    copyMeta.name = FullName
    copyMeta.odin_type = VecType
    copyMeta.index = mani._gen_vector_index(VecType, VecLen, ElemType, AllowedVals, Vec2Type, Vec3Type, Vec4Type)
    copyMeta.newindex = mani._gen_vector_newindex(VecType, VecLen, ElemType, AllowedVals, Vec2Type, Vec3Type, Vec4Type)
    copyMeta.methods = make(map[cstring]lua.CFunction)
    copyMeta.methods["__tostring"] = tostring
    expStruct.full_meta = copyMeta

    mani.add_struct(expStruct)
}

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


main :: proc() {
    using fmt
    
    //types :: [?]typeid{type_of(Vec3), type_of(Vec2)}
    L := luaL.newstate()
    luaL.openlibs(L)
    //generate_vecs("Vec4", _mani_vec4_tostring, Vec4, 4, int, "xyzwrgba", Vec2, Vec3, Vec4)
    //generate_vecs("Vec3", _mani_vec3_tostring, Vec3, 3, int, "xyzrgb", Vec2, Vec3, Vec4)
    //generate_vecs("Vec2", _mani_vec2_tostring, Vec2, 2, int, "xyrg", Vec2, Vec3, Vec4)
    //generate_vecs("Vec4_light", _mani_vec4_tostring, ^Vec4, 4, int, "xyzwrgba", Vec2, Vec3, Vec4)
    //generate_vecs("Vec3_light", _mani_vec3_tostring, ^Vec3, 3, int, "xyzrgb", Vec2, Vec3, Vec4)
    //generate_vecs("Vec2_light", _mani_vec2_tostring, ^Vec2, 2, int, "xyrg", Vec2, Vec3, Vec4)
  
    mani.export_all(L, mani.global_state)
    obj := make_object(20)
    
    v: Vec3 = {1, 2, 3}
    mani.set_global(L, "g_vec", &v)

    if luaL.dofile(L, "test/test.lua") != lua.OK {
        fmt.printf("LuaError: %s\n", lua.tostring(L, -1))
    }

    fmt.printf("Odin: %s\n", vec3_tostring(v))
    
   
}