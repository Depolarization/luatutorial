--=====================================================================
-- t2_seed.lua
-- 播种三问：同种子同序列吗？忘了播种会怎样？os.time 播种为什么会撞车？
-- 注意：B 段必须在任何 randomseed 之前执行，它代表「进程启动后直接抽」。
--=====================================================================

---------------------------------------------------------------------
-- B. 不播种直接抽：5.1/5.2/5.3/JIT 每次进程启动都一样，5.4 会自动播种
---------------------------------------------------------------------
do
  local g = {}
  for i = 1, 5 do g[i] = math.random(0, 999999) end
  print("B 不播种前五值\t" .. table.concat(g, "\t"))
end

---------------------------------------------------------------------
-- A. 同种子同序列：这是 PRNG 的定义，不是 bug
---------------------------------------------------------------------
do
  math.randomseed(7)
  local a = {}
  for i = 1, 5 do a[i] = math.random(0, 999999) end
  math.randomseed(7)
  local b = {}
  for i = 1, 5 do b[i] = math.random(0, 999999) end
  local same = true
  for i = 1, 5 do if a[i] ~= b[i] then same = false end end
  print("A 同种子同序列\t" .. tostring(same) .. "\t" .. table.concat(a, ","))
end

---------------------------------------------------------------------
-- C. os.time() 只有 1 秒分辨率：一个脚本里连打两次都一样
---------------------------------------------------------------------
do
  local t1, t2 = os.time(), os.time()
  print("C os.time连打两次\t" .. tostring(t1 == t2) .. "\t" .. t1)
end

---------------------------------------------------------------------
-- D. 同一秒两次启动 = 同一个 T = 同一条序列（5.1~5.4 全中）
---------------------------------------------------------------------
do
  local T = os.time()
  math.randomseed(T)
  local d1 = { math.random(0, 999999), math.random(0, 999999) }
  math.randomseed(T)                    -- 模拟同一秒内的第二次启动
  local d2 = { math.random(0, 999999), math.random(0, 999999) }
  print("D 同秒重播种同序列\t" .. tostring(d1[1] == d2[1] and d1[2] == d2[2]) ..
        "\t" .. d1[1] .. "," .. d1[2])
end

---------------------------------------------------------------------
-- E. os.clock 的分辨率实测（Windows 上是墙钟）
---------------------------------------------------------------------
do
  local c0 = os.clock()
  local c1 = os.clock()
  local guard = 0
  while c1 == c0 and guard < 3000000 do
    c1 = os.clock()
    guard = guard + 1
  end
  print("E os.clock步进\t" .. string.format("%.4f", c1 - c0) .. "s\t循环 " .. guard .. " 次")
end

---------------------------------------------------------------------
-- F. 民间补丁 os.time()+os.clock()：种子成了浮点数，5.4 直接拒收
---------------------------------------------------------------------
do
  local ts = os.time() + os.clock()
  print("F 补丁种子值\t" .. string.format("%.3f", ts) .. "\t" ..
        (math.type and math.type(ts) or "number(浮点)"))
  local okf, vf = pcall(math.randomseed, ts)
  if okf then
    print("F 浮点种子\t接受（5.3 及以前、LuaJIT 都收）")
  else
    print("F 浮点种子\t" .. (string.find(tostring(vf), "no integer representation", 1, true)
          and "拒绝(number has no integer representation)" or tostring(vf)))
  end
end
