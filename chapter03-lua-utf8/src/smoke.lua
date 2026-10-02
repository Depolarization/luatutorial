-- smoke.lua : 最小冒烟，确认库装得上、几个关键值对得上
local ok, U = pcall(require, "utf8lite")
if not ok then error(U) end

local function nums(t)
  local o = {}
  for k = 1, #t do o[k] = tostring(t[k]) end
  return table.concat(o, ",")
end

print("_VERSION       :", _VERSION, "| 原生 utf8 :", type(utf8))
print("len('a中b')    :", U.len("a中b"), " (期望 3)")
print("字节数 #'a中b' :", #"a中b", " (期望 5)")
local cps = {}
for _, cp in U.codes("a中b") do cps[#cps + 1] = cp end
print("codes          :", nums(cps), " (期望 97,20013,98)")
print("sub(2,2)       :", U.escape(U.sub("a中b", 2, 2)), " (期望 \\u{4E2D})")
print("reverse        :", U.escape(U.reverse("a中b")), " (期望 中 在前)")
print("fit(s,3)       :", U.escape((U.fit("a中bc", 3))), "| 字节", #(U.fit("a中bc", 3)))
print("check 正常     :", U.check("正常text"))
print("check 半个字   :", U.check("\228\184"))
print("char(0x1F600)  :", U.escape(U.char(0x1F600)), "| 字节", #U.char(0x1F600))
print("offset(3)      :", U.offset("a中b", 3), "| offset(0,3) :", U.offset("a中b", 0, 3))
print("第 2 个字符    :", U.escape(U.nth("a中b", 2)))
