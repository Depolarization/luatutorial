-- str_intern.lua：实测字符串驻留（intern）的边界、代价与版本差异。
-- 全部用「内存增量」和「耗时」量出来，不引用文档里的数字。
local K = require("perfkit")
print("VERSION", _VERSION)

local ms = function(s) return string.format("%.1f", s * 1000) end
local us = function(s) return string.format("%.1f", s * 1e6) end
local ns = K.ns
local REP = string.rep

-- 1. 驻留悬崖：把同一个内容重复构造 n 次，量每份多花多少字节。
--    驻留 -> 每份只多一个数组槽；不驻留 -> 每份还要一条自己的字符串对象。
print("-- 重复构造同一内容，每份字节数（n=20000）--")
local N = 20000
local slot = K.best(N, function(m)
  local t = {}
  for i = 1, m do t[i] = i end
  return t
end) / N
for _, L in ipairs({8, 16, 32, 38, 39, 40, 41, 42, 48, 64, 128, 256, 1024}) do
  local half = math.floor(L / 2)
  local d = K.best(N, function(m)
    local a, b = REP("x", half), REP("y", L - half)
    local t = {}
    for i = 1, m do t[i] = a .. b end
    return t
  end)
  print("INTERN", L, "每份", string.format("%.2f", d / N), "空槽", string.format("%.2f", slot),
        "驻留", d / N < slot * 2)
  KEEP[1] = nil
end

-- 2. 判等代价：拿一条基准串去和表里 1024 条串逐个比。
--    表里只放两条不同的串对象轮着取，比较双方一直在一级缓存里，
--    于是量到的差别只可能来自「比指针」还是「比内容」，不是访存。
print("-- 判等一次要多少纳秒（同内容 / 首字符就不同）--")
local M = 1024
local function cycle(x, y)
  local t = {}
  for i = 1, M do t[i] = (i % 2 == 0) and x or y end
  return t
end
local function cmp_per(base, arr)
  local d = K.bench(function()
    local k = 0
    for i = 1, M do if base == arr[i] then k = k + 1 end end
    KEEP[1] = k
  end, 0.20)
  return d / M, KEEP[1]
end
for _, L in ipairs({8, 40, 41, 128, 1024}) do
  local body = REP("x", L - 1)
  local head = body .. "x"                       -- 基准串（长串时它是第三个独立对象）
  local a, a2 = body .. "x", body .. "x"         -- 内容跟 head 一模一样
  local b, b2 = "y" .. body, "z" .. body         -- 长度一样，首字符就不同
  local same, diff = cycle(a, a2), cycle(b, b2)
  local p1, h1 = cmp_per(head, same)
  local p2, h2 = cmp_per(head, diff)
  print("EQUAL_SAME", L, ns(p1) .. "ns", "命中", h1)
  print("EQUAL_DIFF", L, ns(p2) .. "ns", "命中", h2)
  same, diff = nil, nil
  K.clean()
end

-- 3. 查找代价：同一个键变量重复查 100 万次，长键会不会每次都重算——看数字。
print("-- 一百万次重复查同一个键 --")
do
  local t = {}
  for _, L in ipairs({8, 40, 41, 128, 1024}) do
    local key = REP("k", L)
    t[key] = 1
    local d = K.mintime(function()
      local c = 0
      for i = 1, 1000000 do c = c + (t[key] or 0) end
      KEEP[1] = c
    end, 2)
    print("LOOKUP_CACHED", L, ms(d) .. "ms", ns(d / 1000000) .. "ns/次", "命中", KEEP[1])
    KEEP[1] = nil
  end
end

-- 4. 第一次用到一条串：只造出来 vs 造出来还要当键用（当键才需要进驻留表 + 算哈希）。
--    两个循环干的活完全一样，只多一次 t[k] = i，差值才是「当键」的净成本。
--    长串（>40 字符）到底进不进驻留表，各版本不一样：5.1 全都进，5.2 起才分家。
print("-- 造一条新串 / 造一条新串并当键用，每次微秒 --")
for _, L in ipairs({8, 40, 41, 1024}) do
  local pad = REP("k", L)
  local m = L >= 1024 and 6000 or 40000
  local sink                            -- 预热：让 JIT / 分配器先进入稳态
  for _ = 1, 200 do sink = pad .. 1 end
  KEEP[1] = sink
  local d1 = K.mintime(function()
    local s = 0
    for i = 1, m do s = s + #(pad .. i) end
    KEEP[1] = s
  end, 3)
  local d2 = K.mintime(function()
    local t1 = {}                        -- 每轮都从空表开始，别把上一轮的键拖成 GC 负担
    local s = 0
    for i = 1, m do local k = pad .. i; t1[k] = i; s = s + #k end
    KEEP[1] = s
    return t1
  end, 3)
  local extra = (d2 - d1) / m
  print("HASH_FIRST", L, "次数", m, "只造", us(d1 / m) .. "us",
        "造并用", us(d2 / m) .. "us", "多花", us(extra > 0 and extra or 0) .. "us",
        "并用更慢", extra > 0)
  KEEP[1] = nil
  K.clean()
end
