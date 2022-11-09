package mani

import lua "shared:lua"
import luaL "shared:luaL"
import strings "core:strings"

import "core:runtime"

LuaName :: distinct string
OdinName :: distinct string
ManiName :: distinct string

MetatableData :: struct {
    name: cstring,
    index: lua.CFunction,
    newindex: lua.CFunction,
}

LuaExport :: struct {
    pkg: string,
    lua_name: LuaName,
    odin_name: OdinName,
}


ProcExport :: struct {
    using base: LuaExport,
    mani_name: ManiName,
    lua_proc: lua.CFunction,
}

StructFieldExport :: struct {
    lua_name: LuaName,
    odin_name: OdinName,
}

StructExport :: struct {
    using base: LuaExport,
    fields: map[OdinName]StructFieldExport, // Key: odin_name
    ref_meta: Maybe(MetatableData),
    copy_meta: Maybe(MetatableData),
}

// TODO(Add lua state in here aswell) (then we can have a single init function instead of export_all)
State :: struct {
    procs: map[OdinName]ProcExport, // Key: odin_name
    structs: map[OdinName]StructExport, // Key: odin_name
    udata_metatable_mapping: map[typeid]cstring, // Key: odin type; Value: lua name
}

global_state := State {
    procs = make(map[OdinName]ProcExport),
    structs = make(map[OdinName]StructExport),
    udata_metatable_mapping = make(map[typeid]cstring),
}

default_context: proc "contextless" () -> runtime.Context = nil

add_function :: proc(v: ProcExport) {
    using global_state 
    procs[v.odin_name] = v
}


export_all :: proc(L: ^lua.State, using state: State) {
    if default_context == nil {
        default_context = runtime.default_context 
    } 
    for key, val in structs {
        using val 
        if ref, ok := ref_meta.?; ok {
            assert(ref.index != nil && ref.newindex != nil)
            luaL.newmetatable(L, ref.name)
            lua.pushcfunction(L, ref.index)
            lua.setfield(L, -2, "__index")
            lua.pushcfunction(L, ref.newindex)
            lua.setfield(L, -2, "__newindex")
            lua.pop(L, 1)
        }
    }
    for key, val in procs {
        lua.pushcfunction(L, val.lua_proc)
        cstr := strings.clone_to_cstring(cast(string)val.lua_name, context.temp_allocator)
        lua.setglobal(L, cstr)
    }
    
}