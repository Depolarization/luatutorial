window.SNIPPETS = {
 "ctor": {
  "line": 22,
  "text": "local function u32(x)        -- 归一化到 [0, 2^32)，负数会正确回绕\n  return x % TWO32\nend\n\n-- 安全整除：double 做除法可能舍入到整数边界的另一侧，用乘法反向修正\n\nlocal function new(hi, lo)\n  return setmetatable({ hi = u32(hi), lo = u32(lo) }, int64)\nend\nint64.new = new\n\nfunction int64.fromNumber(n)          -- n 需为非负整数且 < 2^53\n  local hi = fdiv(n, TWO32)\n  return new(hi, n - hi * TWO32)\nend"
 },
 "fdiv": {
  "line": 27,
  "text": "local function fdiv(x, q)\n  local r = math.floor(x / q) + 0.0          -- +0.0：全程保持 double\n  if r * q > x then r = r - 1 elseif (r + 1) * q <= x then r = r + 1 end\n  return r\nend"
 },
 "add": {
  "line": 66,
  "text": "function int64.add(a, b)\n  local lo = a.lo + b.lo\n  local hi = a.hi + b.hi\n  if lo >= TWO32 then lo, hi = lo - TWO32, hi + 1 end   -- 低 32 位进位\n  return new(hi, lo)                                    -- hi 溢出即 mod 2^64\nend"
 },
 "sub": {
  "line": 73,
  "text": "function int64.sub(a, b)\n  local lo, hi = a.lo - b.lo, a.hi - b.hi\n  if lo < 0 then lo, hi = lo + TWO32, hi - 1 end        -- 低 32 位借位\n  return new(hi, lo)\nend\n\nfunction int64.neg(a) return int64.sub(ZERO, a) end\nfunction int64.isNeg(a) return a.hi >= SIGN end         -- 二补码符号位\nfunction int64.isZero(a) return a.hi == 0 and a.lo == 0 end\n"
 },
 "cmp": {
  "line": 86,
  "text": "function int64.eq(a, b) return a.hi == b.hi and a.lo == b.lo end\n\nfunction int64.ult(a, b)                                -- 无符号 <\n  if a.hi ~= b.hi then return a.hi < b.hi end           -- 先比高位\n  return a.lo < b.lo\nend\n\nfunction int64.slt(a, b)                                -- 有符号 <\n  local x = bit32.bxor(a.hi, 0x80000000)                -- 翻转符号位后\n  local y = bit32.bxor(b.hi, 0x80000000)                -- 就能当无符号比\n  if x ~= y then return x < y end\n  return a.lo < b.lo\nend\n"
 },
 "bitops": {
  "line": 103,
  "text": "local function bw(op, a, b) return new(op(a.hi, b.hi), op(a.lo, b.lo)) end\nfunction int64.band(a, b) return bw(bit32.band, a, b) end\nfunction int64.bor (a, b) return bw(bit32.bor,  a, b) end\nfunction int64.bxor(a, b) return bw(bit32.bxor, a, b) end\nfunction int64.bnot(a)    return new(bit32.bnot(a.hi), bit32.bnot(a.lo)) end"
 },
 "shl": {
  "line": 117,
  "text": "function int64.shl(a, n)                                -- 逻辑左移\n  n = n % 64\n  if n == 0 then return new(a.hi, a.lo) end\n  if n >= 32 then return new(bit32.lshift(a.lo, n - 32), 0) end\n  return new(\n    bit32.bor(bit32.lshift(a.hi, n), bit32.extract(a.lo, 32 - n, n)),\n    bit32.lshift(a.lo, n))\nend"
 },
 "mul32": {
  "line": 152,
  "text": "local function mul32(x, y)                              -- 返回 (hi, lo)\n  local x0, x1 = x % TWO16, fdiv(x, TWO16)\n  local y0, y1 = y % TWO16, fdiv(y, TWO16)\n  local v0 = x0 * y0                    -- < 2^32\n  local v1 = x0 * y1 + x1 * y0          -- < 2^33\n  local v2 = x1 * y1                    -- < 2^32\n  local c = fdiv(v0, TWO16); local r0 = v0 % TWO16\n  v1 = v1 + c\n  c = fdiv(v1, TWO16); local r1 = v1 % TWO16\n  v2 = v2 + c\n  local r3 = fdiv(v2, TWO16); local r2 = v2 % TWO16\n  return r2 + r3 * TWO16, r0 + r1 * TWO16   -- (hi, lo)\nend"
 },
 "mul": {
  "line": 166,
  "text": "function int64.mul(a, b)\n  local llh, lll = mul32(a.lo, b.lo)\n  local lhh, lhl = mul32(a.lo, b.hi)    -- 这两项乘 2^32 后\n  local hlh, hll = mul32(a.hi, b.lo)    -- 高出 64 位的部分直接丢弃\n  return new(llh + lhl + hll, lll)\nend\n"
 },
 "divmod": {
  "line": 176,
  "text": "function int64.divmod(a, b)\n  if b.hi == 0 and b.lo == 0 then error(\"division by zero\") end\n  local q, r = ZERO, ZERO\n  for i = 63, 0, -1 do\n    r = int64.shl(r, 1)\n    if int64.bit(a, i) == 1 then r = int64.bor(r, ONE) end\n    if not int64.ult(r, b) then\n      r = int64.sub(r, b)\n      q = int64.bor(q, int64.shl(ONE, i))\n    end\n  end\n  return q, r\nend\nfunction int64.div(a, b) local q = int64.divmod(a, b); return q end\nfunction int64.mod(a, b) local _, r = int64.divmod(a, b); return r end\n"
 },
 "tostring": {
  "line": 195,
  "text": "function int64.tostring(a, signed)\n  if signed and int64.isNeg(a) then\n    return \"-\" .. int64.tostring(int64.neg(a))\n  end\n  if int64.isZero(a) then return \"0\" end\n  local digits, n = {}, a\n  while not int64.isZero(n) do\n    local r\n    n, r = int64.divmod(n, TEN)\n    digits[#digits + 1] = r.lo\n  end\n  local out = {}\n  for i = #digits, 1, -1 do out[#out + 1] = string.char(48 + digits[i]) end\n  return table.concat(out)\nend"
 }
};
window.LUAOUT = [
 "== 1. double 的天花板 ==",
 "2^53 + 1 == 2^53 ?       true",
 "2^53 + 1 =               9007199254740992",
 "",
 "== 2. hi / lo 拆分 ==",
 "2^53  ->  hi             0x00200000",
 "2^53  ->  lo             0x00000000",
 "还原 =                     9007199254740992",
 "",
 "== 3. 加法：低位进位 ==",
 "(2^64-1) + 1 =           0",
 "            hex          0000000000000000",
 "",
 "== 4. 减法：借位与二补码 ==",
 "0 - 1      hex           FFFFFFFFFFFFFFFF",
 "0 - 1  有符号               -1",
 "-42    有符号               -42",
 "-42 < 0 ?                true",
 "",
 "== 5. 乘法：拆 16 位半字 ==",
 "2^32 * 2^32 =            0",
 "123456789 * 987654321    121932631112635269",
 "2^63 * 2 =               0",
 "",
 "== 6. 除法：64 步长除法 ==",
 "10^18 / 7 =              142857142857142857",
 "10^18 % 7 =              1",
 "",
 "== 7. 位运算与移位 ==",
 "v        =               12345678901234567890",
 "v   hex  =               AB54A98CEB1F0AD2",
 "v << 17  =               5988052741705170944",
 "v >> 17  =               94190055093647",
 "v & 255  =               210",
 "~v  hex  =               54AB567314E0F52D",
 "",
 "== 8. 对照：int64 vs double ==",
 "int64  =                 9999999800000001",
 "double =                 9999999800000000",
 "自检：330 条用例，通过 330，失败 0",
 "结论：与 Python 大整数结果完全一致"
];
