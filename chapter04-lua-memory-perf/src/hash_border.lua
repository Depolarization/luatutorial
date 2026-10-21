-- hash_border.lua：实测 #t 的「边界」语义。每一种写法都在五个解释器上各跑一遍。
local K = require("perfkit")
print("VERSION", _VERSION)

-- 1. 构造器里带 nil：# 是多少？
print("-- 字面量构造 --")
for _, c in ipairs({
  {src = "{1,2,3,4,5}",      t = {1, 2, 3, 4, 5}},
  {src = "{1,2,nil,4,5}",    t = {1, 2, nil, 4, 5}},
  {src = "{1,nil,3}",        t = {1, nil, 3}},
  {src = "{nil,2}",          t = {nil, 2}},
  {src = "{1,2,3,nil}",      t = {1, 2, 3, nil}},
}) do
  print("LITERAL_LEN", c.src, #c.t, "run", K.first_run(c.t), "max", K.maxnumkey(c.t))
end

-- 2. 逐个赋值造出来的洞
print("-- 先填满再挖洞 --")
for _, spec in ipairs({
  {n = 5,   holes = {}},
  {n = 5,   holes = {5}},
  {n = 5,   holes = {3}},
  {n = 5,   holes = {1}},
  {n = 8,   holes = {5}},
  {n = 100, holes = {50}},
  {n = 100, holes = {100}},
  {n = 100, holes = {1}},
}) do
  local t = {}
  for i = 1, spec.n do t[i] = i end
  for _, h in ipairs(spec.holes) do t[h] = nil end
  local hs = {}
  for _, h in ipairs(spec.holes) do hs[#hs + 1] = h end
  print("HOLES", spec.n, table.concat(hs, ","), "len", #t, "run", K.first_run(t),
        "max", K.maxnumkey(t))
end

-- 3. 挖完洞之后再插一个新键，触发 rehash：洞会不会被「吸掉」，# 会不会变
print("-- 洞之后再加键（触发 rehash）--")
do
  local t = {}
  for i = 1, 100 do t[i] = i end
  t[50] = nil
  local before = #t
  t[101] = 101
  local after = #t
  print("REHASH_ABSORB", "before", before, "after_add101", after, "changed", before ~= after)
  local u = {}
  for i = 1, 100 do u[i] = i end
  u[50] = nil
  local b2 = #u
  u.x = "string key"
  print("REHASH_STRKEY", "before", b2, "after_add_strkey", #u)
end

-- 4. 大数组：中间一个洞 / 最后一个洞
print("-- 大数组 --")
for _, n in ipairs({100000}) do
  local half = math.floor(n / 2)
  local a = {}
  for i = 1, n do a[i] = i end
  a[half] = nil
  local b = {}
  for i = 1, n do b[i] = i end
  b[n] = nil
  print("BIG", n, "hole_at_half", #a, "hole_at_end", #b, "run_half", K.first_run(a))
end

-- 5. 只有偶数键 / 只有大键：# 直接是 0
do
  local e = {}
  for i = 1, 1000 do e[2 * i] = i end
  local o = {}
  for i = 1, 1000 do o[i + 100] = i end
  print("ODD_SHAPE", "even1000", #e, "from101", #o, "run", K.first_run(e), K.first_run(o))
end

-- 6. table.insert 碰到洞：新元素落在哪一格、边界后面的数据还在不在
do
  local t = {1, 2, nil, 4, 5}
  local len0 = #t
  table.insert(t, 99)
  print("INSERT_HOLE", "len_before", len0, "len_after", #t, "inserted_at", #t,
        "value", t[#t], "洞后面的数据还在", t[4] == 4 and t[5] == 5)
  local u = {}
  for i = 1, 10 do u[i] = i end
  u[6] = nil
  table.insert(u, 77)
  print("INSERT_HOLE2", "len_before", 10, "after", #u, "t7", u[7], "t10", u[10])
end

-- 7. 同一个内容的表，构造顺序不同 -> # 不同？
do
  local a = {}
  for i = 1, 20 do a[i] = i end
  a[10] = nil
  local b = {}
  for i = 1, 9 do b[i] = i end
  for i = 11, 20 do b[i] = i end
  print("SAME_DATA", #a, #b, "equal_content", K.maxnumkey(a) == K.maxnumkey(b))
end
