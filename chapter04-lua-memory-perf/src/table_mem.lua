-- table_mem.lua：实测一张表的两半部分各花多少内存。
-- 不引用任何文档结论：每个数字都是当前这台解释器 collectgarbage("count") 的真实差值。
local K = require("perfkit")

print("VERSION", _VERSION, "LUAJIT", type(jit) == "table")

-- 1. 空表本身的开销
local empty = K.best(1, function() return {} end)
print("EMPTY", "{}", string.format("%.0f", empty))

local ladder = {9, 17, 33, 65, 129, 1000, 1025, 2048, 100000, 131072, 1000000}

-- 2. 数组部分：键是连续的 1..n
print("-- 数组部分 t[i]=i --")
for _, n in ipairs(ladder) do
  local d = K.best(n, function(m)
    local t = {}
    for i = 1, m do t[i] = i end
    return t
  end)
  print("ARRAY", n, string.format("%.0f", d))
end

-- 3. 哈希部分：键换成 i+0.5。浮点键不可能进数组部分，值仍是整数，
--    所以除了节点本身不产生任何额外对象——这是唯一干净的哈希部分测法。
print("-- 哈希部分 t[i+0.5]=i --")
for _, n in ipairs(ladder) do
  local d = K.best(n, function(m)
    local t = {}
    for i = 1, m do t[i + 0.5] = i end
    return t
  end)
  print("HASH", n, string.format("%.0f", d))
end

-- 4. 由 n=2048 这个「刚好是 2 的幂」的点定出每格字节数，再反推其它 n 实际占了几格
local per_a = K.best(2048, function(m)
  local t = {}
  for i = 1, m do t[i] = i end
  return t
end)
local per_h = K.best(2048, function(m)
  local t = {}
  for i = 1, m do t[i + 0.5] = i end
  return t
end)
per_a = (per_a - empty) / 2048
per_h = (per_h - empty) / 2048
print("PER_SLOT", string.format("%.2f", per_a), string.format("%.2f", per_h),
      "node_bytes", string.format("%.0f", per_h), "slot_bytes", string.format("%.0f", per_a))

print("-- 反推实际格数（向上取整到 2 的幂）--")
for _, n in ipairs({1000, 1025, 100000, 1000000}) do
  local da = K.best(n, function(m)
    local t = {}
    for i = 1, m do t[i] = i end
    return t
  end)
  local dh = K.best(n, function(m)
    local t = {}
    for i = 1, m do t[i + 0.5] = i end
    return t
  end)
  print("SLOTS", n, "array", string.format("%.0f", (da - empty) / per_a),
        "hash", string.format("%.0f", (dh - empty) / per_h))
end

-- 5. 键是偶数：数据到底进数组还是进哈希？
print("-- 偶数键 t[2i]=i --")
for _, n in ipairs({1000, 100000}) do
  local d, u = K.cost(n, function(m)
    local t = {}
    for i = 1, m do t[2 * i] = i end
    return t
  end)
  local run, total = K.first_run(u)
  print("EVEN", n, string.format("%.0f", d), string.format("%.2f", d / n),
        "len#", #u, "pairs_run", run, "total", total, "maxkey", K.maxnumkey(u))
  KEEP[1] = nil
end

-- 6. 只塞一个大整数键：t[1000000]=true
do
  local t = {}
  t[1000000] = true
  local run, total = K.first_run(t)
  print("JUMPKEY", 1000000, "len#", #t, "pairs_run", run, "total", total,
        "value_ok", t[1000000] == true)
end

-- 7. 混用一个字符串键，会不会把数组部分搞坏（两种顺序各测一次）
do
  local n = 100000
  local a = {}
  for i = 1, n do a[i] = i end
  a.name = "x"
  local run, total = K.first_run(a)
  print("MIX_ARRAY_FIRST", n, "len#", #a, "pairs_run", run, "total", total)

  local b = {}
  b.name = "x"
  for i = 1, n do b[i] = i end
  run, total = K.first_run(b)
  print("MIX_HASH_FIRST", n, "len#", #b, "pairs_run", run, "total", total)
  print("MIX_SAME", #a == #b)
end

-- 8. 预分配到底有没有收益：先把 n 个空位「占住」再填，能不能一次到位
do
  local n = 100000
  local d1, t1 = K.cost(n, function(m)
    local t = {}
    for i = 1, m do t[i] = i end
    return t
  end)
  local run1, tot1 = K.first_run(t1)
  local d2, t2 = K.cost(n, function(m)
    local t = {}
    t[m] = true          -- 先占住最后一个下标，看数组部分会不会直接撑到 m
    for i = 1, m do t[i] = i end
    return t
  end)
  local run2, tot2 = K.first_run(t2)
  print("PREHOLD", n, string.format("%.0f", d1), string.format("%.0f", d2),
        "pairs_run", run1, run2, "total", tot1, tot2, "len#", #t1, #t2)
  KEEP[1] = nil
end
