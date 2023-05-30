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

import "attriparse"



main :: proc() {
    fmt.printf("Started mani\n")
    p: attriparse.Parser
    attriparse.parser_init(&p, {}) // We aren't using this yet
    attriparse.parse_package(&p, "./test")
    attriparse.print_parser_data(&p)
}

