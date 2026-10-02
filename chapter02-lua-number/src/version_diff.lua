-- version_diff.lua —— 同一段代码，5.1 与 5.3 跑出不同结果
-- 输出格式：标签<TAB>结果<TAB>类型<TAB>源码，方便网页按标签把各版本拼成对照表
local ieee = require("ieee754")

local has_mt = math.type ~= nil

local function short_err(msg)
  msg = tostring(msg)
  if msg:find("integer representation") then return "<报错·无法转整数>" end
  if msg:find("attempt to call") then return "<报错·无此函数>" end
  if msg:find("attempt to perform") then return "<报错·nil 参与运算>" end
  if msg:find("'then'") or msg:find("expected") then return "<语法不支持>" end
  return "<报错>"
end

local function show(v)
  if type(v) ~= "number" then return tostring(v), "-" end
  local txt
  if has_mt and math.type(v) == "integer" then
    txt = tostring(v)                       -- 整数子类型本来就是精确十进制
  else
    txt = ieee.exact(v)
  end
  return txt, (math.type and math.type(v)) or "number"
end

local rows = {}
local function probe(label, src, raw)
  local chunk = (loadstring or load)(src)
  if not chunk then
    rows[#rows + 1] = { label, "<语法不支持>", "-", src }
    return
  end
  local ok, v = pcall(chunk)
  if not ok then
    rows[#rows + 1] = { label, short_err(v), "-", src }
    return
  end
  if raw then
    rows[#rows + 1] = { label, tostring(v), type(v), src }
  else
    local txt, ty = show(v)
    rows[#rows + 1] = { label, txt, ty, src }
  end
end

print("== 一、整数：5.3 的子类型到底救了谁 ==")
probe("字面量 2^53+1", "return 9007199254740993")
probe("它 == 2^53 ？", "return 9007199254740993 == 2^53")
probe("字面量 + 1（纯整数）", "return 9007199254740993 + 1")
probe("字面量 + 0（纯整数）", "return 9007199254740993 + 0")
probe("字面量 + 0.0（混浮点）", "return 9007199254740993 + 0.0")
probe("字面量 // 1（整除）", "return 9007199254740993 // 1")
probe("2^53 + 1（power 是浮点）", "return 2^53 + 1")
probe("它的 math.type", "return math.type(9007199254740993)")
probe("math.type 存在？", "return math.type ~= nil")

print("== 二、除法与取整 ==")
probe("3/2", "return 3/2")
probe("4/2 的类型", "return math.type(4/2)")
probe("3//2", "return 3//2")
probe("7.0//2", "return 7.0//2")
probe("math.floor(3.7)", "return math.floor(3.7)")
probe("tostring(10/2)", "return tostring(10/2)", true)
probe("tostring(1/3)", "return tostring(1/3)", true)

print("== 三、位运算与溢出 ==")
probe("5 & 3", "return 5 & 3")
probe("1 << 40", "return 1 << 40")
probe("bit32.band(5,3)", "return bit32.band(5, 3)")
probe("math.maxinteger", "return math.maxinteger")
probe("maxinteger + 1（回绕？）", "return math.maxinteger + 1")
probe("string.format('%d', 3.5)", "return string.format('%d', 3.5)")
probe("string.format('%d', 2^53)", "return string.format('%d', 2^53)")

print("== 四、double 的锅，5.3 也不背 ==")
probe("0.1 + 0.2 == 0.3", "return 0.1 + 0.2 == 0.3")
probe("0.1 + 0.2", "return 0.1 + 0.2")
probe("5 % 0.3", "return 5 % 0.3")
probe("-7 % 3", "return -7 % 3")
probe("math.fmod(-7, 3)", "return math.fmod(-7, 3)")

print("== 五、字符串与长度（顺带一提的坑）==")
probe("utf8 库存在？", "return utf8 ~= nil")
probe("#'中文'", "return #'中文'")

print("== 汇总表（标签|结果|类型|源码）==")
for _, r in ipairs(rows) do
  print(string.format("%s|%s|%s|%s", r[1], r[2], r[3], r[4]))
end
