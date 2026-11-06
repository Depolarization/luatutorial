--=====================================================================
-- t4_replay.lua
-- 可复现性落地：同一个种子生成同一个「小世界」；存档只需要存种子。
-- 顺带做一次分布抽查（10000 次），证明手写实现的质量能扛正事。
--=====================================================================
local K = require("prngkit")

---------------------------------------------------------------------
-- 一个 8×8 小世界：种子 → 64 个 0..96 的地形高度
---------------------------------------------------------------------
local function gen_world(seed)
  local g = K.xoshiro256.fromSeed(seed)
  local grid = {}
  for y = 1, 8 do
    local row = {}
    for x = 1, 8 do
      row[x] = g:draw().lo % 97
    end
    grid[y] = row
  end
  return grid
end

local function world_hash(grid)
  local h = 0
  for y = 1, 8 do
    for x = 1, 8 do
      h = (h * 31 + grid[y][x]) % 1000000007
    end
  end
  return h
end

local function rowstr(grid, y)
  local t = {}
  for x = 1, 8 do t[x] = string.format("%02d", grid[y][x]) end
  return table.concat(t, " ")
end

local w1 = gen_world(42)
local h1 = world_hash(w1)
local h1b = world_hash(gen_world(42))
local h3 = world_hash(gen_world(43))

print("A 种子42两次生成\t" .. string.format("%d", h1) .. " vs " .. string.format("%d", h1b) ..
      "\t相同\t" .. tostring(h1 == h1b))
print("B 种子43\t" .. string.format("%d", h3) .. "\t与种子42不同\t" .. tostring(h3 ~= h1))
print("C 存档只存种子\tseed=42\t重建hash=" .. string.format("%d", world_hash(gen_world(42))))
print("D 种子42首行\t" .. rowstr(w1, 1))
print("D 种子43首行\t" .. rowstr(gen_world(43), 1))

---------------------------------------------------------------------
-- 分布抽查：10000 次，奇偶应各半，mod3 应三等分；
-- 低位与高位分开数——** 的低位口碑略逊，数据说话
---------------------------------------------------------------------
do
  local g = K.xoshiro256.fromSeed(7)
  local oddL, oddH, m0, m1, m2 = 0, 0, 0, 0, 0
  for _ = 1, 10000 do
    local z = g:draw()
    if z.lo % 2 == 1 then oddL = oddL + 1 end
    if z.hi % 2 == 1 then oddH = oddH + 1 end
    local m = z.lo % 65536 % 3
    if m == 0 then m0 = m0 + 1 elseif m == 1 then m1 = m1 + 1 else m2 = m2 + 1 end
  end
  print("E 奇偶10000次\t低16位 奇 " .. oddL .. "\t高16位 奇 " .. oddH)
  print("E2 mod3 10000次\t" .. m0 .. " / " .. m1 .. " / " .. m2)
end
