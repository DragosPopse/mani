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

Property :: struct {
    name: string,
    value: string,
}

PropertyMap :: distinct map[string]Property
PropertyCollection :: distinct map[string]PropertyMap

NodeExport :: struct {
    properties: PropertyCollection,
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
    
    // Note(Dragos): memory leaks around everywhere
    symbol_exports = file_exports_make()
    abspath, succ := filepath.abs(".")
    err: filepath.Relative_Error
    symbol_exports.relpath, err = filepath.rel(abspath, fileName)
    symbol_exports.relpath, _ = filepath.to_slash(symbol_exports.relpath)
    symbol_exports.symbols_package = root.pkg_name
    for x in root.decls {
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
            // Note(Dragos): Should this be called in the parse_proc/parse_struct?
            properties, propErr := parse_properties(root, decl) // Todo(Dragos): Memory leaks when erroring
            if propErr != .OkExport do continue
            
            #partial switch v in decl.values[0].derived {
                case ^ast.Proc_Lit: {
                    exportProc := parse_proc(root, decl, v)
                    exportProc.properties = properties
                    append(&symbol_exports.symbols, exportProc) // Add the function to the results
                }

                case ^ast.Struct_Type: {
                    exportStruct, err := parse_struct(root, decl, v) 
                    exportStruct.properties = properties
                    if err == .OkExport {
                        append(&symbol_exports.symbols, exportStruct)
                    }
                }
            }

         
        }
    }

    return
}

parse_struct :: proc(root: ^ast.File, value_decl: ^ast.Value_Decl, struct_decl: ^ast.Struct_Type, allocator := context.allocator) -> (result: StructExport, err: ParseErr) {
    result.properties, err = parse_properties(root, value_decl, allocator)
    switch err {
        case .OkNoExport, .MissingLuaExport, .UnknownProperty: return

        case .OkExport: {
            result.name = value_decl.names[0].derived.(^ast.Ident).name
            result.fields = make(map[string]StructField) 
        }
    }
    return
}


ParseErr :: enum {
    OkNoExport,
    OkExport,
    MissingLuaExport, 
    UnknownProperty,
}

parse_properties :: proc(root: ^ast.File, value_decl: ^ast.Value_Decl, allocator := context.allocator) -> (collection: PropertyCollection, err: ParseErr) {
    err = .OkNoExport
    collection = nil

    valueType := reflect.union_variant_type_info(value_decl.values[0].derived)
    if valueType.id not_in ALLOWED_PROPERTIES {
        return nil, .OkNoExport
    }

    allowedPrefixes := ALLOWED_PROPERTIES[valueType.id]

    for attr, i in value_decl.attributes {
        prefixName, _ := get_attr_elem(root, attr.elems[0])
        if prefixName not_in allowedPrefixes do continue

        if collection == nil {
            collection = make(PropertyCollection)
        }
        if prefixName not_in collection {
            collection[prefixName] = make(PropertyMap)
        }

        properties := &collection[prefixName]
        allowedProperties := allowedPrefixes[prefixName]
        
        for x, j in attr.elems[1:] { // 0 is already checked, we skip
            attrName, attrVal := get_attr_elem(root, x)
            if allowedProperties == nil || attrName in allowedProperties {
                properties[attrName] = Property {
                    name = attrName,
                    value = attrVal,
                }
            } else {
                mani.temp_logger_token(context.logger.data, x, attrName)
                log.errorf("Found unknown attribute for %s prefix", prefixName)
            }
        }
        
    }
    return 
}

parse_proc :: proc(root: ^ast.File, value_decl: ^ast.Value_Decl, proc_lit: ^ast.Proc_Lit, allocator := context.allocator) -> (result: ProcedureExport) {
    v := proc_lit
    procType := v.type
    declName := value_decl.names[0].derived.(^ast.Ident).name // Note(Dragos): Does this work with 'a, b: int' ?????

    nParams := len(procType.params.list)
    nResults := len(procType.results.list)
    result.name = declName 

    // Note(Dragos): these should be checked for 0
    result.param_names = make([]string, nParams)
    result.param_types = make([]string, nParams)
    result.result_names = make([]string, nResults)
    result.result_types = make([]string, nResults)

    // Get parameters
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

    // Get results
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

    return
}


get_attr_elem :: proc(root: ^ast.File, elem: ^ast.Expr) -> (name: string, value: string) {
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
            }
            name = attr.name
        }

        case ^ast.Ident: {
            name = x.name
        }
    }
    return
}

is_pointer_type :: proc(token: string) -> bool {
    return token[0] == '^'
}


