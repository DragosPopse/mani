package mani

import lua "shared:lua"
import strings "core:strings"

State :: struct {
    exported_functions: [dynamic]lua.CFunction,
    exported_names: [dynamic]string,
}

global_state := State {
    exported_functions = make([dynamic]lua.CFunction),
    exported_names = make([dynamic]string),
}

add_function :: proc(fn: lua.CFunction, name: string) {
    append(&global_state.exported_functions, fn)
    append(&global_state.exported_names, name)
}

// Note(Dragos) I need more than the exported functions in order to make proper wrappers
export_all :: proc(L: ^lua.State, using state: State) {
    for fn, i in exported_functions {
        lua.pushcfunction(L, fn)
        cstr := strings.clone_to_cstring(exported_names[i], context.temp_allocator)
        lua.setglobal(L, cstr)
    }
}