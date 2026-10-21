-- md5.lua —— RFC 1321 的 MD5，全部位运算走 bitop 的纯算术层。
-- 三件事和直觉相反：字数按小端读、长度字段也是小端、K 表要写死而不是用 sin 现算。

local B = require("bitop")
local band, bxor, bor, bnot = B.band, B.bxor, B.bor, B.bnot
local add32, rotl = B.add32, B.rotl
local floor, byte, char = math.floor, string.byte, string.char
local P = B.P

local K = {
  3614090360, 3905402710,  606105819, 3250441966, 4118548399, 1200080426, 2821735955, 4249261313,
  1770035416, 2336552879, 4294925233, 2304563134, 1804603682, 4254626195, 2792965006, 1236535329,
  4129170786, 3225465664,  643717713, 3921069994, 3593408605,  38016083, 3634488961, 3889429448,
   568446438, 3275163606, 4107603335, 1163531501, 2850285829, 4243563512, 1735328473, 2368359562,
  4294588738, 2272392833, 1839030562, 4259657740, 2763975236, 1272893353, 4139469664, 3200236656,
   681279174, 3936430074, 3572445317,   76029189, 3654602809, 3873151461,  530742520, 3299628645,
  4096336452, 1126891415, 2878612391, 4237533241, 1700485571, 2399980690, 4293915773, 2240044497,
  1873313359, 4264355552, 2734768916, 1309151649, 4149444226, 3174756917,  718787259, 3951481745,
}

local S = {
  7, 12, 17, 22,  7, 12, 17, 22,  7, 12, 17, 22,  7, 12, 17, 22,
  5,  9, 14, 20,  5,  9, 14, 20,  5,  9, 14, 20,  5,  9, 14, 20,
  4, 11, 16, 23,  4, 11, 16, 23,  4, 11, 16, 23,  4, 11, 16, 23,
  6, 10, 15, 21,  6, 10, 15, 21,  6, 10, 15, 21,  6, 10, 15, 21,
}

local md5 = {}
md5.K = K

-- RFC 1321 写的是 K[i] = floor(2^32 * |sin i|)。在这台机器上现算和写死的 64 个数逐个相同
-- （test.lua 会当场比），但浮点 sin 的结果并不是规范的一部分，所以 OpenSSL、Python
-- 这些严肃实现都是把 64 个数写死的。
function md5.deriveK()
  local t = {}
  for i = 1, 64 do t[i] = floor(math.abs(math.sin(i)) * P[32]) end
  return t
end

local mt = { __index = md5 }      -- 让 obj:update(...) / obj:finish() 能用点调用

-- 一个小端 32 位字 -> 4 个字节
local function le32(n)
  return char(n % 256, floor(n / P[8]) % 256, floor(n / P[16]) % 256, floor(n / P[24]) % 256)
end

-- 64 位比特长度 -> 8 个字节，还是小端
local function le64(n)
  local lo, hi = n % P[32], floor(n / P[32])
  return le32(lo) .. le32(hi)
end

-- 处理一个 64 字节块，st 原地更新。s 从 off 开始取 64 个字节。
local function transform(st, s, off)
  local M = {}
  for k = 0, 15 do
    local i = off + k * 4
    M[k] = byte(s, i) + byte(s, i + 1) * P[8]
                + byte(s, i + 2) * P[16] + byte(s, i + 3) * P[24]
  end
  local a, b, c, d = st[1], st[2], st[3], st[4]
  for i = 1, 64 do
    local j = i - 1
    local F, g
    if j < 16 then
      F = bor(band(b, c), band(bnot(b), d)); g = j
    elseif j < 32 then
      F = bor(band(d, b), band(bnot(d), c)); g = (5 * j + 1) % 16
    elseif j < 48 then
      F = bxor(bxor(b, c), d);               g = (3 * j + 5) % 16
    else
      F = bxor(c, bor(b, bnot(d)));         g = (7 * j) % 16   -- I = C xor (B or (not D))
    end
    F = rotl(add32(F, a, K[i], M[g]), S[i])
    a, b, c, d = d, add32(b, F), b, c
  end
  st[1] = add32(st[1], a); st[2] = add32(st[2], b)
  st[3] = add32(st[3], c); st[4] = add32(st[4], d)
end

function md5.new()
  return setmetatable({ st = { 0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476 },
    buf = "", n = 0 }, mt)
end

function md5.update(obj, s)
  s = s or ""
  obj.n = obj.n + #s
  local data = obj.buf .. s
  local full = #data - #data % 64
  for off = 1, full, 64 do transform(obj.st, data, off) end
  obj.buf = data:sub(full + 1)
  return obj
end

-- 补位 + 跑完最后的块，返回状态字副本（不动 obj，所以可以反复调用）
local function final_state(obj)
  -- 补到「总长 ≡ 56 (mod 64)」。0x80 自己占一位，所以零的个数是 (55 - n) % 64 而不是 (56 - n) % 64
  local tail = obj.buf .. "\128" .. string.rep("\0", (55 - obj.n) % 64) .. le64(obj.n * 8)
  local tmp = { obj.st[1], obj.st[2], obj.st[3], obj.st[4] }
  for off = 1, #tail, 64 do transform(tmp, tail, off) end
  return tmp
end

function md5.digest(obj)
  local st = final_state(obj)
  return le32(st[1]) .. le32(st[2]) .. le32(st[3]) .. le32(st[4])
end

function md5.finish(obj) return B.hex(md5.digest(obj)) end
function md5.hex(s) return B.hex(md5.digest(md5.update(md5.new(), s or ""))) end

-- 四个 32 位状态字，不做小端 dump：演示「同一份状态、换种字节序就是另一个字符串」。
function md5.state(s)
  local st = final_state(md5.update(md5.new(), s or ""))
  return st[1], st[2], st[3], st[4]
end

md5.EMPTY = "d41d8cd98f00b204e9800998ecf8427e"
md5.ABC = "900150983cd24fb0d6963f7d28e17f72"

return md5
