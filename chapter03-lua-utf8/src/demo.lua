--[[
  demo.lua —— 演示脚本，输出会被搬到视频的「运行结果」面板
  同一份文件在 Lua 5.1.5 / fengari(5.3) / Lua 5.4.8 上跑，结果应当一致
  （只有第 8 节「版本差异」按解释器如实打印）。
]]
local U = require("utf8lite")
local concat = table.concat

local esc = U.escape          -- 面板里绝不打印原始字节，一律转义

local function width(cp)
  return cp < 0x80 and 1 or cp < 0x800 and 2 or cp < 0x10000 and 3 or 4
end

local function bytelist(s)
  local o = {}
  for k = 1, #s do o[k] = s:byte(k) end
  return concat(o, " ")
end

print("== 1. # 数的是字节，不是字符 ==")
local samples = {"Hello, 世界", "a中b", "😀😀", "Ω≈ç√∫"}
for k = 1, #samples do
  local s, lo, hi = samples[k], 9, 0
  for _, cp in U.codes(s) do
    local w = width(cp)
    if w < lo then lo = w end
    if w > hi then hi = w end
  end
  print(string.format("%-14s #=%-3d 字符=%-3d 单字符字节 %d..%d", s, #s, U.len(s), lo, hi))
end

print("")
print("== 2. string.sub 按字节切：切半个字就是乱码 ==")
local s = "Hello, 世界"                       -- 13 字节，「世」占 3 字节
print("整串           : " .. esc(s) .. "   (" .. #s .. " 字节 / " .. U.len(s) .. " 字符)")
print("sub(s,1,9)     : " .. esc(s:sub(1, 9)))
print("sub(s,1,12)    : " .. esc(s:sub(1, 12)) .. "   <- 切在「界」中间")
print("U.sub(s,1,8)   : " .. esc(U.sub(s, 1, 8)) .. "   <- 按字符切")
print("U.sub(s,8,8)   : " .. esc(U.sub(s, 8, 8)))
print("U.sub(s,-2,-1) : " .. esc(U.sub(s, -2, -1)))
print("前半是否合法 UTF-8 : sub=" .. tostring(U.check(s:sub(1, 12)))
      .. "   U.sub=" .. tostring(U.check(U.sub(s, 1, 8))))

print("")
print("== 3. 逐字符遍历：字节位置 + 码点 + 占几字节 ==")
local mix, k, pos = "a中😀", 0, 1
while pos <= #mix do
  local cp, nxt = U.decode(mix, pos, true)
  k = k + 1
  print(string.format("  第 %d 个字符: 位置 %d -> U+%04X  占 %d 字节  %s",
    k, pos, cp, nxt - pos, mix:sub(pos, nxt - 1)))
  pos = nxt
end
print("反转           : " .. U.reverse(mix))
local back = {}
for _, cp in U.codes(mix) do back[#back + 1] = U.char(cp) end
print("码点全部回编码   : " .. concat(back) .. "   等于原串 = "
      .. tostring(concat(back) == mix))

print("")
print("== 4. 非法 UTF-8 判定矩阵（返回出错位置与原因）==")
local bads = {
  {"落单的续字节 80",      "\128"},
  {"截断的二字节 C2",       "\194"},
  {"截断的三字节 E4 B8",    "\228\184"},
  {"超长编码 C0 80",       "\192\128"},
  {"代理区 ED A0 80",      "\237\160\128"},
  {"超出 U+10FFFF F4 90",  "\244\144\128\128"},
  {"五字节头 F8",          "\248\159\152\136"},
  {"非法首字节 FE",         "\254"},
  {"串里混入 FF",          "中\255文"},
}
for j = 1, #bads do
  local label, b = bads[j][1], bads[j][2]
  local ok, p, why = U.check(b)
  local l, epos = U.len(b)
  print(string.format("  %-20s check=%-5s 位置=%-3s 原因=%-12s len=%s@%s",
    label, tostring(ok), tostring(p), tostring(why), tostring(l), tostring(epos)))
end

print("")
print("== 5. 安全截断 fit：限字节数，但绝不切半个字 ==")
local msg = "发送一条消息给客服😀😀😀"
print("原串 " .. #msg .. " 字节 / " .. U.len(msg) .. " 字符: " .. msg)
local caps = {5, 8, 10, 13, 20, #msg}
for j = 1, #caps do
  local cap = caps[j]
  local cut, used = U.fit(msg, cap)
  print(string.format("  上限 %2d -> 留 %2d 字节 %2d 字  %s  ok=%s",
    cap, used, U.len(cut) or -1, U.sub(cut, 1, 5), tostring(U.check(cut))))
end

print("")
print("== 6. charpattern：一个字符的字节模式 ==")
print("U.charpattern 字节: " .. bytelist(U.charpattern))
local seg = {}
for c in ("a中😀b"):gmatch(U.charpattern) do seg[#seg + 1] = c end
local escseg = {}
for j = 1, #seg do escseg[j] = esc(seg[j]) .. "(" .. #seg[j] .. ")" end
print("gmatch 切 'a中😀b' : " .. concat(escseg, " | ") .. "   共 " .. #seg .. " 段")
print("第 2 段码点        : U+" .. string.format("%X", U.decode(seg[2], 1, true)))

-- 官方 charpattern 里那个「真 0 字节」，5.1 的模式引擎当场就崩；现场试一次
local nul_pat = "[\0-\127][\128-\191]*"
local pok, perr = pcall(function() return ("a中b"):gmatch(nul_pat)() end)
print(string.format("  含真 0 字节的模式  %-6s %s", pok and "能用" or "崩",
  pok and "" or (tostring(perr):match("malformed pattern") or "ERR")))
local zok, zc = pcall(function() return ("a中b"):gmatch(U.charpattern)() end)
print(string.format("  换 %%z 写法        %-6s 首段=%s", zok and "能用" or "崩", zok and zc or "-"))

print("")
print("== 7. 一行接通两个版本 ==")
print('  utf8 = utf8 or require("utf8lite")   -- 5.1/5.2 补上，5.3+ 用原生')
print("  当前 type(utf8) = " .. type(utf8) .. "   _VERSION = " .. _VERSION)

print("")
print("== 8. 版本差异（按解释器如实打印）==")
print(string.format("  %-26s %s", "type(bit32)", type(bit32)))
if type(utf8) == "table" then
  print(string.format("  %-26s %d", "原生 charpattern 上界", utf8.charpattern:byte(7)))
  print(string.format("  %-26s %d", "  自写库同项", U.charpattern:byte(7)))
  local ok, r = pcall(utf8.char, 0x110000)
  print(string.format("  %-26s %s", "原生 char 0x110000 报错?", tostring(not ok)))
  if ok then
    print(string.format("  %-26s %s", "  产出的字节（非标准！）", bytelist(r)))
  end
  print(string.format("  %-26s %s", "原生 len(代理区) 算合法?",
    tostring(utf8.len("\237\160\128") ~= nil)))
  print(string.format("  %-26s %s", "  自写库同项", tostring(U.len("\237\160\128") ~= nil)))
  print(string.format("  %-26s %s", "第 4 参数 lax 生效?",
    tostring((pcall(utf8.len, "\244\144\128\128", 1, 4, true)
             and utf8.len("\244\144\128\128", 1, 4, true) == 1))))
else
  print("  这个解释器没有 utf8 库，标准库的语义无从谈起")
  print("  自写库照常工作: U.len('a中b') = " .. U.len("a中b"))
end
print(string.format("  %-22s %d 个（三版一致）",
  "codepoint 不传 j 返回", select("#", U.codepoint("a中b"))))

print("")
print("== 9. 性能：拼接方式与「纯 Lua 的代价」 ==")
local N, REPS = 3000, 100
local t = {}
for j = 1, N do t[j] = "中" end

local t0 = os.clock()
local acc
for r = 1, REPS do
  acc = ""
  for j = 1, N do acc = acc .. t[j] end
end
local dotdot = (os.clock() - t0) / REPS

t0 = os.clock()
local acc2
for r = 1, REPS do acc2 = concat(t) end
local conc = (os.clock() - t0) / REPS

print(string.format("  拼 %d 个「中」(%d 字节): .. = %.4fs   table.concat = %.4fs",
  N, #acc, dotdot, conc))
print(string.format("  两种写法结果一致: %s", tostring(acc == acc2)))

local big = string.rep("中", 100000)          -- 30 万字节 / 10 万字符
t0 = os.clock()
local cnt = 0
for _, cp in U.codes(big) do cnt = cnt + 1 end
local walk = os.clock() - t0
print(string.format("  自写库遍历 %d 字符: %.4fs (%.0f 字符/秒)", cnt, walk, cnt / walk))
if type(utf8) == "table" then
  t0 = os.clock()
  local cnt2 = 0
  for _, cp in utf8.codes(big) do cnt2 = cnt2 + 1 end
  local nwalk = os.clock() - t0
  print(string.format("  原生 utf8 遍历 %d 字符: %.4fs —— 纯 Lua 慢 %.0f 倍",
    cnt2, nwalk, walk / nwalk))
else
  print("  原生 utf8 遍历: 这个版本没有原生实现可比")
end
print(string.format("  同一串: U.len = %d   # = %d", U.len(big), #big))

print("")
print("== 10. 自检 ==")
print("  完整对照见 test.lua：Python 独立实现 + 真实 5.4 原生 utf8 逐条比对")
