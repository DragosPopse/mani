package mani_generator

import strings "core:strings"
import fmt "core:fmt"
import filepath "core:path/filepath"
import os "core:os"
import json "core:encoding/json"

DEFAULT_PROC_ATTRIBUTES := Attributes {
    
}

// Note(Dragos): This should change
DEFAULT_STRUCT_ATTRIBUTES := Attributes {
    "Type" = Attributes {
        "Full" = nil, 
        "Light" = nil,
    },
}

GeneratorConfig :: struct {
    input_directory: string,
    meta_directory: string,
    files: map[string]PackageFile,
    lua_types: map[string]string, // Key: odin type
}


PackageFile :: struct {
    builder: strings.Builder,
    filename: string,
    imports: map[string]FileImport, // Key: import package name; Value: import text

    // Lua LSP metadata
    lua_filename: string,
    lua_builder: strings.Builder,
}

package_file_make :: proc(path: string, luaPath: string) -> PackageFile {
    return PackageFile {
        builder = strings.builder_make(), 
        filename = path,
        imports = make(map[string]FileImport),

        lua_builder = strings.builder_make(),
        lua_filename = luaPath,
    }
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
    defer json.destroy_value(obj) // Keys need to be cloned too

    root := obj.(json.Object)
    config.input_directory = strings.clone(root["dir"].(json.String))
    config.meta_directory = strings.clone(root["meta_dir"].(json.String))
    config.lua_types = make(map[string]string)
    types := root["types"].(json.Object)
    
    for luaType, val in types {
        odinTypes := val.(json.Array)
        for type in odinTypes {
            config.lua_types[strings.clone(type.(json.String))] = strings.clone(luaType)
        }
    }
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
                write_array_meta(config, exports, x)
            }
        }
    }
}