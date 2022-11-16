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
    #assert(!intr.type_is_pointer(T), "Pointers are not supported in push_value")
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
    } else when intr.type_is_struct(T) {
        metatableStr, found := global_state.udata_metatable_mapping[T]
        assert(found, "Struct metatable was not found. Did you mark it with @(LuaExport)?")
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
        val^ = cast(Base)lua.tointeger(L, cast(i32)stack_pos)
    } else when intr.type_is_float(Base) {
        val^ = cast(Base)lua.tonumber(L, cast(i32)stack_pos) 
    } else when intr.type_is_boolean(Base) {
        val^ = cast(Base)lua.toboolean(L, cast(i32)stack_pos) 
    } else when Base == cstring {
        val^ = strings.unsafe_string_to_cstring(lua.tostring(L, cast(i32)stack_pos)) // we know its a cstring
    } else when Base == string {
        val^ = lua.tostring(L, cast(i32)stack_pos)
    } else {
        when intr.type_is_pointer(type_of(val^)) {
            cmeta, canCopy := global_state.udata_metatable_mapping[Base]
            rmeta, canRef := global_state.udata_metatable_mapping[Ptr]
            assert(canCopy || canRef, "Metatable not found for type")

            rawdata: rawptr
       
            cdata := cast(Ptr)luaL.testudata(L, cast(i32)stack_pos, cmeta) if canCopy else nil
            rdata := cast(^Ptr)luaL.testudata(L, cast(i32)stack_pos, rmeta) if canRef else nil
            if cdata != nil {
                val^ = cdata
            } else {
                val^ = rdata^
            }
        } else {
            cmeta, canCopy := global_state.udata_metatable_mapping[Base]
            rmeta, canRef := global_state.udata_metatable_mapping[Ptr]
            assert(canCopy || canRef, "Metatable not found for type")

            rawdata: rawptr
       
            cdata := cast(Ptr)luaL.testudata(L, cast(i32)stack_pos, cmeta) if canCopy else nil
            rdata := cast(^Ptr)luaL.testudata(L, cast(i32)stack_pos, rmeta) if canRef else nil
            if cdata != nil {
                val^ = cdata^
            } else {
                val^ = rdata^^
            }
        }
        
    
    }
}