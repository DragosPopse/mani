package generator

import fmt "core:fmt"
import os "core:os"
import ast "core:odin/ast"
import parser "core:odin/parser"
import tokenizer "core:odin/tokenizer"
import strings "core:strings"
import filepath "core:path/filepath"

ProcedureExport :: struct {
    name: string,
    lua_name: string,
    result_types: []string,
    result_names: []string,
    param_types: []string,
    param_names: []string,
    attrib_names: []string,
    attrib_values: []string,
}

SymbolExport :: union {
    ProcedureExport,
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
    result.imports = make(map[string]FileImport)
    return result
}

file_exports_destroy :: proc(obj: ^FileExports) {
    // Note(Dragos): Taken from string builder, shouldn't it be reversed?
    delete(obj.symbols)
    clear(&obj.symbols)
}

parse_symbols :: proc(fileName: string) -> (symbol_exports: FileExports) {
    using fmt
    
    data, ok := os.read_entire_file(fileName);
    if !ok {
        fprintf(os.stderr, "Error reading the file\n")
    }

    p := parser.Parser{}
    p.flags += {parser.Flag.Optional_Semicolons}
    p.err = proc(pos: tokenizer.Pos, fmt: string, args: ..any) {
        printf(fmt, args)
        printf("\n")
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
                fmt.printf("ImportName: %s\n", importName)
                fmt.printf("Import: %s\n", root.src[x.pos.offset : x.end.offset])
        
            }
        }

        if decl, ok := x.derived.(^ast.Value_Decl); ok {
            if len(decl.attributes) < 1 do continue // No attributes here, move on

            // Get the identifier
            declName := decl.names[0].derived.(^ast.Ident).name
            exportResult : SymbolExport
            #partial switch v in decl.values[0].derived {
                case ^ast.Proc_Lit: {
                    // Get the type
                    procType := v.type
                    exportProc := ProcedureExport{}
                    //printf("DeclName: %s\n", declName)

                    // Put single and multi attributes the same slice (multiple @ vs comma separated)
                    nAttribs := 0
                    for attr in decl.attributes {
                        nAttribs += len(attr.elems)
                    }
                    nParams := len(procType.params.list)
                    nResults := len(procType.results.list)
                    exportProc.name = declName

                    // Note(Dragos): these should be checked for 0
                    exportProc.param_names = make([]string, nParams)
                    exportProc.param_types = make([]string, nParams)
                    exportProc.result_names = make([]string, nResults)
                    exportProc.result_types = make([]string, nResults)
                    exportProc.attrib_names = make([]string, nAttribs)
                    exportProc.attrib_values = make([]string, nAttribs)

                    // Get attributes
                    for attr, i in decl.attributes {
                        for x, j in attr.elems {
                            attrName, attrVal := get_attr_elem(x)
                            if attrName == "lua_export" {
                                exportProc.lua_name = attrVal
                            }
                            attrIndex := i * len(decl.attributes) + j
                            exportProc.attrib_names[attrIndex] = attrName
                            exportProc.attrib_values[attrIndex] = attrVal
                            //printf("(Attribute : Value) -> (%s : %s)\n", attrName, attrVal)
                        }   
                    }

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
                                printf("ParamType: %s\n", paramType)
                            }
                        }
                        
                        exportProc.param_names[i] = paramName
                        exportProc.param_types[i] = paramType
                        
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
                                printf("ResType: %s\n", resType)
                            }
                        }
                        if len(rval.names) == 0 || resName == resType {
                            // Result name is not specified
                            sb := strings.builder_make(context.temp_allocator)
                            strings.write_string(&sb, "mani_result")
                            strings.write_int(&sb, i)
                            resName = strings.to_string(sb)
                        }
                        
                        
                        exportProc.result_names[i] = resName
                        exportProc.result_types[i] = resType
                        //printf("(ResultName : ResultType) -> (%s, %s)\n", resName, resType)
                    }

                    append(&symbol_exports.symbols, exportProc) // Add the function to the results
                }
            }

         
        }
    }

    return
}


get_attr_elem :: proc(elem: ^ast.Expr) -> (name: string, value: string) {
    #partial switch x in elem.derived  {
        case ^ast.Field_Value: {
            attr := x.field.derived.(^ast.Ident)
            attrVal := x.value.derived.(^ast.Basic_Lit) 
            name = attr.name
            value = strings.trim(attrVal.tok.text, "\"")
        }

        case ^ast.Ident: {
            name = x.name
        }
    }
    return
}

print_symbol :: proc(symbol: SymbolExport) {
    using fmt
    
    switch s in symbol {
        case ProcedureExport: {
            printf("ProcName: %s\n", s.name)

            for name, i in s.attrib_names {
                printf("(AttribName : AttribValue) -> (%s, %s)\n", name, s.attrib_values[i])
            }

            for name, i in s.param_names {
                printf("(ParamName : ParamType) -> (%s, %s)\n", name, s.param_types[i])
            }

            for name, i in s.result_names {
                printf("(ResultName : ResultTypes) -> (%s, %s)\n", name, s.result_types[i])
            }
        }
    }
}

