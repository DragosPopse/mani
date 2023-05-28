package mani_generator

import "core:fmt"
import "core:strings"

write_lua_struct_init :: proc(sb: ^strings.Builder, exports: FileExports, s: StructExport) {
    using strings, fmt

    exportAttribs := s.attribs[LUAEXPORT_STR].(Attributes) or_else DEFAULT_STRUCT_ATTRIBUTES
    udataType := exportAttribs["Type"].(Attributes)  
    allowLight := "Light" in udataType
    allowFull := "Full" in udataType
    
    luaName := exportAttribs["Name"].(String) or_else s.name


    write_string(sb, "@(init)\n")
    write_string(sb, "_mani_init_")
    write_string(sb, s.name)
    write_string(sb, " :: proc() {\n    ")

    write_string(sb, "expStruct: mani.StructExport")
    write_string(sb, "\n    ")
    write_string(sb, "expStruct.pkg = ")
    write_rune(sb, '"')
    write_string(sb, exports.symbols_package)
    write_rune(sb, '"')
    write_string(sb, "\n    ")

    write_string(sb, "expStruct.odin_name = ")
    write_rune(sb, '"')
    write_string(sb, s.name)
    write_rune(sb, '"')
    write_string(sb, "\n    ")

    write_string(sb, "expStruct.lua_name = ")
    write_rune(sb, '"')
    write_string(sb, luaName)
    write_rune(sb, '"')
    write_string(sb, "\n    ")

    write_string(sb, "expStruct.type = ")
    write_string(sb, s.name)
    write_string(sb, "\n    ")
    
    if methodsAttrib, found := exportAttribs["Methods"]; found {
        write_string(sb, "expStruct.methods = make(map[mani.LuaName]lua.CFunction)")
        write_string(sb, "\n    ")
        methods := methodsAttrib.(Attributes) 
        for odinName, attribVal in methods {
            luaName: string
            if name, ok := attribVal.(String); ok {
                luaName = name
            } else {
                luaName = odinName
            }
            fullName := strings.concatenate({"_mani_", odinName}, context.temp_allocator)
            write_string(sb, "expStruct.methods[")
            write_rune(sb, '"')
            write_string(sb, luaName)
            write_rune(sb, '"')
            write_string(sb, "] = ")
            write_string(sb, fullName)
            write_string(sb, "\n    ")
        }
        
    }

    if allowLight {
        write_string(sb, "\n    ")
        write_string(sb, "refMeta: mani.MetatableData\n    ")
        write_string(sb, "refMeta.name = ")
        write_rune(sb, '"')
        write_string(sb, s.name)
        write_string(sb, "_ref")
        write_rune(sb, '"')
        write_string(sb, "\n    ")

        write_string(sb, "refMeta.odin_type = ")
        write_rune(sb, '^')
        write_string(sb, s.name)
        write_string(sb, "\n    ")

        write_string(sb, "refMeta.index = ")
        write_string(sb, "_mani_index_")
        write_string(sb, s.name)
        write_string(sb, "_ref")
        write_string(sb, "\n    ")

        write_string(sb, "refMeta.newindex = ")
        write_string(sb, "_mani_newindex_")
        write_string(sb, s.name)
        write_string(sb, "_ref")
        write_string(sb, "\n    ")

        if metaAttrib, found := exportAttribs["Metamethods"]; found {
            write_string(sb, "refMeta.methods = make(map[cstring]lua.CFunction)")
            write_string(sb, "\n    ")
            methods := metaAttrib.(Attributes)
            for name, val in methods {
                odinProc := val.(Identifier)
                fmt.sbprintf(sb, "refMeta.methods[\"%s\"] = _mani_%s", name, cast(String)odinProc)
                write_string(sb, "\n    ")
            }
        }


        write_string(sb, "expStruct.light_meta = refMeta")
        write_string(sb, "\n    ")
    }

    if allowFull {
        write_string(sb, "\n    ")
        write_string(sb, "copyMeta: mani.MetatableData\n    ")
        write_string(sb, "copyMeta.name = ")
        write_rune(sb, '"')
        write_string(sb, s.name)
        write_rune(sb, '"')
        write_string(sb, "\n    ")

        write_string(sb, "copyMeta.odin_type = ")
        write_string(sb, s.name)
        write_string(sb, "\n    ")

        write_string(sb, "copyMeta.index = ")
        write_string(sb, "_mani_index_")
        write_string(sb, s.name)
        write_string(sb, "\n    ")

        write_string(sb, "copyMeta.newindex = ")
        write_string(sb, "_mani_newindex_")
        write_string(sb, s.name)
        write_string(sb, "\n    ")

        if metaAttrib, found := exportAttribs["Metamethods"]; found {
            write_string(sb, "copyMeta.methods = make(map[cstring]lua.CFunction)")
            write_string(sb, "\n    ")
            methods := metaAttrib.(Attributes)
            for name, val in methods {
                odinProc := val.(Identifier)
                fmt.sbprintf(sb, "copyMeta.methods[\"%s\"] = _mani_%s", name, cast(String)odinProc)
                write_string(sb, "\n    ")
            }
        }

        write_string(sb, "expStruct.full_meta = copyMeta")
        write_string(sb, "\n    ")
        write_string(sb, "\n    ")

    }

   
    
    write_string(sb, "mani.add_struct(expStruct)")
    write_string(sb, "\n}\n\n")
}

write_lua_newstruct :: proc(sb: ^strings.Builder, exports: FileExports, s: StructExport) {
    
}

write_lua_index :: proc(sb: ^strings.Builder, exports: FileExports, s: StructExport) {
    using strings
    exportAttribs := s.attribs[LUAEXPORT_STR].(Attributes) or_else DEFAULT_STRUCT_ATTRIBUTES
    luaFields := exportAttribs["Fields"].(Attributes) if "Fields" in exportAttribs else nil
    udataType := exportAttribs["Type"].(Attributes)  
    allowLight := "Light" in udataType
    allowFull := "Full" in udataType
    hasMethods := "Methods" in exportAttribs


    if allowFull {
        if hasMethods {
            fmt.sbprintf(sb, 
                `
_mani_index_{0:s} :: proc "c" (L: ^lua.State) -> c.int {{
    context = mani.default_context()
    udata := transmute(^{1:s})luaL.checkudata(L, 1, "{0:s}")
    key := lua.tostring(L, 2)
    if method, found := _mani_methods_{0:s}[key]; found {{
        mani.push_value(L, method)
        return 1
    }}
    switch key {{
        case: {{
            lua.pushnil(L)
            return 1
        }}
                `, s.name, s.name)
        } else {
            fmt.sbprintf(sb, 
                `
_mani_index_{0:s} :: proc "c" (L: ^lua.State) -> c.int {{
    context = mani.default_context()
    udata := transmute(^{1:s})luaL.checkudata(L, 1, "{0:s}")
    key := lua.tostring(L, 2)
    switch key {{
        case: {{
            lua.pushnil(L)
            return 1
        }}
                `, s.name, s.name)
        }

        if luaFields != nil {
            for k, field in s.fields {
                shouldExport := false
                name: string
                if luaField, ok := luaFields[field.name]; ok {
                    shouldExport = true
                    if luaName, ok := luaField.(String); ok {
                        name = luaName
                    } else {
                        name = field.name
                    }  
                } else {
                    shouldExport = false
                }
                
    
                if shouldExport {
                    fmt.sbprintf(sb, 
`        
        case "{0:s}": {{
            mani.push_value(L, udata.{1:s})
            return 1
        }}
`,    name, field.name)
                }
            }
        }
        
        fmt.sbprintf(sb, 
`
    }}
    return 1
}}

`       )
    }

    if allowLight {
        if hasMethods {
            fmt.sbprintf(sb, 
                `
_mani_index_{0:s}_ref :: proc "c" (L: ^lua.State) -> c.int {{
    context = mani.default_context()
    udata := transmute(^{1:s})luaL.checkudata(L, 1, "{0:s}")
    key := lua.tostring(L, 2)
    if method, found := _mani_methods_{0:s}[key]; found {{
        mani.push_value(L, method)
        return 1
    }}
    switch key {{
        case: {{
            lua.pushnil(L)
            return 1
        }}
                `, s.name, s.name)
        } else {
            fmt.sbprintf(sb, 
                `
_mani_index_{0:s}_ref :: proc "c" (L: ^lua.State) -> c.int {{
    context = mani.default_context()
    udata := transmute(^{1:s})luaL.checkudata(L, 1, "{0:s}")
    key := lua.tostring(L, 2)
    switch key {{
        case: {{
            lua.pushnil(L)
            return 1
        }}
                `, s.name, s.name)
        }

        if luaFields != nil {
            for k, field in s.fields {
                shouldExport := false
                name: string
                if luaField, ok := luaFields[field.name]; ok {
                    shouldExport = true
                    if luaName, ok := luaField.(String); ok {
                        name = luaName
                    } else {
                        name = field.name
                    }  
                } else {
                    shouldExport = false
                }
                
    
                if shouldExport {
                    fmt.sbprintf(sb, 
`        
        case "{0:s}": {{
            mani.push_value(L, udata^.{1:s})
            return 1
        }}
`,    name, field.name)
                }
            }
        }

        fmt.sbprintf(sb, 
`
    }}
    return 1
}}

`       )
    }
    
}

write_lua_newindex :: proc(sb: ^strings.Builder, exports: FileExports, s: StructExport) {
    using strings
    exportAttribs := s.attribs[LUAEXPORT_STR].(Attributes) or_else DEFAULT_STRUCT_ATTRIBUTES
    luaFields := exportAttribs["Fields"].(Attributes) if "Fields" in exportAttribs else nil
    udataType := exportAttribs["Type"].(Attributes)  
    allowLight := "Light" in udataType
    allowFull := "Full" in udataType


    if allowFull {
        fmt.sbprintf(sb, 
`
_mani_newindex_{0:s} :: proc "c" (L: ^lua.State) -> c.int {{
    context = mani.default_context()
    udata := transmute(^{1:s})luaL.checkudata(L, 1, "{0:s}")
    key := lua.tostring(L, 2)
    switch key {{
        case: {{
            // Throw an error here
            return 0
        }}
`       , s.name, s.name)
        if luaFields != nil {
            for k, field in s.fields {
                shouldExport := false
                name: string
                if luaField, ok := luaFields[field.name]; ok {
                    shouldExport = true
                    if luaName, ok := luaField.(String); ok {
                        name = luaName
                    } else {
                        name = field.name
                    }  
                } else {
                    shouldExport = false
                }
                

                if shouldExport {
                    fmt.sbprintf(sb, 
`        
        case "{0:s}": {{
            mani.to_value(L, 3, &udata.{1:s})
            return 1
        }}
`,    name, field.name)
                }
            }
        }

        fmt.sbprintf(sb, 
`
    }}
    return 0
}}

`       )
    }

    if allowLight {
        fmt.sbprintf(sb, 
`
_mani_newindex_{0:s}_ref :: proc "c" (L: ^lua.State) -> c.int {{
    context = mani.default_context()
    udata := transmute(^^{1:s})luaL.checkudata(L, 1, "{0:s}")
    key := lua.tostring(L, 2)
    switch key {{
        case: {{
            lua.pushnil(L)
        }}
`       , s.name, s.name)
        if luaFields != nil {
            for k, field in s.fields {
                shouldExport := false
                name: string
                if luaField, ok := luaFields[field.name]; ok {
                    shouldExport = true
                    if luaName, ok := luaField.(String); ok {
                        name = luaName
                    } else {
                        name = field.name
                    }  
                } else {
                    shouldExport = false
                }
                

                if shouldExport {
                    fmt.sbprintf(sb, 
`        
        case "{0:s}": {{
            mani.to_value(L, 3, &udata^.{1:s})
            return 1
        }}
`,    name, field.name)
                }
            }
        }

        fmt.sbprintf(sb, 
`
    }}
    return 1
}}

`       )
    }
}

write_struct_meta :: proc(config: ^GeneratorConfig, exports: FileExports, s: StructExport) {
    using strings
    sb := &(&config.files[exports.symbols_package]).lua_builder
    
    exportAttribs := s.attribs[LUAEXPORT_STR].(Attributes) or_else DEFAULT_PROC_ATTRIBUTES
    // This makes LuaExport.Name not enitrely usable, I should map struct names to lua names
    className :=  exportAttribs["Name"].(String) or_else s.name
    fmt.sbprintf(sb, "---@class %s\n", className)
    for comment in s.lua_docs {
        fmt.sbprintf(sb, "---%s\n", comment)
    }
    if fieldsAttrib, found := exportAttribs["Fields"].(Attributes); found {
        for k, field in s.fields {
            name: string
            luaType := "any" 
            fieldType := field.type[1:] if is_pointer_type(field.type) else field.type
            if luaField, ok := fieldsAttrib[field.name]; ok {
                if luaName, ok := luaField.(String); ok {
                    name = luaName
                } else {
                    name = field.name
                } 

                if type, found := config.lua_types[fieldType]; found {
                    luaType = type 
                } else {
                    #partial switch type in exports.symbols[fieldType] {
                        case ArrayExport: {
                            // Note(Dragos): Not the best. Will need some refactoring
                            luaType = type.attribs["LuaExport"].(Attributes)["Name"].(String) or_else type.name
             
                        }
        
                        case StructExport: {
                            luaType = type.attribs["LuaExport"].(Attributes)["Name"].(String) or_else type.name
                        }
                    }
                }
                fmt.sbprintf(sb, "---@field %s %s\n", name, luaType)
            } 
        }
    }
    fmt.sbprintf(sb, "%s = {{}}\n\n", className)
    
    if methodsAttrib, found := exportAttribs["Methods"]; found {
        methods := methodsAttrib.(Attributes)
        for odinProc, val in methods {
            methodName: string 
            if name, found := val.(String); found {
                methodName = name 
            } else {
                methodName = odinProc
            }

            
            procExport := exports.symbols[odinProc].(ProcedureExport)
            write_proc_meta(config, exports, procExport, fmt.tprintf("%s:%s", className, methodName), 1)

        }
    }
}