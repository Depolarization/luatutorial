-- test.lua：自检。把这一章里所有「不随机器变化」的结构性结论在五个解释器上各验一遍。
-- 时间数字不进这里：它们跟机器走，只作为画面上的实测读数呈现。
local K = require("perfkit")
print("VERSION", _VERSION, "LUAJIT", type(jit) == "table")

local fails = 0
local total = 0
local function eq(tag, got, want)
  total = total + 1
  if got ~= want then
    fails = fails + 1
    print("FAIL", tag, "得到", tostring(got), "期望", tostring(want))
  else
    print("PASS", tag)
  end
end
local function ne(tag, a, b)
  total = total + 1
  if a == b then
    fails = fails + 1
    print("FAIL", tag, "两边都是", tostring(a), "期望不同")
  else
    print("PASS", tag)
  end
end

-- 1. 空表的大小：每个版本都是一个定值（具体字节数由 table_mem.lua 量出来）
do
  local a = K.best(1, function() return {} end)
  local b = K.best(1, function() return {} end)
  total = total + 1
  if a <= 0 or a > 4096 then
    fails = fails + 1
    print("FAIL 空表大小落在不合理区间", a)
  else
    print("INFO 空表字节", a)
  end
end

-- 2. 数组部分的槽价：从 2 的幂两头的差值反推，必须正好落在理论格数上
do
  local p512 = K.best(512, function(n)
    local t = {}
    for i = 1, n do t[i] = i end
    return t
  end)
  local p1024 = K.best(1024, function(n)
    local t = {}
    for i = 1, n do t[i] = i end
    return t
  end)
  local p2048 = K.best(2048, function(n)
    local t = {}
    for i = 1, n do t[i] = i end
    return t
  end)
  eq("1024 与 2048 之间每格同价", p2048 - p1024, (p1024 - p512) * 2)
  print("INFO 每格字节", (p2048 - p1024) / 1024, "512→1024 差价", p1024 - p512)
end

-- 3. 同一个内容的短串只存一份：驻留的直接证据
do
  local s1 = string.rep("a", 20) .. "-tail"
  local s2 = string.rep("a", 20) .. "-tail"
  eq("同内容短串判等", s1 == s2, true)
  local t = {}
  local d = K.best(40000, function(n)
    for i = 1, n do t[i] = string.rep("a", 20) .. "-tail" end
    return t
  end)
  print("INFO 四万条同内容短串每份字节", d / 40000)
end

-- 4. table 的 tostring 带地址，而且地址会变
do
  local t1, t2 = {}, {}
  local s1 = tostring(t1)
  eq("同一个 table 两次打印一致", tostring(t1), s1)
  ne("两张同时活着的表地址不同", s1, tostring(t2))
  print("INFO tostring(table)", s1)
end

-- 5. #t 在有洞时「停在任何一个边界」——边界必须是合法边界，但不能指定是哪一个
do
  local a = {1, 2, nil, 4}
  total = total + 1
  if #a == 2 or #a == 4 then
    print("PASS 有洞时 #a 落在合法边界之一", #a)
  else
    fails = fails + 1
    print("FAIL 有洞时 #a 落在了非法位置", #a)
  end
  local b = {1, nil, 3, nil, 5}
  total = total + 1
  local n = #b
  if b[n] ~= nil and b[n + 1] == nil then
    print("PASS 多个洞时 #b 仍是一个边界", n)
  else
    fails = fails + 1
    print("FAIL #b 不是边界", n, "该位置的值", tostring(b[n]), "下一位", tostring(b[n + 1]))
  end
end

-- 6. collectgarbage 的选项集合：这个解释器支持什么就报什么，不做假设
do
  local ok = pcall(collectgarbage, "setpause", 200)
  total = total + 1
  if not ok then
    fails = fails + 1
    print("FAIL setpause 不可用")
  else
    print("PASS setpause 可用，旧值由返回值给出")
  end
  local g1 = pcall(collectgarbage, "generational")
  local g0 = pcall(collectgarbage, "incremental")
  print("INFO 分代可选", g1, "增量可选", g0)
end

-- 7. 拼接的正确性：五种写法结果必须完全一致
do
  local piece, n = "abc", 3000
  local goal = string.rep(piece, n)
  local t = {}
  for i = 1, n do t[i] = piece end
  local s = ""
  for i = 1, n do s = s .. piece end
  eq("逐段 .. 与 string.rep 一致", s == goal, true)
  eq("table.concat 与 string.rep 一致", table.concat(t) == goal, true)
  local u = {}
  for i = 1, n do u[#u + 1] = piece end
  eq("t[#t+1] 攒起来再 concat 一致", table.concat(u) == goal, true)
  local v = ""
  for i = 1, n do v = v .. i end
  local w = {}
  for i = 1, n do w[i] = tostring(i) end
  eq("数字串逐段拼与先存表再 concat 一致", v == table.concat(w), true)
end

print("SELF-CHECK", _VERSION, total - fails .. "/" .. total, fails == 0 and "OK" or "FAILED")
