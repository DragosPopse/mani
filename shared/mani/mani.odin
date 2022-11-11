package mani

import lua "shared:lua"
import luaL "shared:luaL"
import strings "core:strings"
import "core:c"

import "core:runtime"

LuaName :: distinct string
OdinName :: distinct string
ManiName :: distinct string

MetatableData :: struct {
    name: cstring,
    odin_type: typeid,
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

// Note(Dragos): Test performance
FieldSetProc :: #type proc(L: ^lua.State, s: rawptr, field: string) 
FieldGetProc :: #type proc(L: ^lua.State, s: rawptr, field: string) 


StructFieldExport :: struct {
    lua_name: LuaName,
    odin_name: OdinName,
    type: typeid,
}

StructExport :: struct {
    using base: LuaExport,
    type: typeid,
    fields: map[LuaName]StructFieldExport, // This should be LuaName
    ref_meta: Maybe(MetatableData),
    copy_meta: Maybe(MetatableData),
}

// TODO(Add lua state in here aswell) (then we can have a single init function instead of export_all)
State :: struct {
    procs: map[OdinName]ProcExport, // Key: odin_name
    structs: map[typeid]StructExport, // Key: type 
    udata_metatable_mapping: map[typeid]cstring, // Key: odin type; Value: lua name
}

global_state := State {
    procs = make(map[OdinName]ProcExport),
    structs = make(map[typeid]StructExport),
    udata_metatable_mapping = make(map[typeid]cstring),
}

default_context: proc "contextless" () -> runtime.Context = nil

add_function :: proc(v: ProcExport) {
    using global_state 
    procs[v.odin_name] = v
}

add_struct :: proc(s: StructExport) {
    using global_state 
    structs[s.type] = s
    if ref, ok := s.ref_meta.?; ok {
        udata_metatable_mapping[ref.odin_type] = ref.name
    }

    if copy, ok := s.copy_meta.?; ok {
        udata_metatable_mapping[copy.odin_type] = copy.name
    }
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