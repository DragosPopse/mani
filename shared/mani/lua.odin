package mani

import lua "shared:lua"
import luaL "shared:luaL"
import intr "core:intrinsics"
import refl "core:reflect"
import rt "core:runtime"
import "core:fmt"
import "core:strings"
import "core:c"
import "core:mem"

assert_contextless :: proc "contextless" (condition: bool, message := "", loc := #caller_location) {
    if !condition {
        @(cold)
        internal :: proc "contextless"(message: string, loc: rt.Source_Code_Location) {
            rt.print_caller_location(loc)
            rt.print_string(" ")
            rt.print_string("runtime assertion")
            if len(message) > 0 {
                rt.print_string(": ")
                rt.print_string(message)
            }
            rt.print_byte('\n')
        }
        internal(message, loc)
    }
}

push_value :: proc "contextless"(L: ^lua.State, val: $T) {
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
        assert_contextless(found, "Metatable not found for type. Did you mark it with @(LuaExport)?")
        udata := transmute(^T)lua.newuserdata(L, size_of(T))
        udata^ = val
        luaL.getmetatable(L, metatableStr)
        lua.setmetatable(L, -2)
    } else {
        #assert(false, "mani.push_value: Type not supported")
    }
}

to_value :: proc "contextless"(L: ^lua.State, #any_int stack_pos: int, val: ^$T) {
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
        str := luaL.checkstring(L, cast(i32)stack_pos)
        raw := transmute(mem.Raw_String)str
        val^ = cstring(raw.data)
    } else when Base == string {
        val^ = luaL.checkstring(L, cast(i32)stack_pos)
    } else {
        fmeta, hasFulldata := global_state.udata_metatable_mapping[Base]
        lmeta, hasLightdata := global_state.udata_metatable_mapping[Ptr]
        assert_contextless(hasFulldata || hasLightdata, "Metatable not found for type")

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

