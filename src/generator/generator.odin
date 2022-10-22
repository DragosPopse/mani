package generator

import strings "core:strings"
import fmt "core:fmt"
import filepath "core:path/filepath"
import os "core:os"



GeneratorConfig :: struct {
    input_directory: string,
    output_package: string,
    output_directory: string,
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
            case "-out-dir": {
                assert(len(pair) == 2)
                result.output_directory = pair[1]
            }
            case "-out-package": {
                assert(len(pair) == 2)
                result.output_package = pair[1]
            }
        }
    }
    return
}

generate_proc_lua_wrapper :: proc(sb: ^strings.Builder, pkg: string, fn: ProcedureExport) {
    using strings
    fn_name := strings.concatenate({fn.name, "_mani"}, context.temp_allocator)

    //Add the function to the init body


    write_string(sb, fn_name)
    write_string(sb, " :: proc \"c\" (L: ^lua.State) -> c.int {\n    ")

    write_string(sb, "using ")
    write_string(sb, pkg)
    write_string(sb, "\n\n    ")
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
    write_string(sb, "fmt.printf(\"Init happening\\n\")\n    ")
    write_string(sb, "mani.add_function(")
    write_string(sb, fn_name)
    write_string(sb, ", \"")
    write_string(sb, fn.lua_name)
    write_string(sb, "\"")
    write_string(sb, ")\n}\n")
    
    
}

generate_lua_exports :: proc(config: GeneratorConfig, exports: FileExports) {
    using strings

    sb := builder_make()
    exports_dir := filepath.dir(exports.relpath)
    output_dir := strings.concatenate({config.output_directory, "/", exports_dir}, context.temp_allocator)
    abspath, success := filepath.abs(output_dir)
    exp_abspath, _  := filepath.abs(exports.relpath)
    exportsdir_rel, _ := filepath.rel(abspath, exp_abspath)
    exportsdir_rel = filepath.dir(exportsdir_rel)
    exportsdir_rel, _ = filepath.to_slash(exportsdir_rel)
    exports_dir, _ = filepath.to_slash(exports_dir)

    write_string(&sb, "package ")
    write_string(&sb, exports.symbols_package)
    //write_string(&sb, "_generated")
    write_string(&sb, "\n\n")


    write_string(&sb, "import c \"core:c\"\n")
    write_string(&sb, "import runtime \"core:runtime\"\n")
    write_string(&sb, "import fmt \"core:fmt\"\n")
    write_string(&sb, "import lua \"shared:lua\"\n")
    write_string(&sb, "import luaL \"shared:luaL\"\n")
    write_string(&sb, "import luax \"shared:luax\"\n")
    write_string(&sb, "import mani \"shared:mani\"\n")
    write_string(&sb, "import ")
    write_string(&sb, exports.symbols_package)
    write_string(&sb, " ")
    write_string(&sb, "\"")
    write_string(&sb, exportsdir_rel)
    write_string(&sb, "\"")
    write_string(&sb, "\n\n")

    for exp in exports.symbols {
        switch x in exp {
            case ProcedureExport: {
                generate_proc_lua_wrapper(&sb, exports.symbols_package, x)
                write_string(&sb, "\n")
            }
        }
    }

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
}