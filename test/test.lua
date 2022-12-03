
-- lua
local v = make_vec4(10, 2, 3, 4)

print(tostring(v.xy))
print(tostring(v.yxx))
print("Lua: " .. tostring(g_vec))
g_vec.xyz = v.xxx

v.xxx = v.xyz 
local v = make_object(2)
v:mod(2)

function update(dt) 
    print("Running Update with " .. dt)
    return 1, 2
end