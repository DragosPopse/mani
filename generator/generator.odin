package generator

import strings "core:strings"
import fmt "core:fmt"
import filepath "core:path/filepath"
import os "core:os"

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
        filename := strings.concatenate({path, "/", name, ".generated.odin"})
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
        file.imports["luax"] = FileImport {
            name = "luax",
            text = `import luax "shared:luax"`,
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

generate_proc_lua_wrapper :: proc(config: ^GeneratorConfig, exports: FileExports, fn: ProcedureExport, filename: string) {
    using strings
    fn_name := strings.concatenate({fn.name, "_mani"}, context.temp_allocator)
    config_package(config, exports.symbols_package, filename)
    sb := &(&config.files[exports.symbols_package]).builder
    //Add the function to the init body


    write_string(sb, fn_name)
    write_string(sb, " :: proc \"c\" (L: ^lua.State) -> c.int {\n    ")
    write_string(sb, "context = runtime.default_context()\n\n    ")
    // Declare parameters
    for paramType, i in fn.param_types {
        write_string(sb, fn.param_names[i])
        write_string(sb, ": ")
        write_string(sb, paramType)
        write_string(sb, "\n    ")
    }

    write_string(sb, "\n    ")

    //Get parameters from lua
    for paramName, i in fn.param_names {
        write_string(sb, "luax.get(L, ") // Note(Dragos): This needs to be replaced
        write_int(sb, i + 1)
        write_string(sb, ", &")
        write_string(sb, paramName)
        write_string(sb, ")\n    ")
    }

    // Declare results
    for resultName, i in fn.result_names {
     
        write_string(sb, resultName)
        
        if i < len(fn.result_names) - 1 {
            write_string(sb, ", ")
        }
    }
    write_string(sb, " := ")

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
        write_string(sb, "luax.push(L, ")
        write_string(sb, resultName)
        write_string(sb, ")\n    ")
    }
    write_string(sb, "\n    ")

    write_string(sb, "return ")
    write_int(sb, len(fn.result_types))
    write_string(sb, "\n")
    write_string(sb, "}\n")

    // Generate @init function to bind to mani
    write_string(sb, "\n")
    write_string(sb, "@(init)\n")
    write_string(sb, fn_name)
    write_string(sb, "_init :: proc() {\n    ")
    write_string(sb, "mani.add_function(")
    write_string(sb, fn_name)
    write_string(sb, ", \"")
    write_string(sb, fn.lua_name)
    write_string(sb, "\"")
    write_string(sb, ")\n}\n\n")
    
    
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

    file := &config.files[exports.symbols_package]
    
    for _, imp in exports.imports {
        add_import(file, imp)
    }

    for exp in exports.symbols {
        
        switch x in exp {
            case ProcedureExport: {
                generate_proc_lua_wrapper(config, exports, x, exports.relpath)
            }
        }
    }

    /*
    output := to_string(sb)

    output_dir_slash, new_alloc := filepath.to_slash(output_dir)
    dirs := strings.split(output_dir_slash, "/")
    for dir, i in dirs {
        dirname := strings.join(dirs[0:i + 1], "/")
        if !os.is_dir(dirname) {
            if err := os.make_directory(dirname, 0); err != os.ERROR_NONE {
                fmt.printf("Failed making directory %s %d\n", dirname, err)
            }
        }
    }
   
    stem := filepath.stem(exports.relpath)
    filename := strings.concatenate({output_dir, "/", stem, ".generated.odin"}, context.temp_allocator)
    fd, ok := os.open(filename, os.O_CREATE | os.O_WRONLY | os.O_TRUNC)

    os.write_string(fd, output)
    */
}