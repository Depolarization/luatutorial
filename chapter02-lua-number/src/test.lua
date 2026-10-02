-- test.lua —— 跨版本自检：每条断言都在真实解释器上跑，期望值由 Python 的 Decimal 独立算出
local ieee = require("ieee754")

local has_mt = math.type ~= nil
local pass, fails = 0, {}

local function check(desc, got, want)
  if got == want then
    pass = pass + 1
  else
    fails[#fails + 1] = string.format("    ✗ %s\n      得到 %s\n      期望 %s",
      desc, tostring(got), tostring(want))
  end
end

print("== 与版本无关：double 的真值 ==")
check("0.1 的精确十进制", ieee.exact(0.1),
  "0.1000000000000000055511151231257827021181583404541015625")
check("0.2 的精确十进制", ieee.exact(0.2),
  "0.200000000000000011102230246251565404236316680908203125")
check("0.3 的精确十进制", ieee.exact(0.3),
  "0.299999999999999988897769753748434595763683319091796875")
check("0.1+0.2 的精确十进制", ieee.exact(0.1 + 0.2),
  "0.3000000000000000444089209850062616169452667236328125")
check("精确值能原样读回", tostring(tonumber(ieee.exact(0.1)) == 0.1), "true")
check("2^53+3 被舍到", ieee.exact(2 ^ 53 + 3), "9007199254740996")
check("0.1 的指数域", ieee.bits(0.1).e, "01111111011")
check("0.1 的尾数域", ieee.bits(0.1).f,
  "1001100110011001100110011001100110011001100110011010")
check("5 的指数域", ieee.bits(5).e, "10000000001")

print("== 与版本无关：尺子与取整 ==")
check("ulp(1)", ieee.pow2_name(ieee.ulp(1)), "2^-52")
check("ulp(2^53)", ieee.exact(ieee.ulp(2 ^ 53)), "2")
check("ulp(2^62)", ieee.exact(ieee.ulp(2 ^ 62)), "1024")
check("机器精度", ieee.pow2_name(ieee.machine_eps()), "2^-52")
check("1+eps 不等于 1", tostring(1 + ieee.machine_eps() ~= 1), "true")
check("1+eps/2 等于 1", tostring(1 + ieee.machine_eps() / 2 == 1), "true")
check("2^53+1 == 2^53（浮点加法）", tostring(2 ^ 53 + 1 == 2 ^ 53), "true")
check("-7 % 3（Lua 向下取模）", ieee.exact(-7 % 3), "2")
check("math.fmod(-7,3)（C 语义）", ieee.exact(math.fmod(-7, 3)), "-1")
check("floor(-2.5)", ieee.exact(math.floor(-2.5)), "-3")
check("floor(0.3/0.1)", ieee.exact(math.floor(0.3 / 0.1)), "2")
check("0.1+0.2 不等于 0.3", tostring(0.1 + 0.2 ~= 0.3), "true")
local bf, cyc = ieee.binary_frac(1, 10, 40)
check("1/10 的二进制前缀", bf:sub(1, 4), "0001")
check("1/10 循环节起点", cyc, 2)

print("== 分版本：5.3 的整数子类型 ==")
-- 5.3 的新语法（// 、<< 、maxinteger）在 5.1 里连编译都过不去，
-- 必须用 load 在运行时编译，pcall 兜住，这样同一个文件能在所有版本里跑
local function run(src)
  local chunk = (loadstring or load)(src)
  if not chunk then return "<语法不支持>" end
  local ok, v = pcall(chunk)
  if not ok then return "<报错>" end
  return tostring(v)
end

check("字面量 2^53+1 存不存得下", run("return 9007199254740993 == 2^53"),
  has_mt and "false" or "true")
check("纯整数 +1 是否保精确", run("return 9007199254740993 + 1 == 9007199254740994"),
  has_mt and "true" or "false")
check("混进 0.0 后失真", run("return 9007199254740993 + 0.0 == 2^53"), "true")
check("整数子类型可见", run("return math.type and math.type(9007199254740993) or '无'"),
  has_mt and "integer" or "无")
check("混浮点后被打回", run("return math.type and math.type(9007199254740993 + 0.0) or '无'"),
  has_mt and "float" or "无")
check("3//2", run("return 3//2"), has_mt and "1" or "<语法不支持>")
check("7.0//2 的类型", run("return math.type(7.0//2)"), has_mt and "float" or "<语法不支持>")
check("maxinteger+1 回绕", run("return math.maxinteger + 1"),
  has_mt and "-9223372036854775808" or "<报错>")
check("1<<40", run("return 1 << 40"), has_mt and "1099511627776" or "<语法不支持>")
check("format %d 遇到 3.5", run([[return string.format("%d", 3.5)]]),
  has_mt and "<报错>" or "3")

print(string.format("自检结论：%d 条断言通过，%d 条失败（%s）",
  pass, #fails, _VERSION))
for _, f in ipairs(fails) do print(f) end
if #fails > 0 then error("自检未通过", 0) end
