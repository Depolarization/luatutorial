-- bitop.lua —— 在「只有 double、没有位运算符」的 Lua 5.1 上搭出 32 位位运算层。
-- 全程只用加、减、乘、除、取模，任何一步的中间值都不许靠近 2^53。

local floor = math.floor
local loader = loadstring or load      -- 5.1 的 load 只吃函数，试探新语法要用 loadstring
local unpack = table.unpack or unpack  -- 5.1 的 unpack 在全局，5.2+ 搬进了 table

-- 2 的幂表：刻意不用 `2^i`，优先拿整数。
-- 在 5.3+ 上 `2^i` 结果是浮点，浮点当模数会把精确的 int64 中间值打回原形
-- （实测 0xFFFFFFFF*16777619 % 2^32 = fefffe70，% 0x100000000 = fefffe6d）；
-- 整数模数却没这个问题。fengari 的整数只有 32 位，装不下 2^32 时退回浮点。
local tointeger = math.tointeger
local P = {}
P[0] = 1
for i = 1, 32 do
  local v = 2^i
  P[i] = (tointeger and tointeger(v)) or v
end
local MASK = P[32] - 1                 -- 4294967295
local MOD = P[32]                      -- 4294967296

local M = { P = P, MASK = MASK, MOD = MOD, implementation = "纯算术" }

-- Lua 的 % 是 floor 语义（五端实测 -7 % 3 == 2），所以负数也直接落在 [0, 2^32)
local function u32(n) return n % MOD end
M.u32 = u32

-- 逐位版 and：32 次除法，慢得像参考实现——它就是拿来当参考实现的
local function band_bit(a, b)
  local r = 0
  for k = 0, 31 do
    if floor(a / P[k]) % 2 == 1 and floor(b / P[k]) % 2 == 1 then r = r + P[k] end
  end
  return r
end
M.band_bit = band_bit

-- 半字节查表：16x16 的 and 表只要 256 项，8 次查表换掉 32 次除法
local ANDT = {}
for x = 0, 15 do
  for y = 0, 15 do
    ANDT[x * 16 + y] = band_bit(x, y)   -- 建表用最笨的版本，表本身不需要被信任
  end
end

local function band(a, b)
  local r, w = 0, 1
  for i = 1, 8 do
    local x, y = a % 16, b % 16
    r = r + ANDT[x * 16 + y] * w
    a = floor(a / 16); b = floor(b / 16); w = w * 16
  end
  return r
end
M.band, M.band_tab = band, band

-- 有了 and，or / xor 只是两条半加器恒等式：a+b = (a|b) + (a&b) = (a^b) + 2(a&b)
-- a+b < 2^33，double 放得下，所以这里的加减是精确的
M.bor  = function(a, b) return a + b - band(a, b) end
M.bxor = function(a, b) return a + b - 2 * band(a, b) end
M.bnot = function(a) return MASK - u32(a) end

local function lshift(a, s)
  if s <= 0 then return u32(a) end
  if s >= 32 then return 0 end
  return (u32(a) % P[32 - s]) * P[s]    -- 先砍掉会溢出的高位，中间值 < 2^32
end

local function rshift(a, s)
  if s <= 0 then return u32(a) end
  if s >= 32 then return 0 end
  return floor(u32(a) / P[s])
end

local function rotl(a, s)
  a = u32(a); s = s % 32
  if s == 0 then return a end
  local div = P[32 - s]
  return (a % div) * P[s] + floor(a / div)
end

M.lshift, M.rshift, M.rotl = lshift, rshift, rotl
M.rotr = function(a, s) return rotl(a, -s) end

-- 四个 32 位数相加 < 2^34，仍在 double 的精确范围内；项数控制在 8 个以内
local function add32(a, b, c, d, e)
  return u32(a + b + (c or 0) + (d or 0) + (e or 0))
end
M.add32 = add32

-- 故意的对照组：两个 32 位数直接相乘再取模。积可达 2^64。
-- 5.1/5.2：乘法在 double 里就已经丢低位，后面 % 2^32 救不回来；
-- 5.3/5.4：乘法是 int64，精确，所以这一版反而是对的——但只要模数写成 `2^32`（浮点），
--          它立刻又错了。两种「对」的理由不一样，两种「错」的方式也不一样。
M.mul32_naive = function(a, b) return u32(a * b) end

-- 正确版本：拆成两个 16 位半字，每个中间值都 < 2^33
local function mul32(a, b)
  a = u32(a); b = u32(b)
  local H = P[16]
  local a0, a1 = a % H, floor(a / H)
  local b0, b1 = b % H, floor(b / H)
  -- a1*b1 那一项带 2^32，模掉之后为 0，直接丢掉
  return u32(a0 * b0 + ((a1 * b0 + a0 * b1) % H) * H)
end
M.mul32 = mul32

local HEXD = "0123456789abcdef"

-- 不用 string.format("%08x", n)：fengari 的整数只有 32 位，4294967295 当浮点传进去
-- 直接报 "number has no integer representation"（runtime_probe.lua 实测），
-- 四个真二进制却又能打。自己按 4 位取数，五端才是同一个字符串。
local function hex32(n)
  n = u32(n)
  local t = {}
  for i = 8, 1, -1 do
    local d = n % 16
    t[i] = string.sub(HEXD, d + 1, d + 1)
    n = floor(n / 16)
  end
  return table.concat(t)
end
M.hex32 = hex32

local function hex(s)
  local t = {}
  for i = 1, #s do
    local b = string.byte(s, i)
    t[2 * i - 1] = string.sub(HEXD, floor(b / 16) + 1, floor(b / 16) + 1)
    t[2 * i] = string.sub(HEXD, b % 16 + 1, b % 16 + 1)
  end
  return table.concat(t)
end
M.hex = hex

-- 另外两种后端：只在有的解释器上存在，用来和纯算术版逐位互印
local BACKENDS = {}

BACKENDS.pure = { name = "纯算术（本文件）", u32 = u32, band = band, bor = M.bor,
  bxor = M.bxor, bnot = M.bnot, lshift = lshift, rshift = rshift, rotl = rotl,
  add32 = add32, mul32 = mul32 }

if type(bit32) == "table" then
  local z = bit32
  BACKENDS.bit32 = { name = "bit32（" .. _VERSION .. " 上有）",
    u32 = function(n) return z.band(n, MASK) end,
    band = z.band, bor = z.bor, bxor = z.bxor, bnot = z.bnot,
    lshift = z.lshift, rshift = z.rshift, rotl = z.lrotate,  -- bit32 叫 lrotate，不叫 rol
    -- bit32 只有 32 位，加减照样要先在 double 里算——但 2^33 之内是精确的，所以可用
    add32 = function(a, b, c, d, e)
      return z.band(a + b + (c or 0) + (d or 0) + (e or 0), MASK) end,
    mul32 = function(a, b) return z.band(mul32(a, b), MASK) end }
end

-- 原生位运算符只有 5.3+ 有，源码在 5.1 上连编译都过不了，只能运行时用字符串拼。
-- 运算符只吃整数，所以每个入口都先把纯算术层可能产生的浮点掰回整数（值不变）。
local NATIVE_SRC = [[
local MASK = 0xFFFFFFFF
local function I(n) return math.type(n) == "integer" and n or math.floor(n) end
return {
  u32    = function(n) return I(n) & MASK end,
  band   = function(a, b) return I(a) & I(b) end,
  bor    = function(a, b) return I(a) | I(b) end,
  bxor   = function(a, b) return I(a) ~ I(b) end,
  bnot   = function(a) return (I(a) & MASK) ~ MASK end,
  lshift = function(a, s) return (I(a) << I(s)) & MASK end,
  rshift = function(a, s) return (I(a) & MASK) >> I(s) end,
  rotl   = function(a, s) s = I(s) % 32
             return ((I(a) << s) | (I(a) >> (32 - s))) & MASK end,
  add32  = function(a, b, c, d, e)
             return (I(a) + I(b) + I(c or 0) + I(d or 0) + I(e or 0)) & MASK end,
  mul32  = function(a, b) return I(a) * I(b) & MASK end,   -- int64 中间值，天然精确
}
]]
local ok, f = pcall(loader, NATIVE_SRC)
if ok and f then
  local ok2, t = pcall(f)
  if ok2 and t then
    -- 先确认这台的整数装得下无符号 32 位。fengari 的 lua_Integer 只有 32 位有符号，
    -- 0xFFFFFFFF 在它眼里是 -1，运算符一碰到 4294967295 直接报错——那就不能当对照。
    local ok3, v = pcall(t.u32, 4294967295)
    if ok3 and v == 4294967295 then
      t.name = "原生位运算符（5.3+）"
      BACKENDS.native = t
    else
      M.native_note = "这台的原生运算符只认 32 位有符号整数，u32(4294967295) 直接报错，不能当哈希基准"
      M.native_err = tostring(v)
    end
  end
end

M.BACKENDS = BACKENDS
M.available = function()
  local l = {}
  for k in pairs(BACKENDS) do l[#l + 1] = k end
  table.sort(l)
  return l
end

-- 拿一组操作数把某个后端和纯算术版对一遍，返回一致 / 第一处不一致的描述
function M.verify(backend)
  local B = type(backend) == "table" and backend or BACKENDS[backend]
  if not B then return nil, "没有这个后端" end
  local cases = {}
  local vals = { 0, 1, 2, 15, 16, 255, 256, 65535, 65536, 2147483648, MASK, 305419896, 16777619, 4294967294 }
  for _, a in ipairs(vals) do
    for _, b in ipairs(vals) do
      cases[#cases + 1] = { op = "band", args = { a, b }, ref = band(a, b) }
      cases[#cases + 1] = { op = "bxor", args = { a, b }, ref = M.bxor(a, b) }
      cases[#cases + 1] = { op = "bor",  args = { a, b }, ref = M.bor(a, b) }
      cases[#cases + 1] = { op = "mul32", args = { a, b }, ref = mul32(a, b) }
      cases[#cases + 1] = { op = "add32", args = { a, b }, ref = add32(a, b) }
    end
    cases[#cases + 1] = { op = "bnot", args = { a }, ref = M.bnot(a) }
    for s = 0, 33 do
      cases[#cases + 1] = { op = "lshift", args = { a, s }, ref = lshift(a, s) }
      cases[#cases + 1] = { op = "rshift", args = { a, s }, ref = rshift(a, s) }
      cases[#cases + 1] = { op = "rotl", args = { a, s }, ref = rotl(a, s) }
    end
  end
  local n = 0
  for _, c in ipairs(cases) do
    local got = B[c.op](unpack(c.args))
    if got ~= c.ref then
      return false, string.format("%s(%s) 得 %s，纯算术得 %s",
        c.op, table.concat(c.args, ","), tostring(got), tostring(c.ref))
    end
    n = n + 1
  end
  return true, string.format("%d 项全部一致", n)
end

return M
