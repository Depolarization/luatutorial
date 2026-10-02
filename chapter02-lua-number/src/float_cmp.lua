-- float_cmp.lua —— 小数为什么算不准：0.1 的真身与它的连锁反应
local ieee = require("ieee754")

print("== ① 老问题：0.1 + 0.2 ==")
print(string.format("  0.1 + 0.2 == 0.3 ?  %s", tostring(0.1 + 0.2 == 0.3)))
print(string.format("  %%17g 0.1      = %s", ieee.g17(0.1)))
print(string.format("  %%17g 0.2      = %s", ieee.g17(0.2)))
print(string.format("  %%17g 0.1+0.2  = %s", ieee.g17(0.1 + 0.2)))
print(string.format("  %%17g 0.3      = %s", ieee.g17(0.3)))

print("== ② tostring 会不会骗你 ==")
print(string.format("  tostring(0.1+0.2) = %s", tostring(0.1 + 0.2)))
print(string.format("  精确值 0.1  = %s", ieee.exact(0.1)))
print(string.format("  精确值 0.2  = %s", ieee.exact(0.2)))
print(string.format("  精确值 0.3  = %s", ieee.exact(0.3)))
print(string.format("  精确值 0.1+0.2 = %s", ieee.exact(0.1 + 0.2)))

print("== ③ 0.1 在二进制里是无限循环小数 ==")
local bits, cyc = ieee.binary_frac(1, 10, 32)
print(string.format("  1/10 = 0.%s ...", bits))
if cyc > 0 then
  local rep = bits:sub(cyc, cyc + 3)
  print(string.format("  循环节：从第 %d 位起，%s 这 4 个比特无限重复", cyc, rep))
end
print(string.format("  存进 double 只能截到 53 位，误差就此诞生"))

print("== ④ 误差不只一次，会累加 ==")
local s = 0
for i = 1, 10 do s = s + 0.1 end
print(string.format("  十个 0.1 连加 = %s（== 1 ? %s）", ieee.g17(s), tostring(s == 1)))
print(string.format("  0.1 * 3 == 0.3 ? %s   (%s vs %s)",
  tostring(0.1 * 3 == 0.3), ieee.g17(0.1 * 3), ieee.g17(0.3)))
print(string.format("  0.7 * 10 == 7 ? %s   (%s)", tostring(0.7 * 10 == 7), ieee.g17(0.7 * 10)))
print(string.format("  (0.1+0.2)-0.2 == 0.1 ? %s", tostring((0.1 + 0.2) - 0.2 == 0.1)))

print("== ⑤ 正确的比法：绝对误差 / 相对误差 ==")
local eps = ieee.machine_eps()
print(string.format("  用 2^-52 当尺：|差| = %s", ieee.g17(math.abs((0.1 + 0.2) - 0.3))))
print(string.format("  绝对容差 1e-9 下相等？ %s", tostring(math.abs((0.1 + 0.2) - 0.3) < 1e-9)))
print(string.format("  相对容差 4*eps 下相等？ %s",
  tostring(math.abs((0.1 + 0.2) - 0.3) <= 4 * eps * math.abs(0.3))))

print("== ⑥ 钱该怎么存：换成整数分 ==")
local yuan = 0.1
print(string.format("  0.1 元 用 float 存 → %s", ieee.g17(yuan)))
print(string.format("  改成 10 分（整数）→ %s，运算精确", ieee.exact(10)))
print(string.format("  5.1 里整数分的安全上限：2^53 分 ≈ %s 元",
  ieee.exact(math.floor(2 ^ 53 / 100))))
