-- rounding.lua —— 取整与取模：Lua 的 % 不是 C 的 %
local ieee = require("ieee754")

local function n(x) return ieee.exact(x) end

print("== ① floor / ceil 在负数上 ==")
for _, x in ipairs({ 2.5, -2.5, 2.0, -2.0 }) do
  print(string.format("  x=%-6s floor=%-3s ceil=%-3s", n(x), n(math.floor(x)), n(math.ceil(x))))
end
print(string.format("  「四舍五入」写作 floor(x+0.5)：x=-2.5 得 %s（期望 -3，错了）",
  n(math.floor(-2.5 + 0.5))))

print("== ② Lua 的 % 是向下取模，C/Java/JS 的是截断取余 ==")
local cases = { { -7, 3 }, { 7, 3 }, { -7, -3 }, { 7, -3 } }
for _, c in ipairs(cases) do
  print(string.format("  %2d %% %2d = %-3s   math.fmod = %-3s   (C 语言是 %d)",
    c[1], c[2], n(c[1] % c[2]), n(math.fmod(c[1], c[2])),
    (function()
      local q = c[1] / c[2]
      local t = q < 0 and math.ceil(q) or math.floor(q)
      return c[1] - t * c[2]
    end)()))
end
print(string.format("  循环索引靠这个特性：(-3) %% 5 = %s（正好绕回去）", n(-3 % 5)))

print("== ③ 取模撞上小数 ==")
for _, c in ipairs({ { 5, 0.3 }, { 0.3, 0.1 }, { 1, 0.01 } }) do
  local r = c[1] % c[2]
  print(string.format("  %s %% %s → %s", tostring(c[1]), tostring(c[2]), tostring(r)))
  print(string.format("      精确值：%s", ieee.exact(r)))
end
print(string.format("  5 %% 0.3 == 0.2 ? %s   ← 「整除判断」在这种写法下会失灵",
  tostring(5 % 0.3 == 0.2)))

print("== ④ 除法取整的隐藏雷 ==")
print(string.format("  0.3 / 0.1 = %s", ieee.g17(0.3 / 0.1)))
print(string.format("  math.floor(0.3/0.1) = %s  ← 期望 3", n(math.floor(0.3 / 0.1))))
local q = math.floor((2 ^ 53 + 2) / 3)
print(string.format("  math.floor((2^53+2)/3) = %s", n(q)))
print(string.format("  回乘校验  %s × 3 = %s，原值是 %s",
  n(q), n(q * 3), n(2 ^ 53 + 2)))
print("  → 商本身已经是舍入过的 double，第一章 fdiv 的回乘校验就是为它准备的")

print("== ⑤ 整数除法的版本分水岭 ==")
local function eval(src)
  local chunk = (loadstring or load)(src)
  if not chunk then return "<语法不支持>" end
  local ok, v = pcall(chunk)
  if not ok then return "<运行出错>" end
  if type(v) == "number" then return n(v) end
  return tostring(v)
end
print(string.format("  3/2        = %s", eval("return 3/2")))
print(string.format("  3//2       = %s", eval("return 3//2")))
print(string.format("  -7//2      = %s", eval("return -7//2")))
print(string.format("  -7 %% 2     = %s", eval("return -7 % 2")))
print(string.format("  math.floor(-7/2) = %s（两种语言族在负数上分道扬镳）", n(math.floor(-7 / 2))))
