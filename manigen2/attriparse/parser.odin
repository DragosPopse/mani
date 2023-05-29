package attriparse

import ast "core:odin/ast"
import parser "core:odin/parser"
import tokenizer "core:odin/tokenizer"
import "core:strings"
import "core:fmt"

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

Symbol :: struct {
    attribs: Attribute_Map,
    var: union {
        Struct,
        Proc,
        Array,
    },
}

Attribute_Map :: distinct map[string]Attribute_Value

Parser :: struct {
    parser: parser.Parser,
    src_pkg: ^ast.Package,
    collections: map[string]string,
    allowed_attributes: map[string]bool,
    symbols: map[string]Symbol,
}

parser_init :: proc(p: ^Parser, allowed_attributes: []string) {
    p.parser = parser.default_parser()
    for attrib in allowed_attributes {
        key := strings.clone(attrib)
        p.allowed_attributes[key] = true
    }

    for attrib in BUILTIN_ATTRIBUTES {
        key := strings.clone(attrib)
        p.allowed_attributes[key] = true
    }

    p.collections["core"] = fmt.aprintf("%s/core\n", ODIN_ROOT)
}

is_attribute_valid :: #force_inline proc(p: ^Parser, attrib: string) -> (valid: bool) {
    return attrib in p.allowed_attributes
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

parse_package :: proc(p: ^Parser, path: string) {
    pkg_collected: bool
    p.src_pkg, pkg_collected = parser.collect_package(path)
    assert(pkg_collected, "Package collection failed.")
    parser.parse_package(p.src_pkg, &p.parser)
    for filename, file in p.src_pkg.files {
        root := file
        for decl, index in root.decls {
            #partial switch derived in decl.derived {
                case ^ast.Import_Decl: {

                }
            }
            if value_decl, is_value_decl := decl.derived.(^ast.Value_Decl); is_value_decl {
                if len(value_decl.attributes) < 1 do continue

                #partial switch value in value_decl.values[0].derived {
                    case ^ast.Distinct_Type: { // This needs to be sorted out

                    }

                    case ^ast.Proc_Lit: {

                    }

                    case ^ast.Struct_Type: {

                    }

                    case ^ast.Array_Type: {

                    }
                }
            }
        }
    }
}