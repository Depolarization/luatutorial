-- fnv.lua —— FNV-1a / FNV-1，32 位和 64 位。
-- 32 位版直接吃 bitop 的拆半字乘法；64 位在 5.1 上没有 64 位整数，
-- 只能把两个乘数各自拆成 4 个 16 位 limb 自己乘——这就是「在 double 世界上造一个 u64」。

local B = require("bitop")
local bxor, mul32 = B.bxor, B.mul32
local floor = math.floor
local byte = string.byte

local fnv = {}

local O32, P32 = 0x811c9dc5, 0x01000193          -- 2166136261, 16777619

function fnv.fnv1a32(s)
  local h = O32
  for i = 1, #(s or "") do
    h = mul32(bxor(h, byte(s, i)), P32)
  end
  return h
end

function fnv.fnv132(s)                                -- 先乘后异或
  local h = O32
  for i = 1, #(s or "") do
    h = bxor(mul32(h, P32), byte(s, i))
  end
  return h
end

fnv.hex32 = function(s) return B.hex32(fnv.fnv1a32(s)) end

-- ---- 64 位：数用 {[0]..[3]} 表示，[0] 是最低的 16 位 ----
local L = 65536

-- 直接写 16 位 limb，不用 0xcbf29ce484222325 这种字面量：
-- 十六进制字面量在 5.1 上会被截到 32 位，在 int32 的 Lua 上会变成负数。
local BASIS = { [0] = 0x2325, [1] = 0x8422, [2] = 0x9ce4, [3] = 0xcbf2 }  -- 14695981039346656037
local PRIME = { [0] = 0x01b3, [1] = 0x0000, [2] = 0x0100, [3] = 0x0000 }  -- 1099511628211

-- 16 位 limb 相乘最坏要吃到 65535*65535 = 4294836225，已经越过 32 位。
-- 平台整数装不下就当场认输，绝不吐一个「看着像 64 位、其实回绕过」的字符串。
fnv.can64 = (65535 * 65535) == 4294836225

local function mul64(a, b)                           -- 只保留低 64 位
  local c = { [0] = 0, [1] = 0, [2] = 0, [3] = 0 }
  for i = 0, 3 do
    local carry = 0
    for j = 0, 3 - i do
      local t = c[i + j] + a[i] * b[j] + carry
      carry = floor(t / L)
      c[i + j] = t % L
    end
  end
  return c
end

local function xorb(h, x)                            -- 只动最低 16 位：x < 256
  h[0] = B.bxor(h[0], x)
  return h
end

local function hex64(h)
  local t = {}
  for i = 3, 0, -1 do t[4 - i] = string.format("%04x", h[i]) end
  return table.concat(t)
end
fnv.hex64_of_limb = hex64

function fnv.fnv1a64(s)
  if not fnv.can64 then
    return nil, "这台的整数只有 32 位，16 位 limb 相乘就会回绕——64 位哈希做不了"
  end
  local h = { [0] = BASIS[0], [1] = BASIS[1], [2] = BASIS[2], [3] = BASIS[3] }
  for i = 1, #(s or "") do
    h = mul64(xorb(h, byte(s, i)), PRIME)
  end
  return hex64(h)
end

-- 有 int64 的解释器上，同样的算法 6 行就能写完；拿来交叉验证 limb 版有没有进位错。
local loader = loadstring or load
local NATIVE64 = [[
return function(s)
  local h = 0xcbf29ce484222325          -- 十六进制字面量在 5.3+ 上按位截断，值是那个 64 位模式
  for i = 1, #s do
    h = (h ~ s:byte(i)) * 0x100000001b3
  end
  return string.format("%016x", h)
end
]]
local ok, f = pcall(loader, NATIVE64)
if ok and f then
  local ok2, g = pcall(f)
  if ok2 and g then
    -- 拿公认向量验收，别让它「跑得出 16 个字符」就冒充正确
    local ok3, probe = pcall(g, "a")
    if ok3 and probe == "af63dc4c8601ec8c" then
      fnv.native64 = g
    else
      fnv.native64_note = '这台跑不出正确的 64 位：g("a") = ' .. tostring(probe)
    end
  end
end

return fnv
