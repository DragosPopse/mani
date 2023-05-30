package test
import "core:runtime"
import "subpackage"

ignored_proc :: proc() {

}

@(attrib_something)
Test_Struct :: struct {
    a: int,
    b: string,
}

@(attrib_bool = true, attrib_object = {
    bool_in_object = true,
})
test_proc_1 :: proc(arg1: int, arg2: f32) -> (res1: bool, res2: int) {
    return
}

@(this_needs_to_work)
_ :: subpackage.proc_test

main :: proc() {

}

