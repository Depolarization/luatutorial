-- demo.lua : 把 int64 库跑一遍，输出会原样搬到视频的「运行结果」面板
local I = require("int64")

local function show(label, v) print(string.format("%-24s %s", label, v)) end

print("== 1. double 的天花板 ==")
show("2^53 + 1 == 2^53 ?", tostring((2 ^ 53) + 1 == 2 ^ 53))
show("2^53 + 1 =", string.format("%.0f", (2 ^ 53) + 1))

print("")
print("== 2. hi / lo 拆分 ==")
local a = I.fromNumber(2 ^ 53)
show("2^53  ->  hi", "0x" .. I.hex8(a.hi))
show("2^53  ->  lo", "0x" .. I.hex8(a.lo))
show("还原 =", I.tostring(a))

print("")
print("== 3. 加法：低位进位 ==")
local x = I.fromString("18446744073709551615")   -- 2^64 - 1
local y = I.fromString("1")
show("(2^64-1) + 1 =", I.tostring(I.add(x, y)))
show("            hex", I.toHex(I.add(x, y)))

print("")
print("== 4. 减法：借位与二补码 ==")
show("0 - 1      hex", I.toHex(I.sub(I.ZERO, I.ONE)))
show("0 - 1  有符号", I.tostring(I.neg(I.ONE), true))
show("-42    有符号", I.tostring(I.fromString("-42"), true))
show("-42 < 0 ?", tostring(I.slt(I.fromString("-42"), I.ZERO)))

print("")
print("== 5. 乘法：拆 16 位半字 ==")
show("2^32 * 2^32 =", I.tostring(I.mul(I.fromNumber(2 ^ 32), I.fromNumber(2 ^ 32))))
show("123456789 * 987654321", I.tostring(I.mul(I.fromString("123456789"), I.fromString("987654321"))))
show("2^63 * 2 =", I.tostring(I.mul(I.fromNumber(2 ^ 63), I.fromNumber(2))))

print("")
print("== 6. 除法：64 步长除法 ==")
local d = I.fromString("1000000000000000000")
show("10^18 / 7 =", I.tostring(I.div(d, I.fromNumber(7))))
show("10^18 % 7 =", I.tostring(I.mod(d, I.fromNumber(7))))

print("")
print("== 7. 位运算与移位 ==")
local v = I.fromString("12345678901234567890")
show("v        =", I.tostring(v))
show("v   hex  =", I.toHex(v))
show("v << 17  =", I.tostring(I.shl(v, 17)))
show("v >> 17  =", I.tostring(I.shr(v, 17)))
show("v & 255  =", I.tostring(I.band(v, I.fromNumber(255))))
show("~v  hex  =", I.toHex(I.bnot(v)))

print("")
print("== 8. 对照：int64 vs double ==")
local p = I.mul(I.fromString("99999999"), I.fromString("99999999"))
show("int64  =", I.tostring(p))
show("double =", string.format("%.0f", 99999999 ^ 2))
