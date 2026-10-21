-- insert_cost.lua：往表尾加元素，四种写法的实测耗时；#t 的单价；头部插入的 O(n^2)。
local K = require("perfkit")
local LOAD = loadstring or load
print("VERSION", _VERSION)

local ms = function(s) return string.format("%.1f", s * 1000) end
local ns = K.ns

-- 1. 追加 n 个元素：四种写法。整个循环跑完再除以 n，才是每次操作的单价
print("-- 追加 n = 200000：每次操作多少纳秒 --")
local n = 200000
local ways = {
  {"t[i] = v", function()
     local t = {}
     for i = 1, n do t[i] = i end
     KEEP[1] = t
   end},
  {"t[#t+1] = v", function()
     local t = {}
     for i = 1, n do t[#t + 1] = i end
     KEEP[1] = t
   end},
  {"table.insert(t, v)", function()
     local t = {}
     for i = 1, n do table.insert(t, i) end
     KEEP[1] = t
   end},
  {"局部计数器 t[c] = v", function()
     local t = {}
     local c = 0
     for i = 1, n do c = c + 1; t[c] = i end
     KEEP[1] = t
   end},
}
local base
for _, w in ipairs(ways) do
  local d = K.bench(w[2])
  if not base then base = d end
  print("APPEND", w[1], ns(d / n) .. "ns/次", "整轮", ms(d) .. "ms",
        "相对第一种", string.format("%.1f", d / base) .. "x")
  KEEP[1] = nil
  collectgarbage("collect")
end

-- 2. #t 的单价：每轮先脏写第 1 格，让「瞄一眼就能返回」那条捷径走不通，
--    于是每一轮都得真的找一次边界。两种造法的差别只在数组部分的形状。
print("-- 同样 20 万元素，两种造法下读一次边界的单价 --")
do
  local m = 200000
  local grown = {}
  for i = 1, m do grown[i] = i end              -- 逐个追加：数组部分被放大到 2 的幂
  local parts = {}
  for i = 1, m do parts[i] = tostring(i) end
  local chunk = LOAD("return {" .. table.concat(parts, ",") .. "}")
  local exact = chunk and chunk()               -- 一次构造到位：数组部分正好 m 格
  print("GETNUM_BUILD", m, "grown_len", #grown, "exact_len", exact and #exact or "编译失败")
  if exact then
    KEEP[1] = {grown, exact}
    local u = 2000
    local function len_cost(tbl)
      local d = K.bench(function()
        local s = 0
        for i = 1, u do tbl[1] = i; s = s + #tbl end
        KEEP[1] = s
      end, 0.2)
      return d / u
    end
    local c1 = len_cost(grown)
    local c2 = len_cost(exact)
    print("GETNUM", m, "逐个追加", ns(c1) .. "ns/次", "一次构造", ns(c2) .. "ns/次",
          "差", string.format("%.1f", c1 / c2) .. "倍")
  end
end

-- 3. 预分配到底省什么：同样的数据，一次构造到位比逐个追加少一截内存
print("-- 预分配 vs 逐个追加（10 万元素）--")
do
  local m = 100000
  local parts = {}
  for i = 1, m do parts[i] = tostring(i) end
  local chunk = LOAD("return {" .. table.concat(parts, ",") .. "}")
  local grown = K.best(m, function(mm)
    local t = {}
    for i = 1, mm do t[i] = i end
    return t
  end)
  KEEP[1] = nil
  if chunk then
    K.clean()
    local before = K.bytes()
    local t = chunk()
    local lit = K.bytes() - before
    KEEP[1] = t
    print("PREALLOC", m, "逐个追加", string.format("%.0f", grown),
          "一次构造", string.format("%.0f", lit),
          "省下", string.format("%.1f%%", (grown - lit) / grown * 100))
    KEEP[1] = nil
  else
    print("PREALLOC", m, "构造器编译失败，跳过")
  end
end

-- 4. 头部插入：每加一个元素要把整段往后搬，所以是平方级
print("-- table.insert(t, 1, v) 头部插入 --")
local head = {}
for _, m in ipairs({2000, 4000, 8000}) do
  local d = K.bench(function()
    local t = {}
    for i = 1, m do table.insert(t, 1, i) end
    KEEP[1] = t
  end, 0.15)
  head[m] = d
  KEEP[1] = nil
  print("HEADINS", m, ms(d) .. "ms", "每插一个", ns(d / m) .. "ns",
        "规模翻倍后", head[m / 2] and string.format("%.1fx", d / head[m / 2]) or "-")
end

-- 5. 同样的数据，倒着填再原地反转：证明「换个方向就快」
do
  local m = 8000
  local d1 = K.bench(function()
    local t = {}
    for i = 1, m do table.insert(t, 1, i) end
    KEEP[1] = t
  end, 0.15)
  local d2 = K.bench(function()
    local t = {}
    for i = 1, m do t[#t + 1] = i end
    for i = 1, math.floor(m / 2) do
      local j = m - i + 1
      t[i], t[j] = t[j], t[i]
    end
    KEEP[1] = t
  end, 0.15)
  KEEP[1] = nil
  print("HEAD_VS_REVERSE", m, ms(d1) .. "ms", ms(d2) .. "ms",
        string.format("%.0f倍", d1 / d2))
end

-- 6. 尾部删除：两边都先建表，所以减掉同一个建表基线才是删除的净成本。
--    LuaJIT 会把「置 nil」这个空转循环整个折掉，净成本算出来是负数 → 夹成 0，
--    同时把两次实测的整轮时间原样打出来，方便对照。
do
  local m = 200000
  local base0 = K.bench(function()
    local t = {}
    for i = 1, m do t[i] = i end
    KEEP[1] = t
  end, 0.15)
  local d1 = K.bench(function()
    local t = {}
    for i = 1, m do t[i] = i end
    for i = 1, m do table.remove(t) end
    KEEP[1] = t
  end, 0.15)
  local d2 = K.bench(function()
    local t = {}
    for i = 1, m do t[i] = i end
    for i = m, 1, -1 do t[i] = nil end
    KEEP[1] = t
  end, 0.15)
  KEEP[1] = nil
  local r1, r2 = d1 - base0, d2 - base0
  print("TAIL_REMOVE", m, "建表基线", ms(base0) .. "ms",
        "remove 整轮", ms(d1) .. "ms", "置 nil 整轮", ms(d2) .. "ms",
        "净 remove", ms(r1 > 0 and r1 or 0) .. "ms", "净置 nil", ms(r2 > 0 and r2 or 0) .. "ms",
        "倍数", r2 > 0 and string.format("%.1f倍", r1 / r2) or "删除循环被编译掉")
end
