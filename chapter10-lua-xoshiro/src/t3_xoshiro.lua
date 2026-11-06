--=====================================================================
-- t3_xoshiro.lua
-- 纯 Lua xoshiro256** 实测：splitmix64 播种状态、naive 反面教材、
-- 前 5 个输出，以及与官方 C 参考实现的 1000 值逐一对拍。
--=====================================================================
local K = require("prngkit")
local u = K.u64
local V, verr = K.loadvectors()

---------------------------------------------------------------------
-- A. splitmix64 播种：一个种子打散成 4×u64 状态
---------------------------------------------------------------------
if V then
  local g = K.xoshiro256.fromSeed(V.seed)
  local st = {}
  for i = 1, 4 do st[i] = u.hex(g.s[i]) end
  print("A splitmix64播种 种子" .. V.seed .. "\t" .. table.concat(st, "\t"))
end

---------------------------------------------------------------------
-- B. 反面教材：不打散直接塞 {1,2,3,4}，第一个输出只有 11520
---------------------------------------------------------------------
do
  local n = K.xoshiro256.naiveSeed(1)
  local n1 = n:draw()
  local n1dec = n1.hi * 4294967296.0 + n1.lo          -- 11520 < 2^53，精确
  print("B naive首输出\t" .. u.hex(n1) .. "\t= " .. string.format("%d", n1dec))
end

---------------------------------------------------------------------
-- C. splitmix 播种后的前 5 个输出（十六进制）
---------------------------------------------------------------------
local ok, total = 0, 0
if V then
  local g = K.xoshiro256.fromSeed(V.seed)
  local h = {}
  for i = 1, 5 do
    local z = g:draw()
    h[i] = u.hex(z)
    if u.eq(z, u.fromString(V.raw[i])) then ok = ok + 1 end
  end
  print("C 前五输出\t" .. table.concat(h, "\t"))
  total = total + 5
  -- 继续抽到第 1000 个，逐个对拍
  local good = ok
  for i = 6, 1000 do
    if u.eq(g:draw(), u.fromString(V.raw[i])) then good = good + 1 end
  end
  ok, total = good, 1000
  print("E 第500个\t" .. u.hex(u.fromString(V.raw[500])))
  print("E 第1000个\t" .. u.hex(u.fromString(V.raw[1000])))
end
print("D 对拍1000\t一致 " .. ok .. "/" .. total .. "\t差异 " .. (total - ok))
