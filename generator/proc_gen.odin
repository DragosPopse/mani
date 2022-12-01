package mani_generator

import "core:fmt"
import "core:strings"

write_proc_meta :: proc(config: ^GeneratorConfig, exports: FileExports, fn: ProcedureExport, override_lua_name := "", start_param := 0) {
    using strings, fmt
    sb := &(&config.files[exports.symbols_package]).lua_builder

    for comment in fn.lua_docs {
        fmt.sbprintf(sb, "---%s\n", comment)
    }
    exportAttribs := fn.attribs[LUAEXPORT_STR].(Attributes) or_else DEFAULT_PROC_ATTRIBUTES
    luaName := exportAttribs["Name"].(String) if "Name" in exportAttribs else fn.name
    if override_lua_name != "" {
        luaName = override_lua_name
    }
    for param, i in fn.params[start_param:] {
        paramType := param.type[1:] if is_pointer_type(param.type) else param.type
        luaType := "any" // default unknown type
        if type, found := config.lua_types[paramType]; found {
            luaType = type 
        } else {
            #partial switch type in exports.symbols[paramType] {
                case ArrayExport: {
                    // Note(Dragos): Not the best. Will need some refactoring
                    luaType = type.attribs["LuaExport"].(Attributes)["Name"].(String) or_else type.name
     
                }

                case StructExport: {
                    luaType = type.attribs["LuaExport"].(Attributes)["Name"].(String) or_else type.name
                }
            }
        }
        fmt.sbprintf(sb, "---@param %s %s\n", param.name, luaType)
    }

    for result, i in fn.results {
        resultType := result.type[1:] if is_pointer_type(result.type) else result.type
        luaType := "any" // default unknown type
        if type, found := config.lua_types[resultType]; found {
            luaType = type 
        } else {
            #partial switch type in exports.symbols[resultType] {
                case ArrayExport: {
                    // Note(Dragos): Not the best. Will need some refactoring
                    luaType = type.attribs["LuaExport"].(Attributes)["Name"].(String) or_else type.name
     
                }

                case StructExport: {
                    luaType = type.attribs["LuaExport"].(Attributes)["Name"].(String) or_else type.name
                }
            }
        }
        if strings.has_prefix(result.name, "mani_") {
            fmt.sbprintf(sb, "---@return %s\n", luaType)
        } else {
            fmt.sbprintf(sb, "---@return %s %s\n", luaType, result.name)
        }
        
    }

    fmt.sbprintf(sb, "function %s(", luaName)
    for param, i in fn.params {
        write_string(sb, param.name)
        if i != len(fn.params) - 1 do write_string(sb, ", ")

    }

    write_string(sb, ") end\n\n")
}

generate_proc_lua_wrapper :: proc(config: ^GeneratorConfig, exports: FileExports, fn: ProcedureExport, filename: string) {
    using strings
    fn_name := strings.concatenate({"_mani_", fn.name}, context.temp_allocator)
    
    sb := &(&config.files[exports.symbols_package]).builder

    exportAttribs := fn.attribs[LUAEXPORT_STR].(Attributes) or_else DEFAULT_PROC_ATTRIBUTES
    luaName := exportAttribs["Name"].(String) if "Name" in exportAttribs else fn.name

    write_string(sb, fn_name)
    write_string(sb, " :: proc \"c\" (L: ^lua.State) -> c.int {\n    ")
    if fn.calling_convention == "odin" {
        write_string(sb, "context = mani.default_context()\n\n    ")
    }
    // Declare parameters
    for param in fn.params {
        write_string(sb, param.name)
        write_string(sb, ": ")
        write_string(sb, param.type)
        write_string(sb, "\n    ")
    }

    write_string(sb, "\n    ")

    //Get parameters from lua
    if fn.params != nil && len(fn.params) != 0 {
        for param, i in fn.params {
            write_string(sb, "mani.to_value(L, ") // Note(Dragos): This needs to be replaced
            write_int(sb, i + 1)
            write_string(sb, ", &")
            write_string(sb, param.name)
            write_string(sb, ")\n    ")
        }
    }
    

    // Declare results
    if fn.results != nil && len(fn.results) != 0 {
        for result, i in fn.results {
     
            write_string(sb, result.name)
            
            if i < len(fn.results) - 1 {
                write_string(sb, ", ")
            }
        }
        write_string(sb, " := ")
    }
    write_string(sb, fn.name)
    write_string(sb, "(")
    // Pass parameters to odin function
    for param, i in fn.params {
        write_string(sb, param.name)
        if i < len(fn.params) - 1 {
            write_string(sb, ", ")
        }
    }
    write_string(sb, ")\n\n    ")

    for result, i in fn.results {
        write_string(sb, "mani.push_value(L, ")
        write_string(sb, result.name)
        write_string(sb, ")\n    ")
    }
    write_string(sb, "\n    ")

    write_string(sb, "return ")
    write_int(sb, len(fn.results) if fn.results != nil else 0)
    write_string(sb, "\n")
    write_string(sb, "}\n")

    // Generate @init function to bind to mani

    write_string(sb, "\n")
    write_string(sb, "@(init)\n")
    write_string(sb, fn_name)
    write_string(sb, "_init :: proc() {\n    ")
    write_string(sb, "fn: mani.ProcExport\n    ")

    write_string(sb, "fn.pkg = ")
    write_rune(sb, '"')
    write_string(sb, exports.symbols_package)
    write_rune(sb, '"')
    write_string(sb, "\n    ")

    write_string(sb, "fn.odin_name = ")
    write_rune(sb, '"')
    write_string(sb, fn.name)
    write_rune(sb, '"')
    write_string(sb, "\n    ")

    write_string(sb, "fn.lua_name = ")
    write_rune(sb, '"')
    write_string(sb, luaName)
    write_rune(sb, '"')
    write_string(sb, "\n    ")
    
    write_string(sb, "fn.mani_name = ")
    write_rune(sb, '"')
    write_string(sb, fn_name)
    write_rune(sb, '"')
    write_string(sb, "\n    ")

    write_string(sb, "fn.lua_proc = ")
    write_string(sb, fn_name)
    write_string(sb, "\n    ")

    write_string(sb, "mani.add_function(fn)\n")

    write_string(sb, "}\n\n")
    
    
}