-- test.lua —— 答案卷对拍。每端各跑一遍，输出应当逐字节一致。
-- 用法：lua test.lua（在 src/ 目录里直接跑，不需要任何第三方库）

-- 直接从 src/ 里跑，或者从工程根跑 src/test.lua，两种都认
local dir = (arg and arg[0] or ""):match("^(.*)[\\/][^\\/]*$")
package.path = (dir and (dir .. "/?.lua;") or "") .. "?.lua;src/?.lua;" .. package.path

local B = require("bitop")
local crc = require("crc32")
local fnv = require("fnv")
local md5 = require("md5")
local V = require("vectors")

local npass, nfail, nskip = 0, 0, 0
local bad = {}

local function check(what, got, want)
  if got == want then
    npass = npass + 1
  else
    nfail = nfail + 1
    if #bad < 12 then bad[#bad + 1] = string.format("%s：得 %s，应为 %s", what, tostring(got), want) end
  end
end

local function note_skip(what, why)
  nskip = nskip + 1
  print(string.format("  跳过 %s —— %s", what, why))
end

print("== 运行在 " .. _VERSION)

print(":: 位运算层自证")
for _, name in ipairs(B.available()) do
  local ok, msg = B.verify(name)
  check("后端 " .. name .. " 与纯算术版一致", ok, true)
  print(string.format("  %-8s %s", name, msg))
end
if B.native_note then print("  native   " .. B.native_note) end

print(":: 逐位 vs 查表（同一张表灌出来的两版 CRC）")
for _, v in ipairs(V) do
  check("crc32 查表 " .. v.name, crc.hex(v.data), v.crc32)
  check("crc32 逐位 " .. v.name, B.hex32(crc.bitwise(v.data)), v.crc32)
  local o = crc.new()
  o:update(v.data)
  check("crc32 分块 " .. v.name, o:finish_hex(), v.crc32)
end
print(string.format("  表已生成 %d 项，table[255] = %s", 256, B.hex32(crc.table()[255])))
print("  正向位序（故意不兼容 zlib）：123456789 -> " .. B.hex32(crc.msb("123456789")))

print(":: FNV")
for _, v in ipairs(V) do
  check("fnv1a32 " .. v.name, B.hex32(fnv.fnv1a32(v.data)), v.fnv1a32)
end
if fnv.can64 then
  for _, v in ipairs(V) do
    check("fnv1a64 " .. v.name, fnv.fnv1a64(v.data), v.fnv1a64)
  end
else
  note_skip("fnv1a64", "这台整数只有 32 位，16 位 limb 相乘会回绕")
end
if fnv.native64 then
  for _, v in ipairs(V) do
    check("fnv1a64 原生 int64 对照 " .. v.name, fnv.native64(v.data), v.fnv1a64)
  end
else
  note_skip("原生 int64 对照", fnv.native64_note or "这台没有可用的 64 位整数")
end

print(":: MD5")
local kdiff = (function()
  local k2 = md5.deriveK()
  for i = 1, 64 do
    if k2[i] ~= md5.K[i] then
      return "第 " .. i .. " 个不同（写死 " .. tostring(md5.K[i]) .. " vs 现算 " .. tostring(k2[i]) .. "）"
    end
  end
  return nil
end)()
check("K 表和 sin 现算一致", kdiff, nil)
print(string.format("  K 表 64 项 vs floor(2^32*|sin i|)   %s", kdiff or "逐个相同"))

local cuts = { 0, 1, 3, 7, 16, 55, 56, 57, 63, 64, 65, 127, 128 }
for _, v in ipairs(V) do
  check("md5 " .. v.name, md5.hex(v.data), v.md5)
  for _, c in ipairs(cuts) do
    if c > 0 and c < #v.data then
      local o = md5.new()
      o:update(v.data:sub(1, c))
      o:update(v.data:sub(c + 1))
      check(string.format("md5 分块@%d %s", c, v.name), o:finish(), v.md5)
      local o2 = md5.new()
      o2:update(v.data:sub(1, c))
      o2:update(v.data:sub(c + 1, c + 1))
      o2:update(v.data:sub(c + 2))
      check(string.format("md5 三分块@%d %s", c, v.name), o2:finish(), v.md5)
    end
  end
end

print(":: 补位边界：零的个数是 (55-n) mod 64，补完必须是整块")
local edge = { [55]=1, [56]=1, [57]=1, [63]=1, [64]=1, [65]=1, [127]=1, [128]=1, [129]=1 }
for _, v in ipairs(V) do
  if v.name:match("^NUL") and edge[v.n] then
    local z = (55 - v.n) % 64
    local total = v.n + 1 + z + 8
    check("补完是整块 " .. v.name, total % 64, 0)
    print(string.format("  n=%-4d 零=%-3d 补完=%-4d 共 %d 块", v.n, z, total, math.floor(total / 64)))
  end
end

print(":: CRC 接力（上一块的余值当下一块的种子）")
do
  local a, b = "The quick brown ", "fox jumps over the lazy dog"
  local c1 = crc.of(a)
  local o = crc.new(c1)
  o:update(b)
  check("crc32 接力", B.hex32(o:finish()), crc.hex(a .. b))
  print(string.format("  前半句余值 %s -> 续算后半句 %s   整句一次算完 %s   %s",
    B.hex32(c1), B.hex32(o:finish()), crc.hex(a .. b),
    B.hex32(o:finish()) == crc.hex(a .. b) and "一致" or "不一致"))
end

print(string.format("== 合计 通过 %d，失败 %d，跳过 %d", npass, nfail, nskip))
for _, m in ipairs(bad) do print("   ! " .. m) end
os.exit(nfail == 0 and 0 or 1)
