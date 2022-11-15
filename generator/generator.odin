package mani_generator

import strings "core:strings"
import fmt "core:fmt"
import filepath "core:path/filepath"
import os "core:os"

DEFAULT_PROC_ATTRIBUTES := Attributes {
    
}

DEFAULT_STRUCT_ATTRIBUTES := Attributes {
    "Mode" = Attributes {
        "Ref" = nil, 
        "Copy" = nil,
    },
}


PackageFile :: struct {
    builder: strings.Builder,
    filename: string,
    imports: map[string]FileImport, // Key: import package name; Value: import text

    // Lua LSP metadata
    lua_filename: string,
    lua_builder: strings.Builder,
}

package_file_make :: proc(path: string) -> PackageFile {
    return PackageFile {
        builder = strings.builder_make(), 
        filename = path,
        imports = make(map[string]FileImport),
    }
}

GeneratorConfig :: struct {
    input_directory: string,
    files: map[string]PackageFile,
}


config_package :: proc(config: ^GeneratorConfig, pkg: string, filename: string) {
    result, ok := &config.files[pkg]
    if !ok {
        using strings

        
        path := filepath.dir(filename, context.temp_allocator)
        name := filepath.stem(filename)
        filename := strings.concatenate({path, "/", pkg, ".generated.odin"})
        config.files[pkg] = package_file_make(filename)
        sb := &(&config.files[pkg]).builder
        file := &config.files[pkg]

        write_string(sb, "package ")
        write_string(sb, pkg)
        write_string(sb, "\n\n")
    
        // Add required imports
   
        file.imports["c"] = FileImport {
            name = "c",
            text = `import c "core:c"`,
        }
        file.imports["fmt"] = FileImport {
            name = "fmt",
            text = `import fmt "core:fmt"`,
        }
        file.imports["runtime"] = FileImport {
            name = "runtime",
            text = `import runtime "core:runtime"`,
        }
        file.imports["lua"] = FileImport {
            name = "lua",
            text = `import lua "shared:lua"`,
        }
        file.imports["luaL"] = FileImport {
            name = "luaL",
            text = `import luaL "shared:luaL"`,
        }
        file.imports["mani"] = FileImport {
            name = "mani",
            text = `import mani "shared:mani"`,
        }
        
        for _, imp in file.imports {
            write_string(sb, imp.text)
            write_string(sb, "\n")
        }
        write_string(sb, "\n")
    }
}


create_config_from_args :: proc() -> (result: GeneratorConfig) {
    result = GeneratorConfig{}
    for arg in os.args {
        pair := strings.split(arg, ":", context.temp_allocator)
        if len(pair) == 1 {
            // Input directory
            result.input_directory = pair[0]
        }
    }
    return
}

generate_struct_lua_wrapper :: proc(config: ^GeneratorConfig, exports: FileExports, s: StructExport, filename: string) {
    using strings 
    sb := &(&config.files[exports.symbols_package]).builder
    write_lua_index(sb, exports, s)
    write_lua_newindex(sb, exports, s)
    write_lua_struct_init(sb, exports, s)
}

write_lua_struct_init :: proc(sb: ^strings.Builder, exports: FileExports, s: StructExport) {
    using strings

    exportAttribs := s.attribs[LUAEXPORT_STR].(Attributes) or_else DEFAULT_STRUCT_ATTRIBUTES
    exportMode := exportAttribs["Mode"].(Attributes)  
    allowRef := "Ref" in exportMode
    allowCopy := "Copy" in exportMode
    
    luaName := exportAttribs["Name"].(String) if "Name" in exportAttribs else s.name


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

    if allowRef {
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

        write_string(sb, "expStruct.ref_meta = refMeta")
        write_string(sb, "\n    ")
    }

    if allowCopy {
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

        write_string(sb, "expStruct.copy_meta = copyMeta")
        write_string(sb, "\n    ")
        write_string(sb, "\n    ")

    }

    //exportAll := "All" in s.properties[LUAEXPORT_STR]
    

    // Note(Dragos): Not the coolest API imo
    // Yep this doesn't work quite well. Should figure out more things
    /*if LUAFIELDS_STR in s.properties {
        for k, v in s.properties[LUAFIELDS_STR] {
            luaName: string
            if v.value == "" {
                luaName = v.name
            } else {
                luaName = v.value
            }
            
            write_string(sb, "expStruct.fields[")
            write_rune(sb, '"')
            write_string(sb, luaName)
            write_rune(sb, '"')
            write_string(sb, "] = mani.StructFieldExport { ")
            write_string(sb, "lua_name = ")
            write_rune(sb, '"')
            write_string(sb, luaName)
            write_rune(sb, '"')
            write_string(sb, ", odin_name = ")
            write_rune(sb, '"')
            write_string(sb, v.name)
            write_rune(sb, '"')
            write_string(sb, ", type = ")
            write_string(sb, s.fields[k].type)
            write_string(sb, " }\n    ")
        }
    } else { // Export all
        for k, field in s.fields {
            write_string(sb, "expStruct.fields[")
            write_rune(sb, '"')
            write_string(sb, field.odin_name)
            write_rune(sb, '"')
            write_string(sb, "] = mani.StructFieldExport { ")
            write_string(sb, "lua_name = ")
            write_rune(sb, '"')
            write_string(sb, field.odin_name)
            write_rune(sb, '"')
            write_string(sb, ", odin_name = ")
            write_rune(sb, '"')
            write_string(sb, field.odin_name)
            write_rune(sb, '"')
            write_string(sb, ", type = ")
            write_string(sb, field.type)
            write_string(sb, " }\n    ")
        }
    }*/
    
    write_string(sb, "mani.add_struct(expStruct)")
    write_string(sb, "\n}\n\n")
}

write_lua_newstruct :: proc(sb: ^strings.Builder, exports: FileExports, s: StructExport) {
    
}

write_lua_index :: proc(sb: ^strings.Builder, exports: FileExports, s: StructExport) {
    using strings
    exportAttribs := s.attribs[LUAEXPORT_STR].(Attributes) or_else DEFAULT_STRUCT_ATTRIBUTES
    luaFields := exportAttribs["Fields"].(Attributes) if "Fields" in exportAttribs else nil
    exportMode := exportAttribs["Mode"].(Attributes) 
    allowRef := "Ref" in exportMode
    allowCopy := "Copy" in exportMode

    if allowCopy {
        //write_string(sb, "_mani_index_")
        //write_string(sb, s.name)
        //write_string(sb, " :: proc(L: ^lua.State) {\n    ")
        //write_string(sb, "udata := ")
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
`       , s.name, s.name)


        for k, field in s.fields {
            shouldExport := false
            name: string
            if luaFields != nil {
                if luaField, ok := luaFields[field.odin_name]; ok {
                    shouldExport = true
                    if luaName, ok := luaField.(String); ok {
                        name = luaName
                    } else {
                        name = field.odin_name
                    }  
                } else {
                    shouldExport = false
                }
            } else {
                name = field.odin_name 
                shouldExport = true
            }

            if shouldExport {
                fmt.sbprintf(sb, 
`        
        case "{0:s}": {{
            mani.push_value(L, udata.{1:s})
            return 1
        }}
`,    name, field.odin_name)
            }
        }

        fmt.sbprintf(sb, 
`
    }}
    return 1
}}

`       )
    }

    if allowRef {
        //write_string(sb, "_mani_index_")
        //write_string(sb, s.name)
        //write_string(sb, " :: proc(L: ^lua.State) {\n    ")
        //write_string(sb, "udata := ")
        fmt.sbprintf(sb, 
`
_mani_index_{0:s}_ref :: proc "c" (L: ^lua.State) -> c.int {{
    context = mani.default_context()
    udata := transmute(^^{1:s})luaL.checkudata(L, 1, "{0:s}")
    key := lua.tostring(L, 2)
    switch key {{
        case: {{
            lua.pushnil(L)
            return 1
        }}
`       , s.name, s.name)
        for k, field in s.fields {
            shouldExport := false
            name: string
            if luaFields != nil {
                if luaField, ok := luaFields[field.odin_name]; ok {
                    shouldExport = true
                    if luaName, ok := luaField.(String); ok {
                        name = luaName
                    } else {
                        name = field.odin_name
                    }  
                } else {
                    shouldExport = false
                }
            } else {
                name = field.odin_name 
                shouldExport = true
            }

            if shouldExport {
                fmt.sbprintf(sb, 
`        
        case "{0:s}": {{
            mani.push_value(L, udata^.{1:s})
            return 1
        }}
`,    name, field.odin_name)
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
    exportMode := exportAttribs["Mode"].(Attributes) 
    allowRef := "Ref" in exportMode
    allowCopy := "Copy" in exportMode

    if allowCopy {
        //write_string(sb, "_mani_index_")
        //write_string(sb, s.name)
        //write_string(sb, " :: proc(L: ^lua.State) {\n    ")
        //write_string(sb, "udata := ")
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
        for k, field in s.fields {
            shouldExport := false
            name: string
            if luaFields != nil {
                if luaField, ok := luaFields[field.odin_name]; ok {
                    shouldExport = true
                    if luaName, ok := luaField.(String); ok {
                        name = luaName
                    } else {
                        name = field.odin_name
                    }  
                } else {
                    shouldExport = false
                }
            } else {
                name = field.odin_name 
                shouldExport = true
            }

            if shouldExport {
                fmt.sbprintf(sb, 
`        
        case "{0:s}": {{
            mani.to_value(L, 3, &udata.{1:s})
            return 0
        }}
`,    name, field.odin_name)
            }
        }

        fmt.sbprintf(sb, 
`
    }}
    return 0
}}

`       )
    }

    if allowRef {
        //write_string(sb, "_mani_index_")
        //write_string(sb, s.name)
        //write_string(sb, " :: proc(L: ^lua.State) {\n    ")
        //write_string(sb, "udata := ")
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
        for k, field in s.fields {
            shouldExport := false
            name: string
            if luaFields != nil {
                if luaField, ok := luaFields[field.odin_name]; ok {
                    shouldExport = true
                    if luaName, ok := luaField.(String); ok {
                        name = luaName
                    } else {
                        name = field.odin_name
                    }  
                } else {
                    shouldExport = false
                }
            } else {
                name = field.odin_name 
                shouldExport = true
            }

            if shouldExport {
                fmt.sbprintf(sb, 
`        
        case "{0:s}": {{
            mani.to_value(L, 3, &udata^.{1:s})
        }}
`,    name, field.odin_name)
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
    for paramType, i in fn.param_types {
        write_string(sb, fn.param_names[i])
        write_string(sb, ": ")
        write_string(sb, paramType)
        write_string(sb, "\n    ")
    }

    write_string(sb, "\n    ")

    //Get parameters from lua
    if fn.param_names != nil {
        for paramName, i in fn.param_names {
            write_string(sb, "mani.to_value(L, ") // Note(Dragos): This needs to be replaced
            write_int(sb, i + 1)
            write_string(sb, ", &")
            write_string(sb, paramName)
            write_string(sb, ")\n    ")
        }
    }
    

    // Declare results
    if fn.result_names != nil {
        for resultName, i in fn.result_names {
     
            write_string(sb, resultName)
            
            if i < len(fn.result_names) - 1 {
                write_string(sb, ", ")
            }
        }
        write_string(sb, " := ")
    }
    write_string(sb, fn.name)
    write_string(sb, "(")
    // Pass parameters to odin function
    for paramName, i in fn.param_names {
        write_string(sb, paramName)
        if i < len(fn.param_names) - 1 {
            write_string(sb, ", ")
        }
    }
    write_string(sb, ")\n\n    ")

    for resultName, i in fn.result_names {
        write_string(sb, "mani.push_value(L, ")
        write_string(sb, resultName)
        write_string(sb, ")\n    ")
    }
    write_string(sb, "\n    ")

    write_string(sb, "return ")
    write_int(sb, len(fn.result_types) if fn.result_types != nil else 0)
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

add_import :: proc(file: ^PackageFile, import_statement: FileImport) {
    if import_statement.name not_in file.imports {
        using strings
        sb := &file.builder
        write_string(sb, import_statement.text)
        write_string(sb, "\n")
        file.imports[import_statement.name] = import_statement
    }
}

generate_lua_exports :: proc(config: ^GeneratorConfig, exports: FileExports) {
    using strings
    config_package(config, exports.symbols_package, exports.relpath)
    file := &config.files[exports.symbols_package]
    
    for _, imp in exports.imports {
        add_import(file, imp)
    }

    for exp in exports.symbols {
        
        switch x in exp {
            case ProcedureExport: {
                generate_proc_lua_wrapper(config, exports, x, exports.relpath)
            }

            case StructExport: {
                generate_struct_lua_wrapper(config, exports, x, exports.relpath)
            }
        }
    }
}