package main

import "core:fmt"
import os "core:os"
import dlib "core:dynlib"
import c "core:c"
import libc "core:c/libc"
import runtime "core:runtime"
import strings "core:strings"
import intr "core:intrinsics"
import filepath "core:path/filepath"


import odin "core:odin"
import ast "core:odin/ast"
import parser "core:odin/parser"
import tokenizer "core:odin/tokenizer"
import gen "generator"



main :: proc() {
    using fmt  
    
    config := gen.create_config_from_args()
    if !os.is_dir(config.input_directory) {
        fprintf(os.stderr, "Could not open input directory %s\n", config.input_directory)
    }

    dirQueue := make([dynamic]string)
    append(&dirQueue, config.input_directory)
    for len(dirQueue) > 0 {
        idx := len(dirQueue) - 1
        if dirfd, err := os.open(dirQueue[idx]); err == os.ERROR_NONE {
            pop(&dirQueue)
            if files, err := os.read_dir(dirfd, 0); err == os.ERROR_NONE {
                for file in files {    
                    if os.is_dir(file.fullpath) {
                        append(&dirQueue, file.fullpath)
                    } else if filepath.long_ext(file.fullpath) == ".odin" {
                        symbols := gen.parse_symbols(file.fullpath)
                        // Note(Dragos): I should generate a file per package. Have a map[package]file0
                        gen.generate_lua_exports(&config, symbols)
                    }
                }
            }
        }
        else {
            pop(&dirQueue)
        }
    }
    delete(dirQueue)


    for pkg, file in &config.files {
        sb := &file.builder
        str := strings.to_string(sb^)
        fd, ok := os.open(file.filename, os.O_CREATE | os.O_WRONLY | os.O_TRUNC)
        defer os.close(fd)
        os.write_string(fd, str)
    }
}