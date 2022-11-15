print("Whatsup")

obj = make_object(23)

print_object(obj)

mod_object(obj)  --bad argument #1 to 'mod_object' (HalfObject_ref expected, got HalfObject) 
-- Maybe there is no requirement for using a ^Obj metatable when checking to_value