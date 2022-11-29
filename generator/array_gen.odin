package mani_generator

import "core:fmt"
import "core:strings"
import codew "code_writer"

write_lua_array_index :: proc(sb: ^strings.Builder, exports: FileExports, arr: ArrayExport) {
    using strings, fmt
    writer := codew.writer_make(sb)
    exportAttrib := arr.attribs["LuaExport"].(Attributes)
    luaName := exportAttrib["Name"].(String) or_else arr.name

    udataTypeAttrib := exportAttrib["Type"].(Attributes)  
    allowLight := "Light" in udataTypeAttrib
    allowFull := "Full" in udataTypeAttrib
    UdataType :: enum {
        Light = 0,
        Full,
    }
    udataType := [UdataType]bool {
        .Light = allowLight, 
        .Full = allowFull,
    }

    swizzleTypes := exportAttrib["SwizzleTypes"].(Attributes) 
    allowedFields := cast(string)exportAttrib["Fields"].(Identifier)
    hasMethods := "Methods" in exportAttrib
    //0: Arr2
    //1: Arr3 
    //2: Arr4
    arrayTypes: [3]ArrayExport
    for typename in swizzleTypes {
        type := exports.symbols[typename].(ArrayExport)
        arrayTypes[type.len - 2] = type
    }
    arrayTypes[arr.len - 2] = arr

    if allowFull {
        
        if hasMethods {
            sbprintf(sb,
                `
_mani_index_{0:s} :: proc "c" (L: ^lua.State) -> c.int {{

    context = mani.default_context()
    udata: {0:s}
    mani.to_value(L, 1, &udata)
    // Note(Dragos): It should also accept indices
    key := lua.tostring(L, 2)
    if method, found := _mani_methods_{0:s}[key]; found {{
        mani.push_value(L, method)
        return 1
    }}
    assert(len(key) <= 4, "Vectors can only be swizzled up to 4 elements")

    result: {1:s} // Highest possible array type
    for r, i in key {{
        if idx := strings.index_rune("{3:s}", r); idx != -1 {{
            arrIdx := idx %% {2:i}
            result[i] = udata[arrIdx]
        }}
    }}

    switch len(key) {{
        case 1: {{
            mani.push_value(L, result.x)
        }}

        case 2: {{
            mani.push_value(L, result.xy)
        }}

        case 3: {{
            mani.push_value(L, result.xyz)
        }}

        case 4: {{
            mani.push_value(L, result)
        }}

        case: {{
            lua.pushnil(L)
        }}
    }}

    return 1
}}
            `, arr.name, arrayTypes[2].name, arr.len, allowedFields)
        } else {
            sbprintf(sb,
                `
_mani_index_{0:s} :: proc "c" (L: ^lua.State) -> c.int {{

    context = mani.default_context()
    udata: {0:s}
    mani.to_value(L, 1, &udata)
    // Note(Dragos): It should also accept indices
    key := lua.tostring(L, 2)
    
    assert(len(key) <= 4, "Vectors can only be swizzled up to 4 elements")

    result: {1:s} // Highest possible array type
    for r, i in key {{
        if idx := strings.index_rune("{3:s}", r); idx != -1 {{
            arrIdx := idx %% {2:i}
            result[i] = udata[arrIdx]
        }}
    }}

    switch len(key) {{
        case 1: {{
            mani.push_value(L, result.x)
        }}

        case 2: {{
            mani.push_value(L, result.xy)
        }}

        case 3: {{
            mani.push_value(L, result.xyz)
        }}

        case 4: {{
            mani.push_value(L, result)
        }}

        case: {{
            lua.pushnil(L)
        }}
    }}

    return 1
}}
            `, arr.name, arrayTypes[2].name, arr.len, allowedFields)
        }
        
    }

    if allowLight {
        if hasMethods {
            sbprintf(sb,
                `
_mani_index_{0:s}_ref :: proc "c" (L: ^lua.State) -> c.int {{

    context = mani.default_context()
    udata: ^{0:s}
    mani.to_value(L, 1, &udata)
    // Note(Dragos): It should also accept indices
    key := lua.tostring(L, 2)
    if method, found := _mani_methods_{0:s}[key]; found {{
        mani.push_value(L, method)
        return 1
    }}
    assert(len(key) <= 4, "Vectors can only be swizzled up to 4 elements")

    result: {1:s} // Highest possible array type
    for r, i in key {{
        if idx := strings.index_rune("{3:s}", r); idx != -1 {{
            arrIdx := idx %% {2:i}
            result[i] = udata[arrIdx]
        }}
    }}

    switch len(key) {{
        case 1: {{
            mani.push_value(L, result.x)
        }}

        case 2: {{
            mani.push_value(L, result.xy)
        }}

        case 3: {{
            mani.push_value(L, result.xyz)
        }}

        case 4: {{
            mani.push_value(L, result)
        }}

        case: {{
            lua.pushnil(L)
        }}
    }}

    return 1
}}
            `, arr.name, arrayTypes[2].name, arr.len, allowedFields)
        } else {
            sbprintf(sb,
                `
    _mani_index_{0:s}_ref :: proc "c" (L: ^lua.State) -> c.int {{
    
        context = mani.default_context()
        udata: ^{0:s}
        mani.to_value(L, 1, &udata)
        // Note(Dragos): It should also accept indices
        key := lua.tostring(L, 2)
        
        assert(len(key) <= 4, "Vectors can only be swizzled up to 4 elements")
    
        result: {1:s} // Highest possible array type
        for r, i in key {{
            if idx := strings.index_rune("{3:s}", r); idx != -1 {{
                arrIdx := idx %% {2:i}
                result[i] = udata[arrIdx]
            }}
        }}
    
        switch len(key) {{
            case 1: {{
                mani.push_value(L, result.x)
            }}
    
            case 2: {{
                mani.push_value(L, result.xy)
            }}
    
            case 3: {{
                mani.push_value(L, result.xyz)
            }}
    
            case 4: {{
                mani.push_value(L, result)
            }}
    
            case: {{
                lua.pushnil(L)
            }}
        }}
    
        return 1
    }}
            `, arr.name, arrayTypes[2].name, arr.len, allowedFields)
        }
    }
    
}

write_lua_array_newindex :: proc(sb: ^strings.Builder, exports: FileExports, arr: ArrayExport) {
    using strings, fmt
    
    exportAttrib := arr.attribs["LuaExport"].(Attributes)
    luaName := exportAttrib["Name"].(String) or_else arr.name
    udataType := exportAttrib["Type"].(Attributes)
    allowLight := "Light" in udataType
    allowFull := "Full" in udataType
    swizzleTypes := exportAttrib["SwizzleTypes"].(Attributes) 
    allowedFields := cast(string)exportAttrib["Fields"].(Identifier)
    
    //0: Arr2
    //1: Arr3 
    //2: Arr4
    arrayTypes: [3]ArrayExport
    for typename in swizzleTypes {
        type := exports.symbols[typename].(ArrayExport)
        arrayTypes[type.len - 2] = type
    }
    arrayTypes[arr.len - 2] = arr

    if allowFull {
        sbprintf(sb,
            `
_mani_newindex_{0:s} :: proc "c" (L: ^lua.State) -> c.int {{

    context = mani.default_context()
    udata: {0:s} 
    mani.to_value(L, 1, &udata)
    // Note(Dragos): It should also accept indices
    key := lua.tostring(L, 2)
    assert(len(key) <= {1:d}, "Cannot assign more indices than the vector takes")

    switch len(key) {{
        case 1: {{
            val: {2:s} 
            mani.to_value(L, 3, &val.x)
            
            if idx := strings.index_byte("{5:s}", key[0]); idx != -1 {{
                arrIdx := idx %% {1:d}
                udata[arrIdx] = val.x
            }}
        }

        case 2: {{
            val: {2:s}
            mani.to_value(L, 3, &val)
            for r, i in key {{
                if idx := strings.index_rune("{5:s}", r); idx != -1 {{
                    arrIdx := idx %% {1:d}
                    udata[arrIdx] = val[i]
                }}
            }}
        }}

        case 3: {{
            val: {3:s}
            mani.to_value(L, 3, &val)
            for r, i in key {{  
                if idx := strings.index_rune("{5:s}", r); idx != -1 {{
                    arrIdx := idx %% {1:d}
                    udata[arrIdx] = val[i]
                }}
            }}
        }}

        case 4: {{
            val: {4:s}
            mani.to_value(L, 3, &val)
            for r, i in key {{                   
                if idx := strings.index_rune("{5:s}", r); idx != -1 {{
                    arrIdx := idx %% {1:d}
                    udata[arrIdx] = val[i]
                }}
            }}
        }}
    }}


    return 0
}}
        `, arr.name, arr.len, arrayTypes[0].name, arrayTypes[1].name, arrayTypes[2].name, allowedFields)
    }

    if allowLight {
        sbprintf(sb,
            `
_mani_newindex_{0:s}_ref :: proc "c" (L: ^lua.State) -> c.int {{

    context = mani.default_context()
    udata: ^{0:s} 
    mani.to_value(L, 1, &udata)
    // Note(Dragos): It should also accept indices
    key := lua.tostring(L, 2)
    assert(len(key) <= {1:d}, "Cannot assign more indices than the vector takes")

    switch len(key) {{
        case 1: {{
            val: {2:s} 
            mani.to_value(L, 3, &val.x)      
            if idx := strings.index_byte("{5:s}", key[0]); idx != -1 {{
                arrIdx := idx %% {1:d}
                udata[arrIdx] = val.x
            }}
        }

        case 2: {{
            val: {2:s}
            mani.to_value(L, 3, &val)
            for r, i in key {{
                if idx := strings.index_rune("{5:s}", r); idx != -1 {{
                    arrIdx := idx %% {1:d}
                    udata[arrIdx] = val[i]
                }}
            }}
        }}

        case 3: {{
            val: {3:s}
            mani.to_value(L, 3, &val)    
            for r, i in key {{   
                if idx := strings.index_rune("{5:s}", r); idx != -1 {{
                    arrIdx := idx %% {1:d}
                    udata[arrIdx] = val[i]
                }}
            }}
        }}

        case 4: {{
            val: {4:s}
            mani.to_value(L, 3, &val)
            for r, i in key {{                   
                if idx := strings.index_rune("{5:s}", r); idx != -1 {{
                    arrIdx := idx %% {1:d}
                    udata[arrIdx] = val[i]
                }}
            }}
        }}
    }}


    return 0
}}
        `, arr.name, arr.len, arrayTypes[0].name, arrayTypes[1].name, arrayTypes[2].name, allowedFields)
    }

}


write_lua_array_init :: proc(sb: ^strings.Builder, exports: FileExports, arr: ArrayExport) {
    using strings, fmt

    exportAttribs := arr.attribs[LUAEXPORT_STR].(Attributes)
    udataType := exportAttribs["Type"].(Attributes)  
    allowLight := "Light" in udataType
    allowFull := "Full" in udataType
    
    luaName := exportAttribs["Name"].(String) or_else arr.name


    write_string(sb, "@(init)\n")
    write_string(sb, "_mani_init_")
    write_string(sb, arr.name)
    write_string(sb, " :: proc() {\n    ")

    write_string(sb, "expStruct: mani.StructExport")
    write_string(sb, "\n    ")
    write_string(sb, "expStruct.pkg = ")
    write_rune(sb, '"')
    write_string(sb, exports.symbols_package)
    write_rune(sb, '"')
    write_string(sb, "\n    ")

    write_string(sb, "expStruct.odin_name = ")
    write_rune(sb, '"')
    write_string(sb, arr.name)
    write_rune(sb, '"')
    write_string(sb, "\n    ")

    write_string(sb, "expStruct.lua_name = ")
    write_rune(sb, '"')
    write_string(sb, luaName)
    write_rune(sb, '"')
    write_string(sb, "\n    ")

    write_string(sb, "expStruct.type = ")
    write_string(sb, arr.name)
    write_string(sb, "\n    ")
    
    if methodsAttrib, found := exportAttribs["Methods"]; found {
        write_string(sb, "expStruct.methods = make(map[mani.LuaName]lua.CFunction)")
        write_string(sb, "\n    ")
        methods := methodsAttrib.(Attributes) 
        for odinName, attribVal in methods {
            luaName: string
            if name, ok := attribVal.(String); ok {
                luaName = name
            } else {
                luaName = odinName
            }
            fullName := strings.concatenate({"_mani_", odinName}, context.temp_allocator)
            write_string(sb, "expStruct.methods[")
            write_rune(sb, '"')
            write_string(sb, luaName)
            write_rune(sb, '"')
            write_string(sb, "] = ")
            write_string(sb, fullName)
            write_string(sb, "\n    ")
        }
        
    }

    if allowLight {
        write_string(sb, "\n    ")
        write_string(sb, "refMeta: mani.MetatableData\n    ")
        write_string(sb, "refMeta.name = ")
        write_rune(sb, '"')
        write_string(sb, arr.name)
        write_string(sb, "_ref")
        write_rune(sb, '"')
        write_string(sb, "\n    ")

        write_string(sb, "refMeta.odin_type = ")
        write_rune(sb, '^')
        write_string(sb, arr.name)
        write_string(sb, "\n    ")

        write_string(sb, "refMeta.index = ")
        write_string(sb, "_mani_index_")
        write_string(sb, arr.name)
        write_string(sb, "_ref")
        write_string(sb, "\n    ")

        write_string(sb, "refMeta.newindex = ")
        write_string(sb, "_mani_newindex_")
        write_string(sb, arr.name)
        write_string(sb, "_ref")
        write_string(sb, "\n    ")

        if metaAttrib, found := exportAttribs["Metamethods"]; found {
            write_string(sb, "refMeta.methods = make(map[cstring]lua.CFunction)")
            write_string(sb, "\n    ")
            methods := metaAttrib.(Attributes)
            for name, val in methods {
                odinProc := val.(Identifier)
                fmt.sbprintf(sb, "refMeta.methods[\"%s\"] = _mani_%s", name, cast(String)odinProc)
                write_string(sb, "\n    ")
            }
        }


        write_string(sb, "expStruct.light_meta = refMeta")
        write_string(sb, "\n    ")
    }

    if allowFull {
        write_string(sb, "\n    ")
        write_string(sb, "copyMeta: mani.MetatableData\n    ")
        write_string(sb, "copyMeta.name = ")
        write_rune(sb, '"')
        write_string(sb, arr.name)
        write_rune(sb, '"')
        write_string(sb, "\n    ")

        write_string(sb, "copyMeta.odin_type = ")
        write_string(sb, arr.name)
        write_string(sb, "\n    ")

        write_string(sb, "copyMeta.index = ")
        write_string(sb, "_mani_index_")
        write_string(sb, arr.name)
        write_string(sb, "\n    ")

        write_string(sb, "copyMeta.newindex = ")
        write_string(sb, "_mani_newindex_")
        write_string(sb, arr.name)
        write_string(sb, "\n    ")

        if metaAttrib, found := exportAttribs["Metamethods"]; found {
            write_string(sb, "copyMeta.methods = make(map[cstring]lua.CFunction)")
            write_string(sb, "\n    ")
            methods := metaAttrib.(Attributes)
            for name, val in methods {
                odinProc := val.(Identifier)
                fmt.sbprintf(sb, "copyMeta.methods[\"%s\"] = _mani_%s", name, cast(String)odinProc)
                write_string(sb, "\n    ")
            }
        }

        write_string(sb, "expStruct.full_meta = copyMeta")
        write_string(sb, "\n    ")
        write_string(sb, "\n    ")

    }

   
    
    write_string(sb, "mani.add_struct(expStruct)")
    write_string(sb, "\n}\n\n")
}
