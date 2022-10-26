package generator

import strings "core:strings"
import fmt "core:fmt"
import filepath "core:path/filepath"
import os "core:os"



GeneratorConfig :: struct {
    input_directory: string,
    builders: map[string]strings.Builder,
    filenames: map[string]string,
}


config_package :: proc(config: ^GeneratorConfig, pkg: string, filename: string) {
    result, ok := config.builders[pkg]
    if !ok {
        using strings
        // First file with package definition, initialize it
        config.builders[pkg] = strings.builder_make()
        builder := &config.builders[pkg]
        path := filepath.dir(filename, context.temp_allocator)
        name := filepath.stem(filename)
        config.filenames[pkg] = strings.concatenate({path, "/", name, ".generated.odin"})


        write_string(builder, "package ")
        write_string(builder, pkg)
        write_string(builder, "\n\n")
    
    
        write_string(builder, "import c \"core:c\"\n")
        write_string(builder, "import runtime \"core:runtime\"\n")
        write_string(builder, "import fmt \"core:fmt\"\n")
        write_string(builder, "import lua \"shared:lua\"\n")
        write_string(builder, "import luaL \"shared:luaL\"\n")
        write_string(builder, "import luax \"shared:luax\"\n")
        write_string(builder, "import mani \"shared:mani\"\n")
    }
}


create_config_from_args :: proc() -> (result: GeneratorConfig) {
    result = GeneratorConfig{}
    for arg in os.args {
        pair := strings.split(arg, ":", context.temp_allocator)
        switch pair[0] {
            case "-in-dir": {
                assert(len(pair) == 2)
                result.input_directory = pair[1]
            }
        }
    }
    return
}

generate_proc_lua_wrapper :: proc(config: ^GeneratorConfig, pkg: string, fn: ProcedureExport, filename: string) {
    using strings
    fn_name := strings.concatenate({fn.name, "_mani"}, context.temp_allocator)
    config_package(config, pkg, filename)
    sb := &config.builders[pkg]
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
        if resultName == "" {
            write_string(sb, "mani_result")
            write_int(sb, i)
        } else {
            write_string(sb, resultName)
        }
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

generate_lua_exports :: proc(config: ^GeneratorConfig, exports: FileExports) {
    using strings

    sb := builder_make()
    exports_dir := filepath.dir(exports.relpath)
    exp_abspath, _  := filepath.abs(exports.relpath)

    exports_dir, _ = filepath.to_slash(exports_dir)




    for exp in exports.symbols {
        switch x in exp {
            case ProcedureExport: {
                generate_proc_lua_wrapper(config, exports.symbols_package, x, exports.relpath)
                write_string(&sb, "\n")
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