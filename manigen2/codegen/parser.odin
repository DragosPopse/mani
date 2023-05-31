package attriparse

import ast "core:odin/ast"
import parser "core:odin/parser"
import tokenizer "core:odin/tokenizer"
import "core:strings"
import "core:fmt"
import "core:strconv"
import "core:path/filepath"

BUILTIN_ATTRIBUTES := [?]string {
    "private",
    "require",
    "link_name",
    "link_prefix",
    "export",
    "linkage",
    "default_calling_convention",
    "link_section",
    "extra_linker_flags",
    "deferred_in",
    "deferred_out",
    "deferred_in_out",
    "deferred_none",
    "deprecated",
    "require_results",
    "warning",
    "disabled",
    "init",
    "cold",
    "optimization_mode",
    "static",
    "thread_local",
    "builtin",
    "objc_name",
    "objc_type",
    "objc_is_class_method",
    "require_target_feature",
    "enable_target_feature",
}


String :: string
Identifier :: distinct String
Int :: int
Float :: f32

Attribute_Value :: union {
    // nil: empty attribute, like a flag, array element, etc
    String,
    Identifier,
    Int,
    Attribute_Map,
}

Field :: struct {
    name: string,
    type: string,
}

Struct :: struct {
    fields: [dynamic]Field,
}

Proc :: struct {
    type: string,
    calling_convention: string,
    params: [dynamic]Field,
    results: [dynamic]Field,
}

Array :: struct {
    len: int,
    value_type: string,
}

External_Symbol :: struct {
    pkg_path: string,
    ident: string,
    pkg: string, // lazily evaluated
}


Symbol :: struct {
    attribs: Attribute_Map,
    is_distinct: bool,
    var: union {
        Struct,
        Proc,
        Array,
        External_Symbol, // This might not be needed
        // A symbol can also be a primitive
    },
}


Attribute_Map :: distinct map[string]Attribute_Value

Program :: struct {
    root_pkg: ^ast.Package,
    parser: parser.Parser,
    collections: map[string]string,
    pkgs: map[string]^ast.Package,
    symbols: map[string]Symbol,
}

// Parse all imports first as packages, do it recursively no?
parse_package :: proc(p: ^Program, path: string) {
    fmt.printf("Trying to parse path: %v\n", path)
    path := make_import_path(p, path)
    fmt.printf("Making import path %v\n", path)
    pkg, pkg_collected := parser.collect_package(path)

    assert(pkg_collected, "Package collection failed.")
    pkg_parsed := parser.parse_package(pkg, &p.parser)
    fmt.assertf(pkg_parsed, "Failed to parse package at path %v\n", pkg.fullpath)
    if pkg.name in p.pkgs {
        return // already parsed
    }
    p.pkgs[pkg.name] = pkg
    fmt.printf("Found package %v\n", pkg.name)
    for filename, file in pkg.files {
        root := file
        for decl, index in root.decls {
            #partial switch derived in decl.derived {
                case ^ast.Import_Decl: {
                    import_name: string
                    parse_package(p, strings.trim(derived.fullpath, "\""))
                    import_text := root.src[derived.pos.offset : derived.end.offset]
                    
                    if derived.name.kind != .Invalid {
                        // got a name
                        import_name = derived.name.text
                    } else {
                        // Take the name from the path
                        start_pos := 0
                        for c, i in derived.fullpath {
                            if c == ':' {
                                start_pos = i + 1
                                break
                            }
                        }
                        // Use the last folder
                        split := strings.split(derived.fullpath[start_pos:], "/", context.temp_allocator)
                        import_name = split[len(split) - 1]
                        import_name = strings.trim(import_name, "\"")
                    }
                }
            }
        }
    }
}

parse_program :: proc(program: ^Program, root_path: string) {
    program.parser = parser.default_parser({.Optional_Semicolons, .Allow_Reserved_Package_Name}) 
    parse_package(program, root_path)
}

make_import_path :: proc(p: ^Program, path: string, allocator := context.allocator) -> (result: string) {
    parts := strings.split(path, ":", context.temp_allocator)
    collection_path := "./"
    pkg_path := ""
    if len(parts) == 2 { // we have a collection thing
        assert(parts[0] in p.collections, "Collection not found.")
        collection_path = p.collections[parts[0]]
        pkg_path = parts[1]
    } else {
        pkg_path = parts[0]
    }
    return filepath.join({collection_path, pkg_path}, allocator)
}

print_program_data :: proc(p: ^Program) {
    fmt.printf("Packages:\n")
    for name, pkg in p.pkgs {
        fmt.printf("%v\n", name)
    }
    fmt.printf("\n")
    for name, symbol in p.symbols {
        fmt.printf("Symbol: %v\n", name)
        fmt.printf("distinct: %v\n", symbol.is_distinct)
        fmt.printf("Attribs: %v\n", symbol.attribs)
        switch var in symbol.var {
            case Struct: {
                fmt.printf("Variant: Struct\n")
                fmt.printf("Fields: %v\n", var.fields)
            }

            case Proc: {
                fmt.printf("Variant: Proc\n")
                fmt.printf("Type: %v\n", var.type)
                fmt.printf("Params: %v\n", var.params)
                fmt.printf("Results: %v\n", var.results)
            }

            case Array: {
                fmt.printf("Variant: Array\n")
                fmt.printf("Length: %v\n", var.len)
                fmt.printf("Value Type: %v\n", var.value_type)
            }

            case External_Symbol: {
                fmt.printf("Variant: External Symbol\n")
                fmt.printf("Package: %v\n", var.pkg_path)
                fmt.printf("Identifier: %v\n", var.ident)
            }
        }

        fmt.printf("\n")
    }
}

parse_attributes :: proc(root: ^ast.File, value_decl: ^ast.Value_Decl) -> (result: Attribute_Map) {
    result = make(Attribute_Map)
    for attr, i in value_decl.attributes {
        for x, j in attr.elems { 
            name := get_attr_name(root, x)
            
            result[name] = parse_attrib_val(root, x)
        }
        
    }
    return
}

parse_attrib_object :: proc(root: ^ast.File, obj: ^ast.Comp_Lit) -> (result: Attribute_Map) {
    result = make(Attribute_Map)
    for elem, i in obj.elems {
        name := get_attr_name(root, elem)
        result[name] = parse_attrib_val(root, elem)
    }
    return
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

parse_attrib_val :: proc(root: ^ast.File, elem: ^ast.Expr) -> (result: Attribute_Value) {
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
            //fmt.printf("Found identifier %v\n", x)
            return nil
        }

        case ^ast.Comp_Lit: {
            //result = parse_attrib_object(root, x)
            //fmt.printf("We shouldn't be in comp literal %v\n", x)
            return nil
        }
    }
    return nil
}

// This needs to be remade
parse_external_symbol :: proc(p: ^Program, root: ^ast.File, value_decl: ^ast.Value_Decl, ext_decl: ^ast.Selector_Expr) -> (result: Symbol, name: string) {
    result.attribs = parse_attributes(root, value_decl)
    result.var = External_Symbol{}
    var_external := &result.var.(External_Symbol)
    name = value_decl.names[0].derived.(^ast.Ident).name
    pkg := ext_decl.expr.derived.(^ast.Ident).name
    //var_external.pkg_path = p.imports_alias_path_mapping[pkg]
     // This might crash in some conditions
     // This is also a bit weird... We'll need to test further
    var_external.ident = root.src[ext_decl.op.pos.offset + 1 : ext_decl.expr_base.end.offset]
    //fmt.printf("Selector expr: %v\n", ext_decl)
    
    return
}

parse_array :: proc(root: ^ast.File, value_decl: ^ast.Value_Decl, arr_decl: ^ast.Array_Type) -> (result: Symbol, name: string) {
    result.attribs = parse_attributes(root, value_decl)
    result.var = Array{}
    var_array := &result.var.(Array)
    name = value_decl.names[0].derived.(^ast.Ident).name
    var_array.value_type = arr_decl.elem.derived.(^ast.Ident).name
    lenLit := arr_decl.len.derived.(^ast.Basic_Lit)
    lenStr := root.src[lenLit.pos.offset : lenLit.end.offset]
    var_array.len, _ = strconv.parse_int(lenStr)
    
    return
}

parse_struct :: proc(root: ^ast.File, value_decl: ^ast.Value_Decl, struct_decl: ^ast.Struct_Type) -> (result: Symbol, name: string) {
    result.attribs = parse_attributes(root, value_decl)
    result.var = Struct{}
    var_struct := &result.var.(Struct)
    name = value_decl.names[0].derived.(^ast.Ident).name
    //result.fields = make(map[string]Field) 
    
    for field in struct_decl.fields.list {
        
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
        for name in field.names {
            fName := name.derived.(^ast.Ident).name 
            append(&var_struct.fields, Field {
                name = fName,
                type = fType,
            })
        }
        
    }

    return
}


parse_proc :: proc(root: ^ast.File, value_decl: ^ast.Value_Decl, proc_lit: ^ast.Proc_Lit) -> (result: Symbol, name: string) {
 
    //result.properties, err = parse_properties(root, value_decl)
    result.attribs = parse_attributes(root, value_decl)
    result.var = Proc{}
    var_proc := &result.var.(Proc)
    v := proc_lit
    procType := v.type
    declName := value_decl.names[0].derived.(^ast.Ident).name // Note(Dragos): Does this work with 'a, b: int' ?????

    name = declName
    var_proc.type = root.src[procType.pos.offset : procType.end.offset]
    switch conv in procType.calling_convention {
        case string: {
            var_proc.calling_convention = strings.trim(conv, `"`)
        }

        case ast.Proc_Calling_Convention_Extra: {
            var_proc.calling_convention = "c" //not fully correct
        }

        case: { // nil, default calling convention
            var_proc.calling_convention = "odin"
        }
    }
    // Note(Dragos): these should be checked for 0
    
    
    var_proc.params = make(type_of(var_proc.params))
    var_proc.results = make(type_of(var_proc.results))
    // Get parameters
    if procType.params != nil {
        
        for param, i in procType.params.list {
            paramType: string
            #partial switch x in param.type.derived {
                case ^ast.Ident: {
                    paramType = x.name
                }
                case ^ast.Selector_Expr: {
                    paramType = root.src[x.pos.offset : x.end.offset] //godlike odin
                }
                case ^ast.Pointer_Type: {
                    paramType = root.src[x.pos.offset : x.end.offset]
                }
            }

            for name in param.names {
                append(&var_proc.params, Field{
                    name = name.derived.(^ast.Ident).name, 
                    type = paramType,
                })
            }         
        }
    }
    
    // Get results
    if procType.results != nil {
        for rval, i in procType.results.list {
            resName: string
            resType: string
            #partial switch x in rval.type.derived {
                case ^ast.Ident: {
                    resType = x.name
                    if len(rval.names) != 0 {
                        resName = rval.names[0].derived.(^ast.Ident).name
                    }
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
            
    

            append(&var_proc.results, Field{
                name = resName, 
                type = resType,
            })
        }
    }

    
    return
}