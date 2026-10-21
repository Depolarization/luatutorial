-- demo.lua —— 把「在 Lua 5.1 上写哈希」这件事按顺序演示一遍。
-- 这份文件的输出就是视频里「运行结果」面板的素材，所以每一行都必须是真的跑出来的。

local dir = (arg and arg[0] or ""):match("^(.*)[\\/][^\\/]*$")
package.path = (dir and (dir .. "/?.lua;") or "") .. "?.lua;src/?.lua;" .. package.path

local B = require("bitop")
local crc = require("crc32")
local fnv = require("fnv")
local md5 = require("md5")

local clock = os.clock
local loader = loadstring or load

-- os.clock 的分辨率很粗，这台机器上还随时有别的东西在跑。
-- 取平均会被随机冒出来的停顿拖高，倍数一次一个样；改成几个函数在同一轮里交替跑、
-- 各取最快的一次：最快那次才是这段代码自己的耗时。轮数一并打出来，方便核对。
local function timed(f)
  local t0 = clock(); f(); return clock() - t0
end

local function best(...)
  local fs = { ... }
  local t = {}
  for i = 1, #fs do t[i] = math.huge end
  local probe = 0
  for i = 1, #fs do
    local dt = timed(fs[i])
    if dt < t[i] then t[i] = dt end
    probe = probe + dt
  end
  local rounds = math.max(1, math.min(5, math.floor(1.5 / math.max(probe, 0.001))))
  for _ = 1, rounds do
    for i = 1, #fs do
      local dt = timed(fs[i])
      if dt < t[i] then t[i] = dt end
    end
  end
  return t, rounds + 1
end

print("== 运行在 " .. _VERSION)
print(string.format("  bit32=%s  位运算符=%s  纯算术层=%s  能做 64 位=%s",
  type(bit32), loader("return 1 & 1") and "有" or "没有",
  B.implementation, tostring(fnv.can64)))
local names = {}
for _, k in ipairs(B.available()) do names[#names + 1] = k end
print("  可用后端: " .. table.concat(names, " / "))

print("")
print(":: 1) 三种写法的 FNV-1a 32，只差在乘法怎么处理")
local S1 = "The quick brown fox jumps over the lazy dog"
local function fnv_textbook(s)               -- 教程里最常见的那一行
  local h = 0x811c9dc5
  for i = 1, #s do h = B.bxor(h, s:byte(i)) * 16777619 % 2^32 end
  return h
end
local function fnv_naive(s)                  -- 模数换成整数（连乘表里的 2^32）
  local h = 0x811c9dc5
  for i = 1, #s do h = B.u32(B.bxor(h, s:byte(i)) * 16777619) end
  return h
end
local right = B.hex32(fnv.fnv1a32(S1))
print(string.format("  拆半字 mul32   %s   <- bitop 给的", right))
print(string.format("  直接乘+整数模  %s  %s", B.hex32(fnv_naive(S1)),
  B.hex32(fnv_naive(S1)) == right and "对" or "错"))
print(string.format("  直接乘+2^32模  %s  %s   <- 2^32 是浮点", B.hex32(fnv_textbook(S1)),
  B.hex32(fnv_textbook(S1)) == right and "对" or "错"))

print("")
print(":: 2) CRC-32：同一份数据，逐位 / 查表 / 分块接力 / 正向位序")
local chk = crc.CHECK
print(string.format("  逐位      %s", B.hex32(crc.bitwise(chk))))
print(string.format("  查表      %s", crc.hex(chk)))
local o = crc.new(); o:update("12345"); o:update("6789")
print(string.format("  分两次喂  %s", o:finish_hex()))
print(string.format("  正向位序  %s   <- 和 zlib 对不上，多项式没镜像而已", B.hex32(crc.msb(chk))))
print(string.format("  标准答案  %s   <- CRC-32/ISO-HDLC 的 check 值", crc.CHECK_HEX))
print(string.format("  256 项表已经生成，前 4 项 %s %s %s %s",
  B.hex32(crc.table()[0]), B.hex32(crc.table()[1]),
  B.hex32(crc.table()[2]), B.hex32(crc.table()[3])))

print("")
print(":: 3) 逐位 vs 查表，慢多少")
local big = string.rep(S1 .. "\010", 700)
local cb = B.hex32(crc.bitwise(big))
local ct = crc.hex(big)
local t3, rounds3 = best(function() return B.hex32(crc.bitwise(big)) end,
                          function() return crc.hex(big) end)
print(string.format("  %d 字节  逐位最快 %.3fs  查表最快 %.3fs  交替 %d 轮  结果一致=%s  慢 %.1fx",
  #big, t3[1], t3[2], rounds3, tostring(cb == ct), t3[2] > 0 and t3[1] / t3[2] or 0))

print("")
print(":: 4) MD5 的字节序：状态一样，dump 方式不一样就是两个字符串")
local a, b, c, d = md5.state("abc")
print(string.format("  四个状态字          %s %s %s %s",
  B.hex32(a), B.hex32(b), B.hex32(c), B.hex32(d)))
print(string.format("  标准输出(小端逐字节) %s", md5.hex("abc")))
print(string.format("  照抄成字(大端逐字)   %s%s%s%s   <- 这样输出就全错了",
  B.hex32(a), B.hex32(b), B.hex32(c), B.hex32(d)))

print("")
print(":: 5) 大文件分块：切在哪儿都不该影响结果")
local whole = md5.hex(big)
print(string.format("  一次喂完 %d 字节 -> %s", #big, whole))
for _, cut in ipairs({ 1, 7, 56, 64, 65, 4093 }) do
  local m = md5.new()
  m:update(big:sub(1, cut)); m:update(big:sub(cut + 1, cut + 999))
  m:update(big:sub(cut + 1000))
  local got = m:finish()
  print(string.format("  切成 %5d/%4d/%d -> %s  %s", cut, 999, #big - cut - 999,
    got, got == whole and "一致" or "不一致"))
end

print("")
print(":: 6) 64 位哈希在只有 double 的世界")
if fnv.can64 then
  local limb = fnv.fnv1a64(S1)
  local nat = fnv.native64 and fnv.native64(S1) or nil
  print(string.format("  手搭 limb 的 FNV-1a64 = %s", limb))
  print(string.format("  原生 int64 六个字符版 = %s  一致=%s",
    nat or "这台没有 int64", nat and tostring(limb == nat) or "n/a"))
else
  local why = select(2, fnv.fnv1a64("a"))
  print("  " .. tostring(why))
end
print(string.format("  对照：FNV-1a32 同一个串 = %s", B.hex32(fnv.fnv1a32(S1))))

print("")
print(":: 7) 本机三家的答案")
print(string.format("  crc32  %s", crc.hex(S1)))
print(string.format("  fnv32  %s", B.hex32(fnv.fnv1a32(S1))))
print(string.format("  md5    %s", md5.hex(S1)))

print("")
print(":: 8) 三种算法跑同一个缓冲区，各花多少时间")
local c1 = function() return crc.hex(big) end
local f1 = function() return B.hex32(fnv.fnv1a32(big)) end
local m1 = function() return md5.hex(big) end
local t8, rounds8 = best(c1, f1, m1)
print(string.format("  %d 字节，取最快   crc32 %.3fs   fnv1a32 %.3fs   md5 %.3fs   交替 %d 轮",
  #big, t8[1], t8[2], t8[3], rounds8))
local function ratio(a, b) return b > 0 and a / b or 0 end
print(string.format("  md5 / crc32 = %.1f 倍，md5 / fnv1a32 = %.1f 倍",
  ratio(t8[3], t8[1]), ratio(t8[3], t8[2])))
print(string.format("  吞吐量 字节/秒   crc32 %.0f   fnv1a32 %.0f   md5 %.0f",
  ratio(#big, t8[1]), ratio(#big, t8[2]), ratio(#big, t8[3])))
print(string.format("  三个答案  %s / %s / %s", c1(), f1(), m1()))
