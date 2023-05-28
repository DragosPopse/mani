package odin_writer

import "core:strings"
import "core:fmt"
import "core:strconv"

OdinWriter :: struct {
    sb: ^strings.Builder,
    curr_indent: int,
    indentation: string,
}

writer_make :: proc(builder: ^strings.Builder, indent := "    ") -> (result: OdinWriter) {
    using result 
    sb = builder
    curr_indent = 0
    indentation = indent
    return
}

writer_destroy :: proc(w: ^OdinWriter) {
    strings.builder_destroy(w.sb)
}

indent :: proc(using w: ^OdinWriter) {
    using strings
    for in 0..<curr_indent {
        write_string(sb, indentation)
    }   
}

next_line :: proc(using w: ^OdinWriter) {
    using strings
    write_string(sb, "\n")
}

// This should be used in the same block. It won't modify indentation
write :: proc(using w: ^OdinWriter, str: string) {
    using fmt, strings
    indent(w)
    write_string(sb, str)
    next_line(w)
}

end_block :: proc(using w: ^OdinWriter) {
    using strings
    curr_indent -= 1 
    indent(w)
    write_string(sb, "}")
    next_line(w)
}

@(deferred_out = end_block)
begin_block_decl :: proc(using w: ^OdinWriter, identifier: string, type: string, decl_token := "::") -> ^OdinWriter {
    using strings, fmt
    indent(w)
    curr_indent += 1
    sbprintf(sb, "%s %s %s {{", identifier, decl_token, type)

    next_line(w)
    return w
}

@(deferred_out = end_block)
begin_if :: proc(using w: ^OdinWriter, cond: string) -> ^OdinWriter{
    using fmt
    indent(w)
    curr_indent += 1
    sbprintf(sb, "if %s {{", cond)
    next_line(w)

    return w
}

@(deferred_out = end_block)
begin_else_if :: proc(using w: ^OdinWriter, cond: string) -> ^OdinWriter {
    using fmt
    curr_indent -= 1
    indent(w)
    next_line(w)
    sbprintf(sb, "}} else %s {{", cond)
    curr_indent += 1
    next_line(w)
    return w
}

@(deferred_out = end_block)
begin_else :: proc(using w: ^OdinWriter) -> ^OdinWriter {
    using strings
    curr_indent -= 1
    next_line(w)
    write_string(sb, "} else {")
    curr_indent += 1
    next_line(w)
    return w
}

@(deferred_out = end_block)
begin_for :: proc(using w: ^OdinWriter, cond: string) -> ^OdinWriter {
    using fmt
    indent(w)
    curr_indent += 1
    sbprintf(sb, "for %s {{", cond)
    next_line(w)
    return w
}

@(deferred_out = end_block)
begin_switch :: proc(using w: ^OdinWriter, stmt: string) -> ^OdinWriter{
    using fmt
    indent(w)
    curr_indent += 1
    sbprintf(sb, "switch %s {{", stmt)
    next_line(w)
    return w
}

@(deferred_out = end_block)
begin_case :: proc(using w: ^OdinWriter, cond: string) -> ^OdinWriter{
    using fmt
    indent(w)
    curr_indent += 1
    sbprintf(sb, "case %s: {{", cond)
    next_line(w)
    return w
}