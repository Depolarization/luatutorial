--=====================================================================
-- int64.lua
-- 用两个 32 位无符号整数 (hi, lo) 模拟 64 位整数
--
-- 背景：Lua 5.1 / 5.2 的 number 只是 double，只能精确表示 2^53 以内的
--       整数；标准库 bit32 又只支持 32 位。所以必须自己拆成两半。
--
-- 约定：value = hi * 2^32 + lo      hi, lo 都归一化到 [0, 2^32)
--       按二补码解释时，负数 = hi 的最高位为 1
-- 所有中间结果都保证 < 2^53，所以 double 能精确表示。
--=====================================================================

local bit32 = bit32 or require("bit32")

local int64 = {}
int64.__index = int64

local TWO32 = 4294967296.0   -- 2^32
local TWO16 = 65536.0        -- 2^16
local SIGN  = 2147483648.0   -- 2^31，hi 的符号位

local function u32(x)        -- 归一化到 [0, 2^32)，负数会正确回绕
  return x % TWO32
end

-- 安全整除：double 做除法可能舍入到整数边界的另一侧，用乘法反向修正
local function fdiv(x, q)
  local r = math.floor(x / q) + 0.0          -- +0.0：全程保持 double
  if r * q > x then r = r - 1 elseif (r + 1) * q <= x then r = r + 1 end
  return r
end

local function new(hi, lo)
  return setmetatable({ hi = u32(hi), lo = u32(lo) }, int64)
end
int64.new = new

local ZERO = new(0, 0)
local ONE  = new(0, 1)
local TEN  = new(0, 10)
int64.ZERO, int64.ONE, int64.TEN = ZERO, ONE, TEN

---------------------------------------------------------------------
-- 构造
---------------------------------------------------------------------
function int64.fromNumber(n)          -- n 需为非负整数且 < 2^53
  local hi = fdiv(n, TWO32)
  return new(hi, n - hi * TWO32)
end

function int64.fromString(s)          -- 十进制字符串，不受 double 精度限制
  s = s:match("^%s*(.-)%s*$")
  local neg = false
  if s:sub(1, 1) == "-" then neg = true; s = s:sub(2)
  elseif s:sub(1, 1) == "+" then s = s:sub(2) end
  local n = ZERO
  for i = 1, #s do
    n = int64.add(int64.mul(n, TEN), new(0, s:byte(i) - 48))
  end
  return neg and int64.neg(n) or n
end

---------------------------------------------------------------------
-- 加减：手动处理进位 / 借位
---------------------------------------------------------------------
function int64.add(a, b)
  local lo = a.lo + b.lo
  local hi = a.hi + b.hi
  if lo >= TWO32 then lo, hi = lo - TWO32, hi + 1 end   -- 低 32 位进位
  return new(hi, lo)                                    -- hi 溢出即 mod 2^64
end

function int64.sub(a, b)
  local lo, hi = a.lo - b.lo, a.hi - b.hi
  if lo < 0 then lo, hi = lo + TWO32, hi - 1 end        -- 低 32 位借位
  return new(hi, lo)
end

function int64.neg(a) return int64.sub(ZERO, a) end
function int64.isNeg(a) return a.hi >= SIGN end         -- 二补码符号位
function int64.isZero(a) return a.hi == 0 and a.lo == 0 end

---------------------------------------------------------------------
-- 比较
---------------------------------------------------------------------
function int64.eq(a, b) return a.hi == b.hi and a.lo == b.lo end

function int64.ult(a, b)                                -- 无符号 <
  if a.hi ~= b.hi then return a.hi < b.hi end           -- 先比高位
  return a.lo < b.lo
end

function int64.slt(a, b)                                -- 有符号 <
  local x = bit32.bxor(a.hi, 0x80000000)                -- 翻转符号位后
  local y = bit32.bxor(b.hi, 0x80000000)                -- 就能当无符号比
  if x ~= y then return x < y end
  return a.lo < b.lo
end

---------------------------------------------------------------------
-- 位运算：hi / lo 各自按 32 位算，互不干扰
---------------------------------------------------------------------
local function bw(op, a, b) return new(op(a.hi, b.hi), op(a.lo, b.lo)) end
function int64.band(a, b) return bw(bit32.band, a, b) end
function int64.bor (a, b) return bw(bit32.bor,  a, b) end
function int64.bxor(a, b) return bw(bit32.bxor, a, b) end
function int64.bnot(a)    return new(bit32.bnot(a.hi), bit32.bnot(a.lo)) end

function int64.bit(a, i)  -- 取第 i 位（0 = 最低位）
  if i >= 32 then return bit32.extract(a.hi, i - 32) end
  return bit32.extract(a.lo, i)
end

---------------------------------------------------------------------
-- 移位：跨 hi / lo 拼接，bit32 每次只负责自己那 32 位
---------------------------------------------------------------------
function int64.shl(a, n)                                -- 逻辑左移
  n = n % 64
  if n == 0 then return new(a.hi, a.lo) end
  if n >= 32 then return new(bit32.lshift(a.lo, n - 32), 0) end
  return new(
    bit32.bor(bit32.lshift(a.hi, n), bit32.extract(a.lo, 32 - n, n)),
    bit32.lshift(a.lo, n))
end

function int64.shr(a, n)                                -- 逻辑右移
  n = n % 64
  if n == 0 then return new(a.hi, a.lo) end
  if n >= 32 then return new(0, bit32.rshift(a.hi, n - 32)) end
  return new(
    bit32.rshift(a.hi, n),
    bit32.bor(bit32.rshift(a.lo, n), bit32.lshift(a.hi, 32 - n)))
end

function int64.sar(a, n)                                -- 算术右移（补符号位）
  local r = int64.shr(a, n)
  if n > 0 and int64.isNeg(a) then
    if n >= 32 then
      r.hi = 0xFFFFFFFF
      r.lo = u32(bit32.bor(r.lo, bit32.lshift(0xFFFFFFFF, 64 - n)))
    else
      r.hi = u32(bit32.bor(r.hi, bit32.lshift(0xFFFFFFFF, 32 - n)))
    end
  end
  return r
end

---------------------------------------------------------------------
-- 乘法：32×32 会得到 64 位，double 装不下！
--       把每个 32 位再拆成两个 16 位半字，16×16 = 32 位，double 精确
---------------------------------------------------------------------
local function mul32(x, y)                              -- 返回 (hi, lo)
  local x0, x1 = x % TWO16, fdiv(x, TWO16)
  local y0, y1 = y % TWO16, fdiv(y, TWO16)
  local v0 = x0 * y0                    -- < 2^32
  local v1 = x0 * y1 + x1 * y0          -- < 2^33
  local v2 = x1 * y1                    -- < 2^32
  local c = fdiv(v0, TWO16); local r0 = v0 % TWO16
  v1 = v1 + c
  c = fdiv(v1, TWO16); local r1 = v1 % TWO16
  v2 = v2 + c
  local r3 = fdiv(v2, TWO16); local r2 = v2 % TWO16
  return r2 + r3 * TWO16, r0 + r1 * TWO16   -- (hi, lo)
end

function int64.mul(a, b)
  local llh, lll = mul32(a.lo, b.lo)
  local lhh, lhl = mul32(a.lo, b.hi)    -- 这两项乘 2^32 后
  local hlh, hll = mul32(a.hi, b.lo)    -- 高出 64 位的部分直接丢弃
  return new(llh + lhl + hll, lll)
end

---------------------------------------------------------------------
-- 除法：二进制长除法，逐位试减，共 64 步
---------------------------------------------------------------------
function int64.divmod(a, b)
  if b.hi == 0 and b.lo == 0 then error("division by zero") end
  local q, r = ZERO, ZERO
  for i = 63, 0, -1 do
    r = int64.shl(r, 1)
    if int64.bit(a, i) == 1 then r = int64.bor(r, ONE) end
    if not int64.ult(r, b) then
      r = int64.sub(r, b)
      q = int64.bor(q, int64.shl(ONE, i))
    end
  end
  return q, r
end
function int64.div(a, b) local q = int64.divmod(a, b); return q end
function int64.mod(a, b) local _, r = int64.divmod(a, b); return r end

---------------------------------------------------------------------
-- 转字符串：反复除 10，从低位往高位取余
---------------------------------------------------------------------
function int64.tostring(a, signed)
  if signed and int64.isNeg(a) then
    return "-" .. int64.tostring(int64.neg(a))
  end
  if int64.isZero(a) then return "0" end
  local digits, n = {}, a
  while not int64.isZero(n) do
    local r
    n, r = int64.divmod(n, TEN)
    digits[#digits + 1] = r.lo
  end
  local out = {}
  for i = #digits, 1, -1 do out[#out + 1] = string.char(48 + digits[i]) end
  return table.concat(out)
end

local HEXDIGIT = "0123456789ABCDEF"
function int64.hex8(n)                              -- 32 位 -> 8 位十六进制
  local t = {}
  for i = 8, 1, -1 do
    local d = n % 16
    t[i] = HEXDIGIT:sub(d + 1, d + 1)
    n = fdiv(n, 16)
  end
  return table.concat(t)
end

function int64.toHex(a) return int64.hex8(a.hi) .. int64.hex8(a.lo) end
function int64.toNumber(a) return a.hi * TWO32 + a.lo end   -- 仅在 < 2^53 时精确

---------------------------------------------------------------------
-- 运算符重载
---------------------------------------------------------------------
int64.__add = int64.add
int64.__sub = int64.sub
int64.__mul = int64.mul
int64.__div = int64.div
int64.__mod = int64.mod
int64.__unm = int64.neg
int64.__eq  = int64.eq
int64.__lt  = int64.ult
int64.__tostring = int64.tostring

return int64
