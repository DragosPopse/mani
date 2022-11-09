package odin_writer

import "core:strings"
import "core:strconv"

OdinWriter :: struct {
    sb: strings.Builder,
    curr_indent: int,
    indentator: string,
}

writer_make :: proc(max_depth := 10, indent := "    ", allocator := context.allocator) -> (result: OdinWriter) {
    using result 
    sb = strings.builder_make(allocator)
    curr_indent = 0
    indentBuilder := strings.builder_make(allocator)
    
    indentator = strings.to_string(indentBuilder)
    
    return
}

writer_destroy :: proc(w: ^OdinWriter) {
    strings.builder_destroy(&w.sb)
    delete(w.indentator)
}

