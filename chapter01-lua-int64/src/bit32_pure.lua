--=====================================================================
-- bit32_pure.lua
-- 纯算术实现的 bit32 兼容层（Lua 5.1 根本没有 bit32）
-- 思路：位运算在 2^k 进制下是「逐位独立」的，
--       所以 32 位运算 = 8 个 4 位查表运算拼起来。
--=====================================================================
local M = {}

local TWO32 = 4294967296.0
local TWO16 = 65536.0
local MAX32 = 4294967295.0

-- 4 位真值表；用恒等式 a|b = a+b-(a&b)、a^b = a+b-2(a&b) 推出
local AND, OR, XOR = {}, {}, {}
for a = 0, 15 do
  AND[a], OR[a], XOR[a] = {}, {}, {}
  for b = 0, 15 do
    local r, p, x, y = 0, 1, a, b
    for _ = 1, 4 do
      local xb, yb = x % 2, y % 2
      r = r + p * (xb * yb)
      x, y = (x - xb) / 2, (y - yb) / 2
      p = p * 2
    end
    AND[a][b] = r
    OR[a][b]  = a + b - r
    XOR[a][b] = a + b - 2 * r
  end
end

local function op32(T, x, y, ...)
  x, y = x % TWO32, y % TWO32
  local r, p = 0.0, 1.0
  for _ = 1, 8 do
    local a, b = x % 16, y % 16
    r = r + T[math.floor(a)][math.floor(b)] * p
    x, y = (x - a) / 16, (y - b) / 16
    p = p * 16
  end
  if select("#", ...) > 0 then return op32(T, r, ...) end
  return r
end

-- 安全整除：double 除法可能因舍入跨过整数边界，用乘法反向修正
local function fdiv(x, q)
  local r = math.floor(x / q) + 0.0
  if r * q > x then r = r - 1 elseif (r + 1) * q <= x then r = r + 1 end
  return r
end

function M.band(x, ...) return op32(AND, x, ...) end
function M.bor (x, ...) return op32(OR,  x, ...) end
function M.bxor(x, ...) return op32(XOR, x, ...) end
function M.bnot(x) return MAX32 - (x % TWO32) end
function M.btest(x, ...) return M.band(x, ...) ~= 0 end

function M.lshift(x, n)
  if n >= 32 or n <= -32 then return 0 end
  if n < 0 then return M.rshift(x, -n) end
  x = x % TWO32
  if n >= 16 then x = (x % TWO16) * TWO16; n = n - 16 end
  if n == 0 then return x end
  local hi, lo = fdiv(x, TWO16), x % TWO16
  return ((hi * 2 ^ n) % TWO16) * TWO16 + lo * 2 ^ n
end

function M.rshift(x, n)
  if n >= 32 or n <= -32 then return 0 end
  if n < 0 then return M.lshift(x, -n) end
  x = x % TWO32
  if n >= 16 then return fdiv(fdiv(x, TWO16), 2 ^ (n - 16)) end
  local hi = fdiv(x, TWO16)
  return hi * 2 ^ (16 - n) + fdiv(x - hi * TWO16, 2 ^ n)
end

function M.extract(x, field, width)
  return M.rshift(x, field) % 2 ^ (width or 1)
end

return M
