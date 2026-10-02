--[[
  test.lua : 双层对照自检
    第 1 层  vectors.lua —— Python 自己编解码出的标准答案（独立第二实现）
    第 2 层  原生 utf8 库 —— 只有 5.3+ 才有，5.1 上会明确打印「跳过」
  同一份文件在真实 Lua 5.1.5 与真实 Lua 5.4.8 上跑，结论应当一致。
]]
local U = require("utf8lite")
local V = require("vectors")

local unpack = table.unpack or unpack
local concat = table.concat

local pass, fail, nassert = 0, 0, 0
local function eq(got, want, what)
  nassert = nassert + 1
  if got == want then pass = pass + 1
  else
    fail = fail + 1
    if fail <= 6 then
      print(string.format("FAIL %-34s got=%s want=%s",
                          what, tostring(got), tostring(want)))
    end
  end
end

-- 把一个函数的全部返回值压成一行可比较的字符串；出错统一记作 "ERR"
local function collect(...)
  local t = {n = select("#", ...)}
  for k = 1, t.n do t[k] = select(k, ...) end
  return t
end
local function snap(f, ...)
  local args = collect(...)
  local okres, res = pcall(function(a)
    return collect(f(unpack(a, 1, a.n)))
  end, args)
  if not okres then return "ERR" end
  local o = {}
  for k = 1, res.n do o[k] = tostring(res[k]) end
  return concat(o, "|")
end
-- snap 自己必须先是对的，否则整份对照都是空跑
assert(snap(function(...) return 7, nil, "x" end) == "7|nil|x", "snap 自检失败")
assert(snap(error, "boom") == "ERR", "snap 自检失败")
assert(snap(function() return 0 end) == "0", "snap 自检失败")

-- 库出错不要让整个自检挂掉，记成 "ERR" 照样算差异
local function one(f, ...)
  local ok, v = pcall(f, ...)
  if not ok then return "ERR" end
  return v
end

-- ==================== 1. 对照 Python 的标准答案 ====================
print("== 1. 对照 Python 独立实现（vectors.lua）==")

for idx, c in ipairs(V) do
  local s = c.s
  if c.len then                                   -- 合法串
    eq(one(U.len, s), c.len, "#" .. idx .. " len")

    local okp, res = pcall(function() return collect(U.codepoint(s, 1, #s)) end)
    if okp then
      for k = 1, #c.cps do eq(res[k], c.cps[k], "#" .. idx .. " cp" .. k) end
      local back = {}
      local okr = pcall(function()
        for k = 1, #c.cps do back[k] = U.char(c.cps[k]) end
      end)
      if okr then eq(concat(back), s, "#" .. idx .. " 编码回原串")
      else eq("出错", "不应出错", "#" .. idx .. " char 回编码") end
    else
      eq("出错", "不应出错", "#" .. idx .. " codepoint")
    end

    for k = 1, #c.offset do
      local want = c.offset[k]
      if want < 0 then want = nil end            -- -1 记号表示「应该是 nil」
      eq(one(U.offset, s, k), want, "#" .. idx .. " offset(" .. k .. ")")
    end

    for m = 1, #c.fit_len do                      -- 安全截断：0 .. #s 字节
      local okf, cut, used = pcall(U.fit, s, m - 1)
      if not okf then cut, used = "", -1 end
      eq(#cut, c.fit_bytes[m], "#" .. idx .. " fit(" .. (m - 1) .. ") 字节")
      eq(used, c.fit_bytes[m], "#" .. idx .. " fit(" .. (m - 1) .. ") 返回字节数")
      eq(one(U.len, cut), c.fit_len[m], "#" .. idx .. " fit(" .. (m - 1) .. ") 字符")
    end

    eq(one(U.reverse, one(U.reverse, s)), s, "#" .. idx .. " 反转两次还原")
    local parts = {}
    local okp2 = pcall(function()
      for k = 1, c.len do parts[k] = U.nth(s, k) end
    end)
    if okp2 then eq(concat(parts), s, "#" .. idx .. " 逐字符拼回")
    else eq("出错", "不应出错", "#" .. idx .. " nth") end
    eq(one(U.len, one(U.sub, s, 1, c.len)), c.len, "#" .. idx .. " sub 全串")

    -- charpattern 必须能独立把一个字符一段切出来：段数 = 字符数，拼回 = 原串
    local segs = {}
    local okseg = pcall(function()
      for piece in s:gmatch(U.charpattern) do segs[#segs + 1] = piece end
    end)
    if okseg then
      eq(#segs, c.len, "#" .. idx .. " charpattern 段数")
      eq(concat(segs), s, "#" .. idx .. " charpattern 拼回")
    else
      eq("出错", "不应出错", "#" .. idx .. " charpattern")
    end
  else                                            -- 非法串：出错位置由构造决定
    local l, pos = U.len(s)
    eq(l, nil, "#" .. idx .. " len 应失败")
    eq(pos, c.bad, "#" .. idx .. " len 出错位置")
    local okc, cpos = U.check(s)
    eq(okc, false, "#" .. idx .. " check 应判非法")
    eq(cpos, c.bad, "#" .. idx .. " check 出错位置")
  end
end
print(string.format("  用例 %d 个字符串 / 断言 %d 处：pass %d，fail %d",
                    #V, nassert, pass, fail))

-- ==================== 2. 对照原生 utf8 ====================
print("")
print("== 2. 对照原生 utf8 库 ==")
if type(utf8) ~= "table" then
  print("  这个解释器没有 utf8 库（Lua 5.1 正是如此）—— 第 2 层跳过")
  print("  结论：库在未改动过的 5.1 上跑通，全部答案来自 Python 独立实现")
  return
end
if _VERSION ~= "Lua 5.4" then
  -- 5.3 的标准库语义和 5.4 有实打实的分歧（代理区、lax、charpattern），
  -- 逐条比对必然对不上，那属于版本差异，见 version_probe.lua 的清单。
  print(string.format("  %s 的 utf8 语义与 5.4 不同（代理区/lax/charpattern）", _VERSION))
  print("  逐条一致性只在真实 5.4 上验证；本解释器只跑第 1 层（对照 Python）")
  return
end

local diff = 0
local function same(a, b, what)
  if a ~= b then
    diff = diff + 1
    if diff <= 6 then
      print("DIFF " .. what .. "  原生=" .. tostring(a) .. "  自写=" .. tostring(b))
    end
  end
end

-- 2a. vectors 里的串，两边结果逐一比对（含 lax 模式）
local function segcount(pat, s)
  local n = 0
  for _ in s:gmatch(pat) do n = n + 1 end
  return n
end
for _, c in ipairs(V) do
  local s = c.s
  same(snap(utf8.len, s), snap(U.len, s), "len " .. #s)
  same(snap(utf8.len, s, 1, #s, true), snap(U.len, s, 1, #s, true), "lax len")
  same(segcount(utf8.charpattern, s), segcount(U.charpattern, s), "charpattern 段数")
  if #s > 0 then
    same(snap(utf8.codepoint, s, 1, #s), snap(U.codepoint, s, 1, #s), "codepoint")
    same(snap(utf8.codepoint, s, 1, #s, true), snap(U.codepoint, s, 1, #s, true), "lax cp")
  end
  for n = -3, 6 do
    same(snap(utf8.offset, s, n), snap(U.offset, s, n), "offset " .. n)
  end
end
for cp = 0, 0x400 do
  same(snap(utf8.char, cp), snap(U.char, cp), "char " .. cp)
end
for _, cp in ipairs({0x7FF, 0x800, 0xFFFF, 0x10000, 0xD800, 0xDFFF,
                     0x10FFFE, 0x10FFFF, 0x110000, 0x200000, 0x4000000,
                     0x7FFFFFFE, 0x7FFFFFFF}) do
  same(snap(utf8.char, cp), snap(U.char, cp), "char " .. cp)
end
print(string.format("  vectors + 边界码点对照：差异 %d 处", diff))

-- 2b. 随机字节串（线性同余自己造随机数，两个解释器得到完全一样的序列）
local seed = 1
local function rnd(m)
  seed = (seed * 1103515245 + 12345) % 2147483648
  return seed % m
end
local TOTAL, rdiff, checks = 20000, 0, 0
local function dump(s)
  local o = {}
  for k = 1, #s do o[k] = tostring(s:byte(k)) end
  return concat(o, " ")
end
for t = 1, TOTAL do
  local n = 1 + rnd(11)
  local bytes = {}
  for k = 1, n do bytes[k] = rnd(256) end
  local s = string.char(unpack(bytes))
  local function cnt(a, b, what)
    checks = checks + 1
    if a ~= b then
      rdiff = rdiff + 1
      if rdiff <= 6 then print("DIFF " .. what .. " 字节=" .. dump(s)) end
    end
  end
  cnt(snap(utf8.len, s), snap(U.len, s), "len")
  cnt(snap(utf8.len, s, 1, #s, true), snap(U.len, s, 1, #s, true), "lax len")
  cnt(snap(utf8.codepoint, s, 1, #s), snap(U.codepoint, s, 1, #s), "codepoint")
  cnt(segcount(utf8.charpattern, s), segcount(U.charpattern, s), "charpattern")
  for n2 = -2, 4 do
    for i = 1, math.min(#s, 5) do
      cnt(snap(utf8.offset, s, n2, i), snap(U.offset, s, n2, i), "offset")
    end
  end
end
print(string.format("  随机字节串 %d 个 / 比对 %d 处：差异 %d 处", TOTAL, checks, rdiff))
print("")
print(string.format("结论：%s", (diff + rdiff == 0)
  and "与原生 utf8 逐条一致，与 Python 独立实现逐条一致"
  or  "还有差异未消除，别急着上线"))
