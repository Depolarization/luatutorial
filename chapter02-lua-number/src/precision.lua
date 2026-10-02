-- precision.lua —— double 的解剖图，以及整数安全区 2^53
local ieee = require("ieee754")

print("== ① 一个 double 的三行位（符号 1 / 指数 11 / 尾数 52）==")
for _, v in ipairs({ 5, 0.1, 2 ^ 53 }) do
  local b = ieee.bits(v)
  print(string.format("  x = %s", ieee.exact(v)))
  print(string.format("    s=%s  e=%s(%+d)  f=%s...", b.s, b.e, b.exp_unbiased, b.f:sub(1, 24)))
end

print("== ② 反直觉开场：两个不相等的整数相等 ==")
local a, b = 9007199254740992, 9007199254740993
print(string.format("  2^53        字面量 = %s", ieee.exact(a)))
print(string.format("  2^53+1      字面量 = %s", ieee.exact(b)))
print(string.format("  两者相等？          %s", tostring(a == b)))

print("== ③ 浮点加法路径：连 5.3 也照样失真 ==")
local big = 2 ^ 53
print(string.format("  2^53 + 1 == 2^53 ?     %s", tostring(big + 1 == big)))
print(string.format("  2^53 + 2 == 2^53 ?     %s", tostring(big + 2 == big)))
print(string.format("  2^53 + 3 实际存成 %s", ieee.exact(big + 3)))
print(string.format("  2^53 + 2 == 2^53 + 4 ? %s", tostring(big + 2 == big + 4)))

print("== ④ 整数间隔阶梯（* 基准，+ 表示这个数活下来了，. 表示被吃掉）==")
for k = 52, 60 do
  local base = 2 ^ k
  local gap = ieee.ulp(base)
  local marks = {}
  for j = 0, 15 do
    if j == 0 then
      marks[#marks + 1] = "*"
    else
      marks[#marks + 1] = ((base + j) - base == j) and "+" or "."
    end
  end
  print(string.format("  2^%-2d 间隔=%-6s %s", k, ieee.pow2_name(gap), table.concat(marks)))
end

print("== ⑤ 一把尺子：各数量级的 1 ulp ==")
for _, e in ipairs({ -2, 0, 1, 52, 53, 62 }) do
  local v = 2 ^ e
  print(string.format("  x=2^%-3d  ulp=%-6s 即 %s", e, ieee.pow2_name(ieee.ulp(v)), ieee.exact(ieee.ulp(v))))
end
print(string.format("  机器精度 eps = %s", ieee.pow2_name(ieee.machine_eps())))

print("== ⑥ 现实世界的分界线 ==")
print(string.format("  2^53 = %s", ieee.exact(big)))
print(string.format("  今天毫秒时间戳 1790000000000 距上界还有 %s 倍",
  ieee.exact(math.floor(big / 1790000000000))))
print(string.format("  2^53 毫秒 约 %s 年", tostring(math.floor(big / 86400000 / 365))))
print(string.format("  雪花ID 量级 7e17 超过 2^53？ %s", tostring(7 * 10 ^ 17 > big)))
print("  → 一旦超过 2^53，加减就开始吃数，必须拆 hi/lo（第一章的方案）")
