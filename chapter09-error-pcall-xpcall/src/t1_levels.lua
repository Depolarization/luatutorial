-- t1_levels.lua · error 的第二个参数 level：位置前缀到底钉在哪一行
local errkit = require("errkit")

print("== A. 三层调用，level 从 0 数到 6 ==")
local function leaf(lvl)
  local keep = lvl
  error("M", lvl)
end
local function parent(lvl)
  local who = "parent"
  leaf(lvl)
end
local function grand(lvl)
  local who = "grand"
  parent(lvl)
end
for lvl = 0, 6 do
  local ok, e = pcall(grand, lvl)
  print("A level=" .. lvl .. " -> " .. tostring(e))
end

print("== B. 尾调用会把栈帧折叠掉一层 ==")
local function stmt_leaf(lvl)
  local keep = lvl
  error("S", lvl)
end
local function tail_leaf(lvl)
  return error("S", lvl)
end
local function one_up(f, lvl)
  local who = "one_up"
  f(lvl)
end
local function tail_up(f, lvl)
  return f(lvl)
end
for lvl = 1, 3 do
  local combos = {
    { "中间层非尾调用 + 叶子非尾调用", one_up, stmt_leaf },
    { "中间层尾调用   + 叶子非尾调用", tail_up, stmt_leaf },
    { "中间层非尾调用 + 叶子尾调用  ", one_up, tail_leaf },
    { "中间层尾调用   + 叶子尾调用  ", tail_up, tail_leaf },
  }
  for i = 1, #combos do
    local c = combos[i]
    local ok, e = pcall(c[2], c[3], lvl)
    print("B " .. c[1] .. " level=" .. lvl .. " -> " .. tostring(e))
  end
end

print("== C. level 取浮点 / 字符串 / 布尔 / 负数 / nil ==")
local cases = {}
cases[#cases + 1] = { "1", 1 }
cases[#cases + 1] = { "1.7", 1.7 }
cases[#cases + 1] = { "\"2\"", "2" }
cases[#cases + 1] = { "true", true }
cases[#cases + 1] = { "-1", -1 }
cases[#cases + 1] = { "nil", nil }
for i = 1, #cases do
  local ok, e = pcall(function(lv)
    local keep = lv
    error("V", lv)
  end, cases[i][2])
  print("C level=" .. cases[i][1] .. " -> " .. tostring(e))
end

print("== D. 同一处崩溃，十种抛法 ==")
local function scene(name, fn)
  local cfg = { hp = 30, name = "boss" }
  local ok, e = pcall(fn)
  print("D " .. name .. " -> " .. errkit.describe(e) .. " [" .. type(e) .. "]")
end
scene("error(string),     ", function() error("no such item") end)
scene("error(string,0),   ", function() error("no such item", 0) end)
scene("error(table),      ", function() error({ code = 404, msg = "no such item" }) end)
scene("error(tbl,2),      ", function() error({ code = 404, msg = "no such item" }, 2) end)
scene("assert(false,msg), ", function() return assert(false, "no such item") end)
scene("assert(false,tbl), ", function() return assert(false, { code = 404 }) end)
scene("assert(nil),       ", function() return assert(nil) end)
scene("error(nil),        ", function() error(nil) end)
scene("error(false),      ", function() error(false) end)
scene("math.sqrt(str),    ", function() return math.sqrt("no such item") end)

print("== E. 位置前缀的有无 ==")
local ok_a, e_a = pcall(function() error("no such item") end)
local ok_b, e_b = pcall(function() error("no such item", 0) end)
local ok_c, e_c = pcall(function() error({ a = 1 }) end)
print("E 默认抛法前 24 字符 -> [" .. tostring(tostring(e_a):sub(1, 24)) .. "]")
print("E 字符串错误 有前缀 -> " .. tostring(tostring(e_a):find(":%d+:") ~= nil))
print("E level=0    有前缀 -> " .. tostring(tostring(e_b):find(":%d+:") ~= nil))
print("E 表错误对象 有前缀 -> " .. tostring(tostring(e_c):find(":%d+:") ~= nil))
