package mani

import lua "shared:lua"
import strings "core:strings"

LuaName :: distinct string
OdinName :: distinct string
ManiName :: distinct string

LuaExport :: struct {
    pkg: string,
    lua_name: LuaName,
    odin_name: OdinName,
}

LuaLibrary :: struct { //for tagging?

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
}

// TODO(Add lua state in here aswell) (then we can have a single init function instead of export_all)
State :: struct {
    procs: map[OdinName]ProcExport, // Key: odin_name
    structs: map[OdinName]StructExport, // Key: odin_name
}

global_state := State {
    procs = make(map[OdinName]ProcExport),
    structs = make(map[OdinName]StructExport),
}


export_all :: proc(L: ^lua.State, using state: State) {
    for key, val in procs {
        lua.pushcfunction(L, val.lua_proc)
        cstr := strings.clone_to_cstring(cast(string)val.lua_name, context.temp_allocator)
        lua.setglobal(L, cstr)
    }
    
}