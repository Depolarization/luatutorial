-- crc32.lua —— 标准 CRC-32（zlib/PNG 那个），逐位版和查表版各写一遍。
-- 多项式 0xEDB88320 是 0x04C11DB7 的位镜像：反射版从最低位往外移，
-- 所以它算出来的结果才和 zlib.crc32 / md5sum 的兄弟 cksum 家族里的 POSIX 版不一样。

local B = require("bitop")
local band, bxor, rshift, lshift = B.band, B.bxor, B.rshift, B.lshift
local byte = string.byte

local POLY_REV = 0xEDB88320          -- 反射多项式
local POLY_FWD = 0x04C11DB7          -- 正向多项式（同一个东西的另一种位序）
local MASK = B.MASK                  -- 0xFFFFFFFF

local crc32 = { POLY_REV = POLY_REV, POLY_FWD = POLY_FWD }

-- 逐位：一个字节做 8 次「取最低位 → 右移 → 有条件异或多项式」
local function update_bit(crc, s)
  for i = 1, #s do
    crc = bxor(crc, byte(s, i))
    for _ = 1, 8 do
      local low = band(crc, 1)          -- 等价于 crc % 2，但用位运算层写才讲得通
      crc = rshift(crc, 1)
      if low == 1 then crc = bxor(crc, POLY_REV) end
    end
  end
  return crc
end

-- 查表：把「一个字节连做 8 次」的结果先算好存进 256 项表，之后每字节只剩三次操作
local TAB
local function table_()
  if TAB then return TAB end
  TAB = {}
  for i = 0, 255 do
    TAB[i] = update_bit(0, string.char(i))   -- 就用逐位版给表灌数据，两版天然同源
  end
  return TAB
end
crc32.table = table_

local function update_tab(crc, s)
  local t = table_()
  for i = 1, #s do
    crc = bxor(rshift(crc, 8), t[band(bxor(crc, byte(s, i)), 0xFF)])
  end
  return crc
end

-- 正向位序：多项式不镜像、从左往右移。这个结果和 zlib 对不上，是故意留着当对照的。
local function update_msb(crc, s)
  for i = 1, #s do
    crc = bxor(crc, lshift(byte(s, i), 24))
    for _ = 1, 8 do
      local high = band(crc, 0x80000000)
      crc = lshift(crc, 1)            -- lshift 自带截断，不用再 and 一次
      if high ~= 0 then crc = bxor(crc, POLY_FWD) end
    end
  end
  return crc
end

function crc32.bitwise(s) return bxor(update_bit(MASK, s or ""), MASK) end
function crc32.of(s) return bxor(update_tab(MASK, s or ""), MASK) end
function crc32.msb(s) return bxor(update_msb(MASK, s or ""), MASK) end
function crc32.hex(s) return B.hex32(crc32.of(s)) end

-- 分块接口：大文件不可能一次读进来，update/finish 才是能用的形态
local mt = { __index = crc32 }

function crc32.new(seed)
  return setmetatable({ crc = bxor(seed or 0, MASK), n = 0, tab = true }, mt)
end

function crc32.update(obj, s)
  obj.crc = obj.tab and update_tab(obj.crc, s) or update_bit(obj.crc, s)
  obj.n = obj.n + #s
  return obj
end

function crc32.finish(obj) return bxor(obj.crc, MASK) end
function crc32.finish_hex(obj) return B.hex32(crc32.finish(obj)) end

-- 标准自检值：CRC-32/ISO-HDLC 的 check 是 0xCBF43926，"123456789" 一跑就知道有没有写反
crc32.CHECK = "123456789"
crc32.CHECK_HEX = "cbf43926"

return crc32
