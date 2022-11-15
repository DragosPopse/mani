package mani_generator

import fmt "core:fmt"
import os "core:os"
import ast "core:odin/ast"
import parser "core:odin/parser"
import tokenizer "core:odin/tokenizer"
import strings "core:strings"
import filepath "core:path/filepath"
import "core:log"
import "../shared/mani"
import "core:reflect"

LUA_PROC_ATTRIBUTES := map[string]bool {
    "Name" = true,
}

LUA_STRUCT_ATTRIBUTES := map[string]typeid {
    "Name" = string,
    "AllowRef" = nil,
    "AllowCopy" = nil,
}

ALLOWED_PROPERTIES := map[typeid]map[string]map[string]bool {
    ^ast.Proc_Lit = {
        "LuaExport" = {
            "Name" = true,
        },
    },

    ^ast.Struct_Type = {
        "LuaExport" = {
            "Name" = true,
            "AllowRef" = true,
            "AllowCopy" = true,
        },
        "LuaFields" = nil,
    },
}

LUAEXPORT_STR :: "LuaExport"
LUAFIELDS_STR :: "LuaFields"

String :: string
Identifier :: distinct String
Int :: i64 
Float :: f64 


AttribVal :: union {
    // nil: empty attribute, like a flag, array element, etc
    String,
    Identifier,
    Int,
    Attributes,
}

Attributes :: distinct map[string]AttribVal



NodeExport :: struct {
    attribs: Attributes,
    lua_docs: [dynamic]string,
}

StructField :: struct {
    odin_name: string,
    type: string,
}

StructExport :: struct {
    using base: NodeExport,
    name: string,
    fields: map[string]StructField, // Key: odin_name
}

ProcedureExport :: struct {
    using base: NodeExport,
    name: string,
    calling_convention: string,
    result_types: []string,
    result_names: []string,
    param_types: []string,
    param_names: []string,
}

SymbolExport :: union {
    ProcedureExport,
    StructExport,
}

FileImport :: struct {
    name: string,
    text: string,
}

FileExports :: struct {
    symbols_package: string,
    relpath: string,
    symbols: [dynamic]SymbolExport,
    imports: map[string]FileImport,
}

file_exports_make :: proc(allocator := context.allocator) -> FileExports {
    result := FileExports{}
    result.symbols = make([dynamic]SymbolExport, allocator)
    result.imports = make(map[string]FileImport, 128, allocator)
    return result
}

file_exports_destroy :: proc(obj: ^FileExports) {
    // Note(Dragos): Taken from string builder, shouldn't it be reversed?
    delete(obj.symbols)
    clear(&obj.symbols)
    
}

parse_symbols :: proc(fileName: string) -> (symbol_exports: FileExports) {
    context.logger = mani.create_generator_logger(log.Level.Debug)
    defer mani.destroy_generator_logger(context.logger)

    data, ok := os.read_entire_file(fileName);
    if !ok {
        fmt.fprintf(os.stderr, "Error reading the file\n")
    }

    p := parser.Parser{}
    p.flags += {parser.Flag.Optional_Semicolons}
    p.err = proc(pos: tokenizer.Pos, format: string, args: ..any) {
        fmt.printf(format, args)
        fmt.printf("\n")
    }
     

    f := ast.File{
        src = string(data),
        fullpath = fileName,
    }
    
    ok = parser.parse_file(&p, &f)

    
    if p.error_count > 0 {
        return
    }

    root := p.file

    commentMapping := make(map[int]^ast.Comment_Group)
    for comment in root.comments {
        commentMapping[comment.end.line] = comment
    }
    
    
    // Note(Dragos): memory leaks around everywhere
    symbol_exports = file_exports_make()
    abspath, succ := filepath.abs(".")
    err: filepath.Relative_Error
    symbol_exports.relpath, err = filepath.rel(abspath, fileName)
    symbol_exports.relpath, _ = filepath.to_slash(symbol_exports.relpath)
    symbol_exports.symbols_package = root.pkg_name
    
    for x, index in root.decls {

        #partial switch x in x.derived {
            case ^ast.Import_Decl: {
                importName: string
                importText := root.src[x.pos.offset : x.end.offset]
                if x.name.kind != .Invalid {
                    // got a name
                    importName = x.name.text
                } else {
                    // Take the name from the path
                    startPos := 0
                    for c, i in x.fullpath {
                        if c == ':' {
                            startPos = i + 1
                            break
                        }
                    }
                    // Note(Dragos): Even more memory leaks I don't care
                    split := strings.split(x.fullpath[startPos:], "/")
                    importName = split[len(split) - 1]
                    importName = strings.trim(importName, "\"")
                    if importName not_in symbol_exports.imports {
                        symbol_exports.imports[importName] = FileImport {
                            name = importName,
                            text = importText,
                        }
                    }
                   
                }     
            }
        }

        if decl, ok := x.derived.(^ast.Value_Decl); ok {
            if len(decl.attributes) < 1 do continue // No attributes here, move on

            #partial switch v in decl.values[0].derived {
                case ^ast.Proc_Lit: {
                    exportProc, err := parse_proc(root, decl, v)
                    if err == .Export {
                        exportProc.lua_docs = parse_lua_annotations(root, decl, commentMapping)
                        append(&symbol_exports.symbols, exportProc) 
                    }
                    
                }

                case ^ast.Struct_Type: {
                    exportStruct, err := parse_struct(root, decl, v) 
                    if err == .Export {
                        exportStruct.lua_docs = parse_lua_annotations(root, decl, commentMapping)
                        append(&symbol_exports.symbols, exportStruct)
                    }
                }
            }

         
        }
    }

    return
}



AttribErr :: enum {
    Skip,
    Export,
    Error,
}

parse_lua_annotations :: proc(root: ^ast.File, value_decl: ^ast.Value_Decl, mapping: map[int]^ast.Comment_Group, allocator := context.allocator) -> (docs: [dynamic]string) {
    if len(value_decl.attributes) > 0 {
        firstLine := value_decl.attributes[0].pos.line
        if group, found := mapping[firstLine - 1]; found {
            docs = make([dynamic]string, allocator)
            text := root.src[group.pos.offset : group.end.offset]
            lines := strings.split_lines(text, context.temp_allocator)
            for line in lines {
                for c, i in line {
                    if c == '@' {
                        append(&docs, line[i:])
                    }
                }
            }
        }
    }
    return
}

validate_proc_attributes :: proc(proc_decl: ^ast.Proc_Lit, attribs: Attributes) -> (err: AttribErr, msg: Maybe(string)) {
    if LUAEXPORT_STR not_in attribs {
        return .Skip, nil
    }

    exportAttribs := attribs[LUAEXPORT_STR] 


    return .Export, nil
}

validate_struct_attributes :: proc(struct_decl: ^ast.Struct_Type, attribs: Attributes) -> (err: AttribErr, msg: Maybe(string)) {
     if LUAEXPORT_STR not_in attribs {
        return .Skip, nil
    }

    exportAttribs := attribs[LUAEXPORT_STR] 
    

    return .Export, nil
}


get_attr_name :: proc(root: ^ast.File, elem: ^ast.Expr) -> (name: string) {
    #partial switch x in elem.derived  {
        case ^ast.Field_Value: {
            attr := x.field.derived.(^ast.Ident)
            name = attr.name
        }

        case ^ast.Ident: {
            name = x.name
        }
    }
    return
}

parse_attributes :: proc(root: ^ast.File, value_decl: ^ast.Value_Decl) -> (result: Attributes) {
    result = make(Attributes)
    for attr, i in value_decl.attributes {
        for x, j in attr.elems { 
            name := get_attr_name(root, x)
            
            result[name] = parse_attrib_val(root, x)
        }
        
    }
    return
}

parse_attrib_object :: proc(root: ^ast.File, obj: ^ast.Comp_Lit) -> (result: Attributes) {
    result = make(Attributes)
    for elem, i in obj.elems {
        name := get_attr_name(root, elem)
        result[name] = parse_attrib_val(root, elem)
    }
    return
}

parse_attrib_val :: proc(root: ^ast.File, elem: ^ast.Expr) -> (result: AttribVal) {
    #partial switch x in elem.derived  {
        case ^ast.Field_Value: {
            #partial switch v in x.value.derived {
                case ^ast.Basic_Lit: {
                    result = strings.trim(v.tok.text, "\"")
                    return
                }

                case ^ast.Ident: {
                    value := root.src[v.pos.offset : v.end.offset]
                    result = cast(Identifier)value
                }

                case ^ast.Comp_Lit: {
                    result = parse_attrib_object(root, v)
                }
            }
            return
        }

        case ^ast.Ident: {
            //result = cast(Identifier)x.name
            //fmt.printf("We shouldn't be an identifier %s\n", x.name)
            return nil
        }

        case ^ast.Comp_Lit: {
            //result = parse_attrib_object(root, x)
            fmt.printf("We shouldn't be in comp literal %v\n", x)
            return
        }
    }
    return nil
}

parse_struct :: proc(root: ^ast.File, value_decl: ^ast.Value_Decl, struct_decl: ^ast.Struct_Type, allocator := context.allocator) -> (result: StructExport, err: AttribErr) {
    
    result.attribs = parse_attributes(root, value_decl)

    if err, msg := validate_struct_attributes(struct_decl, result.attribs); err != .Export {
        return result, err
    }
  
    result.name = value_decl.names[0].derived.(^ast.Ident).name
    result.fields = make(map[string]StructField) 
    
    for field in struct_decl.fields.list {
        fName := field.names[0].derived.(^ast.Ident).name 
        fType: string
        #partial switch x in field.type.derived {
            case ^ast.Ident: {
                fType = x.name
            }
            case ^ast.Selector_Expr: { // What was this again?
                fType = root.src[x.pos.offset : x.end.offset] //godlike odin
            }
            case ^ast.Pointer_Type: {
                fType = root.src[x.pos.offset : x.end.offset]
            }
        }

        result.fields[fName] = StructField {
            odin_name = fName,
            type = fType,
        }
    }

    // Check if LuaFields match
    /*if LUAFIELDS_STR in result.properties {
        for fieldName, _ in result.properties[LUAFIELDS_STR] {
            if fieldName not_in result.fields {
                mani.temp_logger_token(context.logger.data, value_decl, fieldName)  
                log.errorf("Found unknown field in LuaFields. Make sure they match the struct!")
                err = .UnknownProperty
                return
            }
        }
    }*/
    
    err = .Export
    return
}


parse_proc :: proc(root: ^ast.File, value_decl: ^ast.Value_Decl, proc_lit: ^ast.Proc_Lit, allocator := context.allocator) -> (result: ProcedureExport, err: AttribErr) {
 
    //result.properties, err = parse_properties(root, value_decl)
    result.attribs = parse_attributes(root, value_decl)
    
    if err, msg := validate_proc_attributes(proc_lit, result.attribs); err != .Export {
        return result, err
    }
  
    v := proc_lit
    procType := v.type
    declName := value_decl.names[0].derived.(^ast.Ident).name // Note(Dragos): Does this work with 'a, b: int' ?????

   
    result.name = declName 
    switch conv in procType.calling_convention {
        case string: {
            result.calling_convention = conv
        }

        case ast.Proc_Calling_Convention_Extra: {
            result.calling_convention = "c" //not fully correct
        }

        case: { // nil, default calling convention
            result.calling_convention = "odin"
        }
    }
    // Note(Dragos): these should be checked for 0
    
    

    // Get parameters
    if procType.params != nil {
        nParams := len(procType.params.list)
        result.param_names = make([]string, nParams)
        result.param_types = make([]string, nParams)
        for param, i in procType.params.list {
            paramType: string
            paramName := param.names[0].derived.(^ast.Ident).name
        
            #partial switch x in param.type.derived {
                case ^ast.Ident: {
                    paramType = x.name
                }
                case ^ast.Selector_Expr: {
                    paramType = root.src[x.pos.offset : x.end.offset] //godlike odin
                }
                case ^ast.Pointer_Type: {
                    
                    paramType = root.src[x.pos.offset : x.end.offset]
                    
                    mani.temp_logger_token(context.logger.data, x, paramType)
                    
                    log.errorf("Pointer parameter type not supported")
                }
            }
            
            result.param_names[i] = paramName
            result.param_types[i] = paramType
            
        }
    }
    
    // Get results
    if procType.results != nil {
        nResults := len(procType.results.list)
        result.result_names = make([]string, nResults)
        result.result_types = make([]string, nResults)
    
        for rval, i in procType.results.list {
            resName: string
            resType: string
            #partial switch x in rval.type.derived {
                case ^ast.Ident: {
                    resType = x.name
                    resName = rval.names[0].derived.(^ast.Ident).name
                }
                case ^ast.Selector_Expr: {
                    if len(rval.names) != 0 {
                        resName = rval.names[0].derived.(^ast.Ident).name
                    }
                    resType = root.src[x.pos.offset : x.end.offset] //godlike odin
                }
            }
            if len(rval.names) == 0 || resName == resType {
                // Result name is not specified
                sb := strings.builder_make(context.temp_allocator)
                strings.write_string(&sb, "mani_result")
                strings.write_int(&sb, i)
                resName = strings.to_string(sb)
            }
            
            
            result.result_names[i] = resName
            result.result_types[i] = resType
        }
    }

    
    return result, .Export
}


get_attr_elem :: proc(root: ^ast.File, elem: ^ast.Expr) -> (name: string, value: string) { // value can be a map maybe
    #partial switch x in elem.derived  {
        case ^ast.Field_Value: {
            attr := x.field.derived.(^ast.Ident)
            
            #partial switch v in x.value.derived {
                case ^ast.Basic_Lit: {
                    value = strings.trim(v.tok.text, "\"")
                }

                case ^ast.Ident: {
                    value = root.src[v.pos.offset : v.end.offset]
                }

                case ^ast.Comp_Lit: {
                    
                }
            }
            name = attr.name
        }

        case ^ast.Ident: {
            name = x.name
        }
    }
    return
}

is_pointer_type  :: #force_inline proc(token: string) -> bool {
    return token[0] == '^'
}


