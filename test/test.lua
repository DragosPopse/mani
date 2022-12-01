
-- lua
local v = make_vec4(10, 2, 3, 4)

print(tostring(v.xy))
print(tostring(v.yxx))
print("Lua: " .. tostring(g_vec))
g_vec.xyz = v.xxx
