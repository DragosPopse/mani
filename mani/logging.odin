package mani
import "core:odin/tokenizer"
import "core:odin/ast"
import "core:runtime"
import "core:log"
import "core:os"
import "core:strings"
import "core:fmt"

@(private = "file")
LevelHeaders := [?]string{
     0..<10 = "[MANIGEN_DEBUG] -- ",
	10..<20 = "[MANIGEN_INFO ] -- ",
	20..<30 = "[MANIGEN_WARN ] -- ",
	30..<40 = "[MANIGEN_ERROR] -- ",
	40..<50 = "[MANIGEN_FATAL] -- ",
}

GeneratorLoggerData :: struct {
    node: ^ast.Node,
    token: string,
}

GeneratorLoggerDebugOptions :: log.Options {
    .Terminal_Color,
    .Level,
    .Short_File_Path,
    .Line,
    .Procedure,
}

GeneratorLoggerReleaseOptions :: log.Options {
    .Terminal_Color,
    .Level,
}

create_generator_logger :: proc(lowest := log.Level.Debug) -> log.Logger {
    data := new(GeneratorLoggerData)
    opts := GeneratorLoggerDebugOptions when ODIN_DEBUG else GeneratorLoggerReleaseOptions
    return log.Logger {
        generator_logger_proc, 
        data,
        lowest,
        opts,
    }
}

destroy_generator_logger :: proc(logger: log.Logger)  {
    free(logger.data)
}

@(deferred_out = temp_logger_token_exit)
temp_logger_token :: proc(logger_data: rawptr, node: ^ast.Node, token: string) -> ^GeneratorLoggerData {
    data := cast(^GeneratorLoggerData)logger_data
    data.node = node
    data.token = token
    return data
}

temp_logger_token_exit :: proc(data: ^GeneratorLoggerData) {
    data.node = nil
}

generator_logger_proc :: proc(logger_data: rawptr, level: log.Level, text: string, options: log.Options, location := #caller_location) {
    h := os.stdout if level < log.Level.Error else os.stderr
    data := cast(^GeneratorLoggerData)logger_data 
    
    
    backing: [1024]byte
    buf := strings.builder_from_bytes(backing[:])

    do_generator_header(options, level, data, &buf)
    log.do_location_header(options, &buf, location)

    fmt.fprintf(h, "%s%s\n", strings.to_string(buf), text)
}

@(private = "file")
do_generator_header :: proc(opts: log.Options, level: log.Level, data: ^GeneratorLoggerData, str: ^strings.Builder) {

	RESET     :: "\x1b[0m"
	RED       :: "\x1b[31m"
	YELLOW    :: "\x1b[33m"
	DARK_GREY :: "\x1b[90m"

	col := RESET
	switch level {
	    case .Debug:   col = DARK_GREY
	    case .Info:    col = RESET
	    case .Warning: col = YELLOW
	    case .Error, .Fatal: col = RED
	}

	if .Level in opts {
		if .Terminal_Color in opts {
			fmt.sbprint(str, col)
		}
		fmt.sbprint(str, LevelHeaders[level])
		if .Terminal_Color in opts {
			fmt.sbprint(str, RESET)
		}
	}

    if data.node != nil {
        fmt.sbprintf(str, "[%s(%d): `%s`]", data.node.pos.file, data.node.pos.line, data.token)
    }
}
