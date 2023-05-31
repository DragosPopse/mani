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


import ast "core:odin/ast"
import parser "core:odin/parser"
import tokenizer "core:odin/tokenizer"
import "core:mem"
import "core:log"

import "core:time"

import "codegen"



main :: proc() {
    fmt.printf("Started mani\n")
    
    program: codegen.Program
    program.collections["core"] = filepath.join({ODIN_ROOT, "core"})
    codegen.parse_program(&program, "./test")
    
    codegen.print_program_data(&program)
}

