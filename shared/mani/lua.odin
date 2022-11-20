package mani

import lua "shared:lua"
import luaL "shared:luaL"
import intr "core:intrinsics"
import refl "core:reflect"
import rt "core:runtime"
import "core:fmt"
import "core:strings"
import "core:c"

push_value :: proc(L: ^lua.State, val: $T) {
    //#assert(!intr.type_is_pointer(T), "Pointers are not supported in push_value")
    when intr.type_is_integer(T) {
        lua.pushinteger(L, cast(lua.Integer)val) // Note(Dragos): Should this be casted implicitly? I think not
    } else when intr.type_is_float(T) {
        lua.pushnumber(L, cast(lua.Number)val)
    } else when intr.type_is_boolean(T) {
        lua.pushboolean(L, cast(c.bool)val)
    } else when T == cstring {
        lua.pushcstring(L, val)
    } else when T == string {
        lua.pushstring(L, val)
    } else when intr.type_is_proc(T) {
        lua.pushcfunction(L, val)
    } else when intr.type_is_struct(T) || intr.type_is_pointer(T) || intr.type_is_array(T) {
        metatableStr, found := global_state.udata_metatable_mapping[T]
        assert(found, fmt.tprintf("Metatable for %T was not found. Did you mark it with @(LuaExport)?", val))
        udata := transmute(^T)lua.newuserdata(L, size_of(T))
        udata^ = val
        luaL.getmetatable(L, metatableStr)
        lua.setmetatable(L, -2)
    } else {
        #assert(false, "mani.push_value: Type not supported")
    }
}

to_value :: proc(L: ^lua.State, #any_int stack_pos: int, val: ^$T) {
    when intr.type_is_pointer(type_of(val^)) {
        Base :: type_of(val^^)
        Ptr :: type_of(val^)
    } else {
        Base :: type_of(val^)
        Ptr :: type_of(val)
    }
    #assert(!intr.type_is_pointer(Base), "Pointer to pointer not allowed in to_value")

    when intr.type_is_integer(Base) {
        val^ = cast(Base)luaL.checkinteger(L, cast(i32)stack_pos)
    } else when intr.type_is_float(Base) {
        val^ = cast(Base)luaL.checknumber(L, cast(i32)stack_pos) 
    } else when intr.type_is_boolean(Base) {
        val^ = cast(Base)luaL.checkboolean(L, cast(i32)stack_pos) 
    } else when Base == cstring {
        val^ = strings.unsafe_string_to_cstring(lua.checkstring(L, cast(i32)stack_pos)) // we know its a cstring
    } else when Base == string {
        val^ = luaL.checkstring(L, cast(i32)stack_pos)
    } else {
        fmeta, hasFulldata := global_state.udata_metatable_mapping[Base]
        lmeta, hasLightdata := global_state.udata_metatable_mapping[Ptr]
        assert(hasFulldata || hasLightdata, "Metatable not found for type")

        rawdata: rawptr
    
        fdata := cast(Ptr)luaL.testudata(L, cast(i32)stack_pos, fmeta) if hasFulldata else nil
        ldata := cast(^Ptr)luaL.testudata(L, cast(i32)stack_pos, lmeta) if hasLightdata else nil
        when intr.type_is_pointer(type_of(val^)) { 
            if fdata != nil {
                val^ = fdata
            } else {
                val^ = ldata^
            }
        } else {
            if fdata != nil {
                val^ = fdata^
            } else {
                val^ = ldata^^
            }
        }
    }
}


set_global :: proc(L: ^lua.State, name: string, val: $T) {
    push_value(L, val)
    cname := strings.clone_to_cstring(name, context.temp_allocator)
    lua.setglobal(L, cname)
}

// ElemType can be type_of(vec[0])
_gen_vector_index :: proc($VecType: typeid, $VecLen: int, $ElemType: typeid, $AllowedVals: string, $Vec2Type: typeid, $Vec3Type: typeid, $Vec4Type: typeid) -> lua.CFunction {
    return proc "c" (L: ^lua.State) -> c.int {

        context = default_context()
        udata: VecType
        to_value(L, 1, &udata)
        // Note(Dragos): It should also accept indices
        key := lua.tostring(L, 2)
        
        assert(len(key) <= 4, "Vectors can only be swizzled up to 4 elements")

        result: Vec4Type
        for r, i in key {
            if idx := strings.index_rune(AllowedVals, r); idx != -1 {
                arrIdx := idx % VecLen 
                result[i] = udata[arrIdx]
            }
        }

        switch len(key) {
            case 1: {
                push_value(L, result.x)
            }

            case 2: {
                push_value(L, result.xy)
            }

            case 3: {
                push_value(L, result.xyz)
            }

            case 4: {
                push_value(L, result)
            }

            case: {
                lua.pushnil(L)
            }
        }

        return 1
    }
}

_gen_vector_newindex :: proc($ArrayType: typeid, $VecLen: int, $ElemType: typeid, $AllowedVals: string, $Vec2Type: typeid, $Vec3Type: typeid, $Vec4Type: typeid) -> lua.CFunction {
    return proc "c" (L: ^lua.State) -> c.int {
        context = default_context()
        udata: ArrayType 
        to_value(L, 1, &udata)
        // Note(Dragos): It should also accept indices
        key := lua.tostring(L, 2)
        assert(len(key) <= VecLen, "Cannot assign more indices than the vector takes")
        result: Vec4Type

        switch len(key) {
            case 1: {
                val: ElemType 
                to_value(L, 3, &val)
                
                if idx := strings.index_byte(AllowedVals, key[0]); idx != -1 {
                    arrIdx := idx % VecLen
                    udata[arrIdx] = val
                }
            }

            case 2: {
                val: Vec2Type
                for r, i in key {
                    to_value(L, 3, &val)
                    if idx := strings.index_rune(AllowedVals, r); idx != -1 {
                        arrIdx := idx % VecLen
                        udata[arrIdx] = val[i]
                    }
                }
            }

            case 3: {
                val: Vec3Type
                for r, i in key {   
                    to_value(L, 3, &val)
                    if idx := strings.index_rune(AllowedVals, r); idx != -1 {
                        arrIdx := idx % VecLen
                        udata[arrIdx] = val[i]
                    }
                }
            }

            case 4: {
                val: Vec4Type
                for r, i in key {                   
                    to_value(L, 3, &val)
                    if idx := strings.index_rune(AllowedVals, r); idx != -1 {
                        arrIdx := idx % VecLen
                        udata[arrIdx] = val[i]
                    }
                }
            }
        }


        return 0
    }
}