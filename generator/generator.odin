package mani_generator

import strings "core:strings"
import fmt "core:fmt"
import filepath "core:path/filepath"
import os "core:os"
import json "core:encoding/json"

DEFAULT_PROC_ATTRIBUTES := Attributes {
    
}

DEFAULT_STRUCT_ATTRIBUTES := Attributes {
    "Type" = Attributes {
        "Full" = nil, 
        "Light" = nil,
    },
}


PackageFile :: struct {
    builder: strings.Builder,
    filename: string,
    imports: map[string]FileImport, // Key: import package name; Value: import text

    // Lua LSP metadata
    lua_filename: string,
    lua_builder: strings.Builder,
    lua_types: map[string]string, // Key: odin type
}

package_file_make :: proc(path: string, luaPath: string) -> PackageFile {
    return PackageFile {
        builder = strings.builder_make(), 
        filename = path,
        imports = make(map[string]FileImport),

        lua_builder = strings.builder_make(),
        lua_filename = luaPath,
        lua_types = make(map[string]string)
    }
}

GeneratorConfig :: struct {
    input_directory: string,
    meta_directory: string,
    files: map[string]PackageFile,
}


config_package :: proc(config: ^GeneratorConfig, pkg: string, filename: string) {
    result, ok := &config.files[pkg]
    if !ok {
        using strings

        
        path := filepath.dir(filename, context.temp_allocator)
    
        name := filepath.stem(filename)
        filename := strings.concatenate({path, "/", pkg, ".generated.odin"})
        luaFilename := strings.concatenate({config.meta_directory, "/", pkg, ".lsp.lua"})

        config.files[pkg] = package_file_make(filename, luaFilename)
        sb := &(&config.files[pkg]).builder
        file := &config.files[pkg]

        luaSb := &(&config.files[pkg]).lua_builder

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
        file.imports["strings"] = FileImport {
            name = "strings",
            text = `import strings "core:strings"`,
        }
        
        for _, imp in file.imports {
            write_string(sb, imp.text)
            write_string(sb, "\n")
        }
        write_string(sb, "\n")
        
        write_string(luaSb, "---@meta\n\n")
    }
}

config_from_json :: proc(config: ^GeneratorConfig, file: string) {
    data, ok := os.read_entire_file(file)
    if !ok {
        fmt.printf("Failed to read config file\n")
        return
    }
    defer delete(data)
    str := strings.clone_from_bytes(data, context.temp_allocator)
    obj, err := json.parse_string(str)
    if err != .None {
        return
    }
    defer json.destroy_value(obj) 

    root := obj.(json.Object)
    config.input_directory = strings.clone(root["dir"].(json.String))
    config.meta_directory = strings.clone(root["meta_dir"].(json.String))
}

create_config_from_args :: proc() -> (result: GeneratorConfig) {
    result = GeneratorConfig{}
    for arg in os.args {
        pair := strings.split(arg, ":", context.temp_allocator)
        if len(pair) == 1 {
            // Input directory
            result.input_directory = pair[0]
            config_from_json(&result, pair[0])
        }
    }
    return
}

generate_struct_lua_wrapper :: proc(config: ^GeneratorConfig, exports: FileExports, s: StructExport, filename: string) {
    using strings 
    sb := &(&config.files[exports.symbols_package]).builder
    exportAttribs := s.attribs["LuaExport"].(Attributes)
    if methods, found := exportAttribs["Methods"].(Attributes); found {
        generate_methods_mapping(config, exports, methods, s.name)
    }
    write_lua_index(sb, exports, s)
    write_lua_newindex(sb, exports, s)
    write_lua_struct_init(sb, exports, s)
}

generate_array_lua_wrapper :: proc(config: ^GeneratorConfig, exports: FileExports, arr: ArrayExport, filename: string) {
    using strings 
    sb := &(&config.files[exports.symbols_package]).builder

    exportAttribs := arr.attribs["LuaExport"].(Attributes)
    if methods, found := exportAttribs["Methods"].(Attributes); found {
        generate_methods_mapping(config, exports, methods, arr.name)
    }

    write_lua_array_index(sb, exports, arr)
    write_lua_array_newindex(sb, exports, arr)
    write_lua_array_init(sb, exports, arr)
}

generate_methods_mapping :: proc(config: ^GeneratorConfig, exports: FileExports, methods: Attributes, name: string) {
    using strings, fmt
    sb := &(&config.files[exports.symbols_package]).builder

    write_string(sb, `@(private = "file")`)
    write_rune(sb, '\n')
    write_string(sb, "_mani_methods_")
    write_string(sb, name)
    write_string(sb, " := map[string]lua.CFunction {\n")

    for odinName, v in methods {
        luaName := v.(String)
        sbprintf(sb, "    \"%s\" = _mani_%s,\n", luaName, odinName)
    }
    write_string(sb, "}\n")
}

write_lua_array_init :: proc(sb: ^strings.Builder, exports: FileExports, arr: ArrayExport) {
    using strings, fmt

    exportAttribs := arr.attribs[LUAEXPORT_STR].(Attributes)
    udataType := exportAttribs["Type"].(Attributes)  
    allowLight := "Light" in udataType
    allowFull := "Full" in udataType
    
    luaName := exportAttribs["Name"].(String) or_else arr.name


    write_string(sb, "@(init)\n")
    write_string(sb, "_mani_init_")
    write_string(sb, arr.name)
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
    write_string(sb, arr.name)
    write_rune(sb, '"')
    write_string(sb, "\n    ")

    write_string(sb, "expStruct.lua_name = ")
    write_rune(sb, '"')
    write_string(sb, luaName)
    write_rune(sb, '"')
    write_string(sb, "\n    ")

    write_string(sb, "expStruct.type = ")
    write_string(sb, arr.name)
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
        write_string(sb, arr.name)
        write_string(sb, "_ref")
        write_rune(sb, '"')
        write_string(sb, "\n    ")

        write_string(sb, "refMeta.odin_type = ")
        write_rune(sb, '^')
        write_string(sb, arr.name)
        write_string(sb, "\n    ")

        write_string(sb, "refMeta.index = ")
        write_string(sb, "_mani_index_")
        write_string(sb, arr.name)
        write_string(sb, "_ref")
        write_string(sb, "\n    ")

        write_string(sb, "refMeta.newindex = ")
        write_string(sb, "_mani_newindex_")
        write_string(sb, arr.name)
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
        write_string(sb, arr.name)
        write_rune(sb, '"')
        write_string(sb, "\n    ")

        write_string(sb, "copyMeta.odin_type = ")
        write_string(sb, arr.name)
        write_string(sb, "\n    ")

        write_string(sb, "copyMeta.index = ")
        write_string(sb, "_mani_index_")
        write_string(sb, arr.name)
        write_string(sb, "\n    ")

        write_string(sb, "copyMeta.newindex = ")
        write_string(sb, "_mani_newindex_")
        write_string(sb, arr.name)
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

write_lua_array_index :: proc(sb: ^strings.Builder, exports: FileExports, arr: ArrayExport) {
    using strings, fmt
    
    exportAttrib := arr.attribs["LuaExport"].(Attributes)
    luaName := exportAttrib["Name"].(String) or_else arr.name
    udataType := exportAttrib["Type"].(Attributes)
    allowLight := "Light" in udataType
    allowFull := "Full" in udataType
    swizzleTypes := exportAttrib["SwizzleTypes"].(Attributes) 
    allowedFields := cast(string)exportAttrib["Fields"].(Identifier)
    hasMethods := "Methods" in exportAttrib
    //0: Arr2
    //1: Arr3 
    //2: Arr4
    arrayTypes: [3]ArrayExport
    for typename in swizzleTypes {
        type := exports.symbols[typename].(ArrayExport)
        arrayTypes[type.len - 2] = type
    }
    arrayTypes[arr.len - 2] = arr

    if allowFull {
        if hasMethods {
            sbprintf(sb,
                `
_mani_index_{0:s} :: proc "c" (L: ^lua.State) -> c.int {{

    context = mani.default_context()
    udata: {0:s}
    mani.to_value(L, 1, &udata)
    // Note(Dragos): It should also accept indices
    key := lua.tostring(L, 2)
    if method, found := _mani_methods_{0:s}[key]; found {{
        mani.push_value(L, method)
        return 1
    }}
    assert(len(key) <= 4, "Vectors can only be swizzled up to 4 elements")

    result: {1:s} // Highest possible array type
    for r, i in key {{
        if idx := strings.index_rune("{3:s}", r); idx != -1 {{
            arrIdx := idx %% {2:i}
            result[i] = udata[arrIdx]
        }}
    }}

    switch len(key) {{
        case 1: {{
            mani.push_value(L, result.x)
        }}

        case 2: {{
            mani.push_value(L, result.xy)
        }}

        case 3: {{
            mani.push_value(L, result.xyz)
        }}

        case 4: {{
            mani.push_value(L, result)
        }}

        case: {{
            lua.pushnil(L)
        }}
    }}

    return 1
}}
            `, arr.name, arrayTypes[2].name, arr.len, allowedFields)
        } else {
            sbprintf(sb,
                `
_mani_index_{0:s} :: proc "c" (L: ^lua.State) -> c.int {{

    context = mani.default_context()
    udata: {0:s}
    mani.to_value(L, 1, &udata)
    // Note(Dragos): It should also accept indices
    key := lua.tostring(L, 2)
    
    assert(len(key) <= 4, "Vectors can only be swizzled up to 4 elements")

    result: {1:s} // Highest possible array type
    for r, i in key {{
        if idx := strings.index_rune("{3:s}", r); idx != -1 {{
            arrIdx := idx %% {2:i}
            result[i] = udata[arrIdx]
        }}
    }}

    switch len(key) {{
        case 1: {{
            mani.push_value(L, result.x)
        }}

        case 2: {{
            mani.push_value(L, result.xy)
        }}

        case 3: {{
            mani.push_value(L, result.xyz)
        }}

        case 4: {{
            mani.push_value(L, result)
        }}

        case: {{
            lua.pushnil(L)
        }}
    }}

    return 1
}}
            `, arr.name, arrayTypes[2].name, arr.len, allowedFields)
        }
        
    }

    if allowLight {
        if hasMethods {
            sbprintf(sb,
                `
_mani_index_{0:s}_ref :: proc "c" (L: ^lua.State) -> c.int {{

    context = mani.default_context()
    udata: ^{0:s}
    mani.to_value(L, 1, &udata)
    // Note(Dragos): It should also accept indices
    key := lua.tostring(L, 2)
    if method, found := _mani_methods_{0:s}[key]; found {{
        mani.push_value(L, method)
        return 1
    }}
    assert(len(key) <= 4, "Vectors can only be swizzled up to 4 elements")

    result: {1:s} // Highest possible array type
    for r, i in key {{
        if idx := strings.index_rune("{3:s}", r); idx != -1 {{
            arrIdx := idx %% {2:i}
            result[i] = udata[arrIdx]
        }}
    }}

    switch len(key) {{
        case 1: {{
            mani.push_value(L, result.x)
        }}

        case 2: {{
            mani.push_value(L, result.xy)
        }}

        case 3: {{
            mani.push_value(L, result.xyz)
        }}

        case 4: {{
            mani.push_value(L, result)
        }}

        case: {{
            lua.pushnil(L)
        }}
    }}

    return 1
}}
            `, arr.name, arrayTypes[2].name, arr.len, allowedFields)
        } else {
            sbprintf(sb,
                `
    _mani_index_{0:s}_ref :: proc "c" (L: ^lua.State) -> c.int {{
    
        context = mani.default_context()
        udata: ^{0:s}
        mani.to_value(L, 1, &udata)
        // Note(Dragos): It should also accept indices
        key := lua.tostring(L, 2)
        
        assert(len(key) <= 4, "Vectors can only be swizzled up to 4 elements")
    
        result: {1:s} // Highest possible array type
        for r, i in key {{
            if idx := strings.index_rune("{3:s}", r); idx != -1 {{
                arrIdx := idx %% {2:i}
                result[i] = udata[arrIdx]
            }}
        }}
    
        switch len(key) {{
            case 1: {{
                mani.push_value(L, result.x)
            }}
    
            case 2: {{
                mani.push_value(L, result.xy)
            }}
    
            case 3: {{
                mani.push_value(L, result.xyz)
            }}
    
            case 4: {{
                mani.push_value(L, result)
            }}
    
            case: {{
                lua.pushnil(L)
            }}
        }}
    
        return 1
    }}
            `, arr.name, arrayTypes[2].name, arr.len, allowedFields)
        }
    }
    
}

write_lua_array_newindex :: proc(sb: ^strings.Builder, exports: FileExports, arr: ArrayExport) {
    using strings, fmt
    
    exportAttrib := arr.attribs["LuaExport"].(Attributes)
    luaName := exportAttrib["Name"].(String) or_else arr.name
    udataType := exportAttrib["Type"].(Attributes)
    allowLight := "Light" in udataType
    allowFull := "Full" in udataType
    swizzleTypes := exportAttrib["SwizzleTypes"].(Attributes) 
    allowedFields := cast(string)exportAttrib["Fields"].(Identifier)
    
    //0: Arr2
    //1: Arr3 
    //2: Arr4
    arrayTypes: [3]ArrayExport
    for typename in swizzleTypes {
        type := exports.symbols[typename].(ArrayExport)
        arrayTypes[type.len - 2] = type
    }
    arrayTypes[arr.len - 2] = arr

    if allowFull {
        sbprintf(sb,
            `
_mani_newindex_{0:s} :: proc "c" (L: ^lua.State) -> c.int {{

    context = mani.default_context()
    udata: {0:s} 
    mani.to_value(L, 1, &udata)
    // Note(Dragos): It should also accept indices
    key := lua.tostring(L, 2)
    assert(len(key) <= {1:d}, "Cannot assign more indices than the vector takes")

    switch len(key) {{
        case 1: {{
            val: {2:s} 
            mani.to_value(L, 3, &val.x)
            
            if idx := strings.index_byte("{5:s}", key[0]); idx != -1 {{
                arrIdx := idx %% {1:d}
                udata[arrIdx] = val.x
            }}
        }

        case 2: {{
            val: {2:s}
            mani.to_value(L, 3, &val)
            for r, i in key {{
                if idx := strings.index_rune("{5:s}", r); idx != -1 {{
                    arrIdx := idx %% {1:d}
                    udata[arrIdx] = val[i]
                }}
            }}
        }}

        case 3: {{
            val: {3:s}
            mani.to_value(L, 3, &val)
            for r, i in key {{  
                if idx := strings.index_rune("{5:s}", r); idx != -1 {{
                    arrIdx := idx %% {1:d}
                    udata[arrIdx] = val[i]
                }}
            }}
        }}

        case 4: {{
            val: {4:s}
            mani.to_value(L, 3, &val)
            for r, i in key {{                   
                if idx := strings.index_rune("{5:s}", r); idx != -1 {{
                    arrIdx := idx %% {1:d}
                    udata[arrIdx] = val[i]
                }}
            }}
        }}
    }}


    return 0
}}
        `, arr.name, arr.len, arrayTypes[0].name, arrayTypes[1].name, arrayTypes[2].name, allowedFields)
    }

    if allowLight {
        sbprintf(sb,
            `
_mani_newindex_{0:s}_ref :: proc "c" (L: ^lua.State) -> c.int {{

    context = mani.default_context()
    udata: ^{0:s} 
    mani.to_value(L, 1, &udata)
    // Note(Dragos): It should also accept indices
    key := lua.tostring(L, 2)
    assert(len(key) <= {1:d}, "Cannot assign more indices than the vector takes")

    switch len(key) {{
        case 1: {{
            val: {2:s} 
            mani.to_value(L, 3, &val.x)      
            if idx := strings.index_byte("{5:s}", key[0]); idx != -1 {{
                arrIdx := idx %% {1:d}
                udata[arrIdx] = val.x
            }}
        }

        case 2: {{
            val: {2:s}
            mani.to_value(L, 3, &val)
            for r, i in key {{
                if idx := strings.index_rune("{5:s}", r); idx != -1 {{
                    arrIdx := idx %% {1:d}
                    udata[arrIdx] = val[i]
                }}
            }}
        }}

        case 3: {{
            val: {3:s}
            mani.to_value(L, 3, &val)    
            for r, i in key {{   
                if idx := strings.index_rune("{5:s}", r); idx != -1 {{
                    arrIdx := idx %% {1:d}
                    udata[arrIdx] = val[i]
                }}
            }}
        }}

        case 4: {{
            val: {4:s}
            mani.to_value(L, 3, &val)
            for r, i in key {{                   
                if idx := strings.index_rune("{5:s}", r); idx != -1 {{
                    arrIdx := idx %% {1:d}
                    udata[arrIdx] = val[i]
                }}
            }}
        }}
    }}


    return 0
}}
        `, arr.name, arr.len, arrayTypes[0].name, arrayTypes[1].name, arrayTypes[2].name, allowedFields)
    }

}

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

        if methodsAttrib, found := exportAttribs["Methods"]; found {
            methods := methodsAttrib.(Attributes)
            for odinProc, luaNameAttrib in methods {
                luaName: string 
                if name, found := luaNameAttrib.(String); found {
                    luaName = name 
                } else {
                    luaName = odinProc
                }
                fmt.sbprintf(sb, 
`        
        case "{0:s}": {{
            mani.push_value(L, _mani_{1:s})
            return 1
        }}
`,    luaName, odinProc)
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

write_struct_meta :: proc(config: ^GeneratorConfig, exports: FileExports, s: StructExport) {
    using strings
    sb := &(&config.files[exports.symbols_package]).lua_builder
    fmt.sbprintf(sb, "---@class %s\n", s.name)
    for comment in s.lua_docs {
        fmt.sbprintf(sb, "---%s\n", comment)
    }
    exportAttribs := s.attribs[LUAEXPORT_STR].(Attributes) or_else DEFAULT_PROC_ATTRIBUTES
    // This makes LuaExport.Name not enitrely usable, I should map struct names to lua names
    luaName :=  s.name
    fmt.sbprintf(sb, "%s = {{}}\n\n", luaName)
    
    if methodsAttrib, found := exportAttribs["Methods"]; found {
        methods := methodsAttrib.(Attributes)
        for odinProc, val in methods {
            luaName: string 
            if name, found := val.(String); found {
                luaName = name 
            } else {
                luaName = odinProc
            }

            procExport := exports.symbols[odinProc].(ProcedureExport)
            for comment in procExport.lua_docs {
                fmt.sbprintf(sb, "---%s\n", comment)
            }

            fmt.sbprintf(sb, "function %s:%s(", s.name, luaName)

            // We skip the first parameter, assuming it's the struct itself
            // Is this legit? Needs testing
            params := procExport.params[1:] 
            for param, i in params {
                write_string(sb, param.name)
                if i != len(params) - 1 do write_string(sb, ", ")
            }
        
            write_string(sb, ") end\n\n")
        }
    }
}

write_proc_meta :: proc(config: ^GeneratorConfig, exports: FileExports, fn: ProcedureExport) {
    using strings
    sb := &(&config.files[exports.symbols_package]).lua_builder

    for comment in fn.lua_docs {
        fmt.sbprintf(sb, "---%s\n", comment)
    }
    exportAttribs := fn.attribs[LUAEXPORT_STR].(Attributes) or_else DEFAULT_PROC_ATTRIBUTES
    luaName := exportAttribs["Name"].(String) if "Name" in exportAttribs else fn.name
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

    for k, exp in exports.symbols {
        
        switch x in exp {
            case ProcedureExport: {
                generate_proc_lua_wrapper(config, exports, x, exports.relpath)
                write_proc_meta(config, exports, x)
            }

            case StructExport: {
                generate_struct_lua_wrapper(config, exports, x, exports.relpath)
                write_struct_meta(config, exports, x)
            }

            case ArrayExport: {
                generate_array_lua_wrapper(config, exports, x, exports.relpath)
            }
        }
    }
}