-- ieee754.lua —— 不依赖 bit32 / string.pack / math.frexp 的 double 解剖工具
--
-- 为什么不用现成的东西：
--   * math.frexp / math.ldexp 在 Lua 5.3 就被删掉了，5.4 也没有
--   * bit32 只有 5.2 有，string.pack 只有 5.3/5.4 有
--   * tostring(M) 在 5.1 走 %.14g，大整数会变成 "7.2e+15"，直接毁掉后面的字符串运算
-- 所以这里全部用纯算术：靠「乘除 2 的幂是 IEEE 精确操作」+「中间值始终 < 2^53」
-- 目标：Lua 5.1 / 5.2 / 5.3 / 5.4 / LuaJIT 上结果完全一致

local ieee = {}

local floor = math.floor
local abs = math.abs

ieee.MANT_BITS = 52
ieee.P = 2 ^ 52            -- 4503599627370496
ieee.MAXSAFE = 2 ^ 53      -- 9007199254740992

local function pow2(n)                 -- 2^n（只覆盖正规数范围）
  if n > 1023 then return math.huge end
  if n < -1074 then return 0 end
  return 2 ^ n
end

------------------------------------------------------------------
-- 小工具：不依赖 tostring 的整数 → 十进制字符串
-- （5.1 的 tostring 走 %.14g 会毁掉大整数；5.3 的 tostring 会给浮点带上 ".0"，
--   所以这里一律自己拼数字，不用 tostring）
------------------------------------------------------------------
local DIGITS = "0123456789"
local function dchar(d) return DIGITS:sub(math.floor(d) + 1, math.floor(d) + 1) end

local function int_digits(n)           -- 0 <= n < 2^53
  if n == 0 then return "0" end
  local out = {}
  while n > 0 do
    local q = floor(n / 10)
    out[#out + 1] = dchar(n - q * 10)
    n = q
  end
  return table.concat(out):reverse()
end

local function mul_str(num, m)         -- 十进制字符串竖式乘小整数
  local carry, out = 0, {}
  for i = #num, 1, -1 do
    local cur = tonumber(num:sub(i, i)) * m + carry
    out[#out + 1] = dchar(cur % 10)
    carry = floor(cur / 10)
  end
  while carry > 0 do
    out[#out + 1] = dchar(carry % 10)
    carry = floor(carry / 10)
  end
  return table.concat(out):reverse()
end

local function trim_frac(s)
  local i = #s
  while i > 0 and s:sub(i, i) == "0" do i = i - 1 end
  return s:sub(1, i)
end

------------------------------------------------------------------
-- 解剖：x = sign * M * 2^E，其中 M ∈ [2^52, 2^53)
------------------------------------------------------------------
function ieee.decompose(x)
  assert(type(x) == "number" and x == x and abs(x) < math.huge, "只能处理有限数")
  if x == 0 then return 1, 0, 0 end
  assert(abs(x) >= 2 ^ -1022, "次正规数不在本库讨论范围内")
  local sign = x < 0 and -1 or 1
  local y = sign * x
  local e = floor(math.log(y) / math.log(2))         -- 估计指数，可能偏 1
  while y * pow2(-e) >= 2 do e = e + 1 end
  while y * pow2(-e) < 1 do e = e - 1 end
  local m = y * pow2(-e)                             -- 1 <= m < 2，精确
  return sign, floor(m * 2 ^ 52), e - 52
end

-- 该数量级下相邻两个可表示数的间隔（1 ulp）
function ieee.ulp(x)
  if x == 0 then return 2 ^ -1074 end
  local _, _, E = ieee.decompose(x)
  return pow2(E)
end

-- 若 x 恰好是 2 的整数次幂，返回 "2^n"，否则返回 nil
function ieee.pow2_name(x)
  if x <= 0 then return nil end
  local _, M, E = ieee.decompose(x)
  if M ~= 2 ^ 52 then return nil end
  return "2^" .. (E + 52)
end

-- 整数 n 所在区间 [2^k, 2^(k+1)) 与该处的整数间隔
function ieee.spacing_of(n)
  local _, _, E = ieee.decompose(n)
  local k = floor(math.log(n) / math.log(2))
  local gap = pow2(E)
  if gap < 1 then gap = 1 end
  return k, gap
end

------------------------------------------------------------------
-- 位级视图：符号 1 位 / 指数 11 位（偏移 1023）/ 尾数 52 位
------------------------------------------------------------------
local function to_bin(n, width)        -- n < 2^53 的整数 → 定长二进制字符串
  local out = {}
  for _ = 1, width do
    local q = floor(n / 2)
    out[#out + 1] = (n - q * 2) >= 1 and "1" or "0"
    n = q
  end
  return table.concat(out):reverse()
end

function ieee.bits(x)
  local sign, M, E = ieee.decompose(x)
  local biased = math.floor(E + 52 + 1023)
  local frac = math.floor(M - 2 ^ 52)
  return {
    sign = sign,
    exp_biased = biased,
    exp_unbiased = math.floor(E + 52),
    mantissa = frac,
    s = (sign < 0) and "1" or "0",
    e = to_bin(biased, 11),
    f = to_bin(frac, 52),
  }
end

------------------------------------------------------------------
-- 十进制精确展开：把这个 double 真实代表的数一位不差写出来
-- x = M * 2^E。E >= 0 时是整数（M 连乘 E 次 2）；
-- E < 0 时 x = M * 5^d / 10^d（d = -E），乘完把小数点左移 d 位即可
------------------------------------------------------------------
function ieee.exact(x)
  if math.type and math.type(x) == "integer" then
    return tostring(x)                 -- 5.3/5.4 的整数子类型本来就是精确十进制
  end
  local sign, M, E = ieee.decompose(x)
  if M == 0 then return "0" end
  local prefix = sign < 0 and "-" or ""

  if E >= 0 then
    local s = int_digits(M)
    for _ = 1, E do s = mul_str(s, 2) end
    return prefix .. s
  end

  local d = -E
  local digits = int_digits(M)
  for _ = 1, d do digits = mul_str(digits, 5) end
  if #digits <= d then digits = ("0"):rep(d - #digits + 1) .. digits end
  local ip = digits:sub(1, #digits - d)
  local fp = trim_frac(digits:sub(#digits - d + 1))
  if fp == "" then return prefix .. ip end
  return prefix .. ip .. "." .. fp
end

------------------------------------------------------------------
-- 二进制小数长除法：num/den 写成二进制小数，返回数位串与循环节起点
------------------------------------------------------------------
function ieee.binary_frac(num, den, bits)
  local out, seen = {}, {}
  local r = num % den
  local pos, cyc = 0, 0
  while r ~= 0 and pos < (bits or 60) do
    if seen[r] then
      if cyc == 0 then cyc = seen[r] end     -- 余数开始循环；位数继续填满 bits
    else
      seen[r] = pos + 1
    end
    r = r * 2
    local b = 0
    if r >= den then b = 1 r = r - den end
    out[#out + 1] = tostring(b)
    pos = pos + 1
  end
  return table.concat(out), r ~= 0 and cyc or (cyc > 0 and cyc or 0)
end

-- 交叉验证用：%.17g 是 C 库给的最长十进制（5.1 也能用）
function ieee.g17(x) return string.format("%.17g", x) end

-- 机器精度：让 1+e 仍不等于 1 的最小 e，应为 2^-52
function ieee.machine_eps()
  local e = 1
  while 1 + e / 2 ~= 1 do e = e / 2 end
  return e
end

return ieee
