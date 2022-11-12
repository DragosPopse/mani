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
        lua.pushnumber(L, cast(Number)val)
    } else when intr.type_is_boolean(T) {
        lua.pushboolean(L, cast(c.bool)val)
    } else when T == cstring {
        lua.pushcstring(L, val)
    } else when T == string {
        lua.pushstring(L, val)
    } else when intr.type_is_struct(T) {
        metatableStr, found := global_state.udata_metatable_mapping[T]
        assert(found, "Struct metatable was not found. Did you mark it with @(LuaExport)?")
        udata := cast(^T)lua.newuserdata(L, size_of(T))
     
        luaL.getmetatable(L, metatableStr)
        lua.setmetatable(L, -2)
    } else {
        #assert(false, "mani.push_value: Type not supported")
    }
}

to_value :: proc(L: ^lua.State, #any_int stack_pos: int, val: ^$T) {
    Base :: type_of(val^)
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
        meta, ok := global_state.udata_metatable_mapping[type_of(refl.typeid_base(T))] // Is this correct?
        
        assert(ok, "Metatable not found for type")
        data := cast(^T)luaL.checkudata(L, cast(i32)stack_pos, meta) // Note(Dragos) This must be wrong 
        val^ = data^
    }
}