--=====================================================================
-- prngkit.lua
-- 本集公共库：bit32 兜底 + 64 位无符号运算 + splitmix64 播种 + xoshiro256**
--
-- 结构：
--   第 1 节 bit32 兜底 —— 方案取自第 1 章 bit32_pure.lua（4 位真值表 × 8 段）
--   第 2 节 u64        —— 方案取自第 1 章 int64.lua：用 (hi, lo) 两个 32 位
--                         无符号整数模拟 64 位，中间量全部 < 2^53，double 精确；
--                         乘法拆 16 位半字。add/mul32/shl/shr 与 int64.lua 逐行同源。
--   第 3 节 splitmix64 —— 官方 C 参考实现逐行翻译
--   第 4 节 xoshiro256** —— 官方 C 参考实现逐行翻译
--
-- 五个解释器（LuaJIT 2.1 / 5.1 / 5.2 / 5.3 / 5.4）跑同一份代码：
--   5.1/5.2 没有整数子类型、没有位运算符，这里就是纯算术模拟；
--   5.3/5.4 有原生 64 位整数与 bit32，本库照样走 (hi, lo) 路线，
--   所以五家的输出逐位一致，对拍才有意义。
--=====================================================================

local M = {}

---------------------------------------------------------------------
-- 1. bit32 兜底：Lua 5.1 / LuaJIT 根本没有 bit32
--    位运算在 2^k 进制下「逐位独立」，32 位 = 8 个 4 位查表运算拼出来
---------------------------------------------------------------------
local TWO32 = 4294967296.0   -- 2^32
local TWO16 = 65536.0        -- 2^16
local MAX32 = 4294967295.0

local AND, OR, XOR = {}, {}, {}
for a = 0, 15 do
  AND[a], OR[a], XOR[a] = {}, {}, {}
  for b = 0, 15 do
    local r, p, x, y = 0, 1, a, b
    for _ = 1, 4 do
      local xb, yb = x % 2, y % 2
      r = r + p * (xb * yb)             -- 与：两位全 1 才记 1
      x, y = (x - xb) / 2, (y - yb) / 2
      p = p * 2
    end
    AND[a][b] = r
    OR[a][b]  = a + b - r               -- a|b = a+b-(a&b)
    XOR[a][b] = a + b - 2 * r           -- a^b = a+b-2(a&b)
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

-- 安全整除：double 除法可能舍入跨过整数边界，用乘法反向修正
local function fdiv(x, q)
  local r = math.floor(x / q) + 0.0
  if r * q > x then r = r - 1 elseif (r + 1) * q <= x then r = r + 1 end
  return r
end

local bitfn = {}
if bit32 then bitfn = bit32 else            -- 5.2/5.3/5.4 用原生位库
  function bitfn.band(x, ...) return op32(AND, x, ...) end
  function bitfn.bor (x, ...) return op32(OR,  x, ...) end
  function bitfn.bxor(x, ...) return op32(XOR, x, ...) end
  function bitfn.bnot(x) return MAX32 - (x % TWO32) end

  function bitfn.lshift(x, n)
    if n >= 32 or n <= -32 then return 0 end
    if n < 0 then return bitfn.rshift(x, -n) end
    x = x % TWO32
    if n >= 16 then x = (x % TWO16) * TWO16; n = n - 16 end
    if n == 0 then return x end
    local hi, lo = fdiv(x, TWO16), x % TWO16
    return ((hi * 2 ^ n) % TWO16) * TWO16 + lo * 2 ^ n
  end

  function bitfn.rshift(x, n)
    if n >= 32 or n <= -32 then return 0 end
    if n < 0 then return bitfn.lshift(x, -n) end
    x = x % TWO32
    if n >= 16 then return fdiv(fdiv(x, TWO16), 2 ^ (n - 16)) end
    local hi = fdiv(x, TWO16)
    return hi * 2 ^ (16 - n) + fdiv(x - hi * TWO16, 2 ^ n)
  end

  function bitfn.extract(x, field, width)
    return bitfn.rshift(x, field) % 2 ^ (width or 1)
  end
end
M.bit32 = bitfn
M.bit32mode = bit32 and "原生 bit32" or "兜底(纯算术)"

---------------------------------------------------------------------
-- 2. u64：无符号 64 位整数 = (hi, lo)，value = hi * 2^32 + lo
--    add / mul32 / shl / shr 与第 1 章 int64.lua 逐行同源
---------------------------------------------------------------------
local u = {}
local SIGN = 2147483648.0

local function u32(x) return x % TWO32 end

local function new(hi, lo)
  return setmetatable({ hi = u32(hi), lo = u32(lo) }, u)
end
u.new = new

function u.fromParts(hi, lo) return new(hi, lo) end   -- 16 进制常量从这里进

function u.fromNumber(n)                              -- 仅限 < 2^53
  local hi = fdiv(n, TWO32)
  return new(hi, n - hi * TWO32)
end

function u.fromString(s)                              -- 十进制字符串，不丢精度
  s = s:match("^%s*(.-)%s*$")
  local n = new(0, 0)
  local TEN = new(0, 10)
  for i = 1, #s do
    n = u.add(u.mul(n, TEN), new(0, s:byte(i) - 48))
  end
  return n
end

function u.add(a, b)                    -- 手动进位
  local lo = a.lo + b.lo
  local hi = a.hi + b.hi
  if lo >= TWO32 then lo, hi = lo - TWO32, hi + 1 end
  return new(hi, lo)
end

---------------------------------------------------------------------
-- 乘法：32×32 会得到 64 位，double 装不下！
--       把每个 32 位再拆成两个 16 位半字，16×16 = 32 位，double 精确
---------------------------------------------------------------------
local function mul32(x, y)              -- 返回 (hi, lo)
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

function u.mul(a, b)                    -- 高出 64 位的部分直接丢弃
  local llh, lll = mul32(a.lo, b.lo)
  local lhh, lhl = mul32(a.lo, b.hi)    -- 这两项乘 2^32 后
  local hlh, hll = mul32(a.hi, b.lo)    -- 高出 64 位的部分直接丢弃
  return new(llh + lhl + hll, lll)
end

local function bw(op, a, b) return new(op(a.hi, b.hi), op(a.lo, b.lo)) end
function u.band(a, b) return bw(bitfn.band, a, b) end
function u.bor (a, b) return bw(bitfn.bor,  a, b) end
function u.bxor(a, b) return bw(bitfn.bxor, a, b) end

function u.shl(a, n)                    -- 逻辑左移，跨 hi/lo 拼接
  n = n % 64
  if n == 0 then return new(a.hi, a.lo) end
  if n >= 32 then return new(bitfn.lshift(a.lo, n - 32), 0) end
  return new(
    bitfn.bor(bitfn.lshift(a.hi, n), bitfn.extract(a.lo, 32 - n, n)),
    bitfn.lshift(a.lo, n))
end

function u.shr(a, n)                    -- 逻辑右移
  n = n % 64
  if n == 0 then return new(a.hi, a.lo) end
  if n >= 32 then return new(0, bitfn.rshift(a.hi, n - 32)) end
  return new(
    bitfn.rshift(a.hi, n),
    bitfn.bor(bitfn.rshift(a.lo, n), bitfn.lshift(a.hi, 32 - n)))
end

function u.rotl(a, k)                   -- 循环左移：xoshiro 的灵魂
  return u.bor(u.shl(a, k), u.shr(a, 64 - k))
end

function u.eq(a, b) return a.hi == b.hi and a.lo == b.lo end

local HEXDIGIT = "0123456789ABCDEF"
local function hex8(n)
  local t = {}
  for i = 8, 1, -1 do
    local d = n % 16
    t[i] = HEXDIGIT:sub(d + 1, d + 1)
    n = fdiv(n, 16)
  end
  return table.concat(t)
end

function u.hex(a) return "0x" .. hex8(a.hi) .. hex8(a.lo) end
u.__tostring = function(a) return u.hex(a) end
M.u64 = u

---------------------------------------------------------------------
-- 3. splitmix64：官方 C 参考实现逐行翻译，专职把种子打散
--    uint64_t z = (*state += 0x9E3779B97F4A7C15);
--    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9;
--    z = (z ^ (z >> 27)) * 0x94D049BB133111EB;
--    return z ^ (z >> 31);
---------------------------------------------------------------------
local PHI    = new(0x9E3779B9, 0x7F4A7C15)   -- 0x9E3779B97F4A7C15
local MIX_A  = new(0xBF58476D, 0x1CE4E5B9)
local MIX_B  = new(0x94D049BB, 0x133111EB)

local sm = {}
sm.__index = sm

function sm.new(seed)
  return setmetatable({ st = u.fromNumber(seed) }, sm)
end

function sm:next()
  self.st = u.add(self.st, PHI)             -- 黄金比例常数，保证步进不重复
  local z = self.st
  z = u.bxor(z, u.shr(z, 30)); z = u.mul(z, MIX_A)
  z = u.bxor(z, u.shr(z, 27)); z = u.mul(z, MIX_B)
  return u.bxor(z, u.shr(z, 31))
end
M.splitmix64 = sm

---------------------------------------------------------------------
-- 4. xoshiro256**：官方 C 参考实现逐行翻译
--    result = rotl(s[1] * 5, 7) * 9      -- 三元乘：乘 5、转 7、乘 9
--    t = s[1] << 17
--    s[2] ^= s[0]; s[3] ^= s[1]; s[1] ^= s[2]; s[0] ^= s[3]; s[2] ^= t
--    s[3] = rotl(s[3], 45)
-- 状态 S = {s1, s2, s3, s4}（Lua 下标 1..4 对应 C 的 s[0..3]）
---------------------------------------------------------------------
local FIVE = u.fromNumber(5)
local NINE = u.fromNumber(9)

local xo = {}
xo.__index = xo

function xo.next(S)                          -- 模块级函数：对状态表就地推进
  local res = u.mul(u.rotl(u.mul(S[2], FIVE), 7), NINE)
  local t = u.shl(S[2], 17)
  S[3] = u.bxor(S[3], S[1])
  S[4] = u.bxor(S[4], S[2])
  S[2] = u.bxor(S[2], S[3])
  S[1] = u.bxor(S[1], S[4])
  S[3] = u.bxor(S[3], t)
  S[4] = u.rotl(S[4], 45)
  return res
end

function xo.fromState(S)                     -- 显式给状态（含坏状态演示）
  return setmetatable({ s = { S[1], S[2], S[3], S[4] } }, xo)
end

function xo.fromSeed(seed)                   -- splitmix64 播种 4×u64
  local g = sm.new(seed)
  local S = {}
  for i = 1, 4 do S[i] = g:next() end
  return setmetatable({ s = S, seed = seed }, xo)
end

function xo.naiveSeed(seed)                  -- 反面教材：不打散直接塞
  local x = u.fromNumber(seed)
  return xo.fromState({ x, u.add(x, u.fromNumber(1)),
                        u.add(x, u.fromNumber(2)), u.add(x, u.fromNumber(3)) })
end

function xo:draw()
  return xo.next(self.s)
end

M.xoshiro256 = xo

-- 顺手补一个带表头的十六进制格式化，探针里好排版
function M.hexline(tag, x)
  return tag .. "\t" .. u.hex(x)
end

---------------------------------------------------------------------
-- 5. 对拍向量载入：src/xoshiro_vectors.lua（tools/gen_ref.py 生成）
--    run_lua.py 按文件名跑脚本，向量不是公共库，只能用 io 找回来
---------------------------------------------------------------------
function M.loadvectors(name)
  name = name or "xoshiro_vectors.lua"
  local cands = { "src/" .. name, name, "../src/" .. name, "../../src/" .. name }
  for i = 1, #cands do
    local f = io.open(cands[i], "r")
    if f then
      local t = f:read("*a")
      f:close()
      local lch = loadstring or load           -- 5.1/JIT 用 loadstring，5.3+ 用 load
      local chunk = lch and lch(t)
      if not chunk then return nil, "向量文件编译失败" end
      return chunk()
    end
  end
  return nil, "找不到 " .. name .. "（从工程根目录运行 run_lua.py）"
end

return M
