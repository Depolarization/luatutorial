--=====================================================================
-- t1_versions.lua
-- math.random 的版本差异，全部实测：返回类型 / 子类型 / 边角行为 /
-- Windows 上 C rand() 的 15 位熵痕迹 / 5.4 内部就是 xoshiro256** 的对拍。
--=====================================================================
local K = require("prngkit")
local jit_on = type(jit) == "table"

---------------------------------------------------------------------
-- A. 无参调用：五家都返回浮点，但 5.3+ 有 math.type 能说清「浮点」
---------------------------------------------------------------------
local r = math.random()
print("A 无参类型\t" .. (math.type and math.type(r) or "number(浮点)") ..
      "\tmath.type\t" .. (math.type and "有" or "无"))
print("A 无参样例\t" .. string.format("%.6f", r))

-- A2. 无参值 × 32768 是否恒为整数：Windows 的 rand() 只有 15 位，5.1/5.2/5.3 都露馅
do
  local hit, N = 0, 100
  for _ = 1, N do
    local v = math.random()
    if v * 32768 == math.floor(v * 32768) then hit = hit + 1 end
  end
  print("A2 无参x32768整数\t" .. hit .. "/" .. N)
end

---------------------------------------------------------------------
-- B. 带区间调用：5.3+ 返回整数子类型；5.1/5.2/JIT 是整数值的 double
---------------------------------------------------------------------
local r2 = math.random(1, 10)
print("B 区间(1,10)\t" .. tostring(r2) .. "\t" ..
      (math.type and math.type(r2) or
      (r2 % 1 == 0 and "number(值是整数)" or "number(浮点)")))

---------------------------------------------------------------------
-- C. 同种子下五家的序列各不相同（JIT 与 PUC 完全不同源）
---------------------------------------------------------------------
math.randomseed(7)
local e = {}
for i = 1, 3 do e[i] = math.random(0, 999999) end
print("C 种子7前三值\t" .. table.concat(e, "\t"))

---------------------------------------------------------------------
-- D. 边角行为：random(0) / 浮点种子 / randomseed 返回几个值
---------------------------------------------------------------------
math.randomseed(42)
local ok0, v0 = pcall(math.random, 0)
if ok0 then
  print("D random(0)\t不报错\t" .. tostring(v0))
else
  print("D random(0)\t" .. (string.find(tostring(v0), "interval is empty", 1, true)
        and "报错 interval is empty" or tostring(v0)))
end

local okd, vd = pcall(math.randomseed, os.time() + os.clock())
if okd then
  print("D 浮点种子\t接受")
else
  print("D 浮点种子\t" .. (string.find(tostring(vd), "no integer representation", 1, true)
        and "拒绝(number has no integer representation)" or tostring(vd)))
end
print("D randomseed返回\t" .. select("#", math.randomseed(42)))

---------------------------------------------------------------------
-- E. 5.3 在 Windows 的 15 位 rand()：大区间只会落在 512 的倍数上
--    r = k/2^15，r * 2^24 = k * 512，一步不错
---------------------------------------------------------------------
do
  local mult, N = 0, 2000
  for _ = 1, N do
    local v = math.random(0, 16777215)
    if v % 512 == 0 then mult = mult + 1 end
  end
  print("E 大区间512倍数\t" .. mult .. "/" .. N)
end

do
  local seen, distinct = {}, 0
  for _ = 1, 40000 do
    local v = math.random()
    if not seen[v] then seen[v] = true; distinct = distinct + 1 end
  end
  print("E2 无参40000次不同值\t" .. distinct .. "/40000")
end

---------------------------------------------------------------------
-- F. 5.4 内部就是 xoshiro256**：
--    randomseed(42) → 状态 {42, 0xff, 0, 0} 先丢弃 16 个输出，
--    math.random(0, 2^31-1) = 原始输出 & 0x7FFFFFFF（区间是 2 的幂，无重抽偏差）
--    期望序列由 tools/gen_ref.py 按官方 C 翻译生成
---------------------------------------------------------------------
local V = K.loadvectors()
local is54 = (not jit_on) and _VERSION == "Lua 5.4"
if V and is54 then
  math.randomseed(42)
  local ok = 0
  for i = 1, 1000 do
    if math.random(0, 2147483647) == V.luarandom[i] then ok = ok + 1 end
  end
  print("F 5.4内部对拍 种子42\t" .. ok .. "/1000")
  math.randomseed(2024)
  ok = 0
  for i = 1, 1000 do
    if math.random(0, 2147483647) == V.luarandom2[i] then ok = ok + 1 end
  end
  print("F 5.4内部对拍 种子2024\t" .. ok .. "/1000")
else
  print("F 5.4内部对拍 种子42\t仅5.4实测")
  print("F 5.4内部对拍 种子2024\t仅5.4实测")
end
