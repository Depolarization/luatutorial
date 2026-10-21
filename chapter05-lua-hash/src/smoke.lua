-- smoke.lua —— 拷回去就能跑的自检：只认公开标准答案，不依赖答案卷 vectors.lua。
-- 用法：lua src/smoke.lua   （只需要 bitop / crc32 / fnv / md5 四个文件）
-- 期望：五端输出逐字一致，最后一行「全部通过」，退出码 0。

local dir = (arg and arg[0] or ""):match("^(.*)[\\/][^\\/]*$")
package.path = (dir and (dir .. "/?.lua;") or "") .. "?.lua;src/?.lua;" .. package.path

local B = require("bitop")
local crc = require("crc32")
local fnv = require("fnv")
local md5 = require("md5")

local nfail = 0

-- 上一章的老坑在这里又露一次面：#s 数的是字节，%-28s 按字节补空格，
-- 中英混排的标签列就对不齐。上一章用 utf8lite 解的，这里要保持四个文件自包含，
-- 所以按 UTF-8 前缀字节自己数一遍显示宽度。
local function pad(s, w)
  local n, i = 0, 1
  while i <= #s do
    local b = s:byte(i)
    if b < 0x80 then n = n + 1; i = i + 1
    elseif b < 0xE0 then n = n + 1; i = i + 2
    else n = n + 2; i = i + 3 end
  end
  return s .. string.rep(" ", math.max(0, w - n))
end

local function want(what, got, exp)
  local ok = got == exp
  if not ok then nfail = nfail + 1 end
  print("  " .. (ok and "OK" or "!!") .. "  " .. pad(what, 22) .. " " .. tostring(got))
  if not ok then print("          应为 " .. tostring(exp)) end
end

local t0 = os.clock()
print("== smoke @ " .. _VERSION)

-- 一律比十六进制字符串：fengari 的整数只有 32 位，0x80000000 这种字面量在它那儿是负数，
-- 直接拿数字比会在这一端假失败。
print(":: 位运算层")
want("and 0x12345678, 0xFF00", B.hex32(B.band(0x12345678, 0xFF00)), "00005600")
want("or  0xF0F0, 0x0FF0",     B.hex32(B.bor(0xF0F0, 0x0FF0)),      "0000fff0")
want("xor 0x5A5A, 0x0F0F",     B.hex32(B.bxor(0x5A5A, 0x0F0F)),     "00005555")
want("bnot 0",                 B.hex32(B.bnot(0)),                  "ffffffff")
want("lshift 1, 31",           B.hex32(B.lshift(1, 31)),            "80000000")
want("rshift 0xFFFFFFFF, 31",  B.hex32(B.rshift(0xFFFFFFFF, 31)),   "00000001")
want("rotl 0x80000001, 1",     B.hex32(B.rotl(0x80000001, 1)),      "00000003")
want("mul32 最坏进位",          B.hex32(B.mul32(0xFFFFFFFF, 16777619)), "fefffe6d")
local okv, msg = B.verify("pure")
want("纯算术层 2422 项自证", okv and "一致" or msg, "一致")

-- CRC-32/ISO-HDLC：check 值 + 分块 + 接力
print(":: CRC-32")
want('crc32("123456789")', crc.hex("123456789"), "cbf43926")
want("逐位版同值", B.hex32(crc.bitwise("123456789")), "cbf43926")
local c = crc.new(); c:update("12345"); c:update("6789")
want("分两次喂同值", c:finish_hex(), "cbf43926")
local j = crc.new(crc.of("The quick brown "))
j:update("fox jumps over the lazy dog")
want("接力 = 一次喂完", B.hex32(j:finish()), crc.hex("The quick brown fox jumps over the lazy dog"))

-- FNV-1a 32：官方测试向量
print(":: FNV-1a 32")
want('fnv1a32("")',   B.hex32(fnv.fnv1a32("")), "811c9dc5")
want('fnv1a32("a")',  B.hex32(fnv.fnv1a32("a")), "e40c292c")
want('fnv1a32("abc")', B.hex32(fnv.fnv1a32("abc")), "1a47e90b")

print(":: FNV-1a 64")
if fnv.can64 then
  want('fnv1a64("a")', fnv.fnv1a64("a"), "af63dc4c8601ec8c")
else
  print("  -- 这台做不了：" .. select(2, fnv.fnv1a64("a")))
end

-- MD5：RFC 1321 附录里的向量，正好压住 0/1/3 字节这三种补齐长度
print(":: MD5")
want('md5("")',     md5.hex(""),     "d41d8cd98f00b204e9800998ecf8427e")
want('md5("a")',    md5.hex("a"),    "0cc175b9c0f1b6a831c399e269772661")
want('md5("abc")',  md5.hex("abc"),  "900150983cd24fb0d6963f7d28e17f72")
want('md5("hello world")', md5.hex("hello world"), "5eb63bbbe01eeed093cb22bb8f5acdc3")
local m = md5.new(); m:update("hello "); m:update("world")
want("分两次喂同值", m:finish(), "5eb63bbbe01eeed093cb22bb8f5acdc3")

print(string.format("== %s（%.3fs，失败 %d）",
  nfail == 0 and "全部通过" or "有不对的", os.clock() - t0, nfail))
os.exit(nfail == 0 and 0 or 1)
