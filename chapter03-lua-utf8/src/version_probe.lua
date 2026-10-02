--[[
  version_probe.lua : 版本分歧清单
  同一份文件在 Lua 5.1.5 / fengari(Lua 5.3) / Lua 5.4.8 上跑，
  输出直接告诉观众：标准库不只是「有没有」，还「每版语义都不同」。
]]
local U = require("utf8lite")

local function fmt(label, val)
  print(string.format("%-24s %s", label, tostring(val)))
end

local function bytes(s)
  if type(s) ~= "string" then return tostring(s) end
  local o = {}
  for k = 1, #s do o[k] = s:byte(k) end
  return "[" .. table.concat(o, ",") .. "]"
end

-- 出错记 ERR；返回 nil 时把第二个返回值（错误位置）一起带上
local function rets(f, ...)
  local ok, a, b = pcall(f, ...)
  if not ok then return "ERR" end
  if a == nil then return "nil@" .. tostring(b) end
  return tostring(a)
end
local function nat(f, ...)
  if type(utf8) ~= "table" then return "无库" end
  return rets(f, ...)
end

print("### " .. _VERSION .. " ###")
fmt("type(bit32)", type(bit32))
fmt("type(utf8)", type(utf8))
if type(utf8) ~= "table" then
  fmt("字节数 #'a中b'", #"a中b")
  fmt("自写库 U.len('a中b')", U.len("a中b"))
  print("  -> 5.1/5.2 连 utf8 库都没有，只能自己写")
  return
end

-- 分歧 1：代理区码点算不算合法
fmt("len 代理区 ED A0 80", nat(utf8.len, "\237\160\128"))
-- 分歧 2：lax 第 4 参数（5.4 才有）；用 0x110000 这个超范围码点来区分
fmt("len F4 90 80 80 (0x110000)", nat(utf8.len, "\244\144\128\128"))
fmt("  + lax=true", nat(utf8.len, "\244\144\128\128", 1, 4, true))
fmt("是否支持 lax", nat(utf8.len, "\244\144\128\128", 1, 4, true) == "1" and "是" or "否")
-- 分歧 3：codepoint 不传 j 时只解一个字符（5.3/5.4 相同，容易误以为解全串）
fmt("codepoint 不给 j 返回个数", select("#", utf8.codepoint("a中b")))
-- 分歧 4：char 的上界检查
fmt("char(0x110000) 报错?", not pcall(utf8.char, 0x110000))
if pcall(utf8.char, 0x110000) then fmt("char(0x110000) 字节", bytes(utf8.char(0x110000))) end
-- 分歧 5：charpattern 允许的首字节范围，5.3 是 194-244，5.4 放宽到 194-253
fmt("charpattern 首字节上界", utf8.charpattern:byte(7))
local seg = {}
for c in ("a\250\255b"):gmatch(utf8.charpattern) do seg[#seg + 1] = bytes(c) end
fmt("gmatch 切 'a[250][255]b'", #seg .. " 段 " .. table.concat(seg, " "))

print("--- 自写库 utf8lite（三个版本行为应当一致，取 5.4 语义）---")
fmt("U.len 代理区", rets(U.len, "\237\160\128"))
fmt("U.len F4 90 80 80", rets(U.len, "\244\144\128\128"))
fmt("U.len + lax=true", rets(U.len, "\244\144\128\128", 1, 4, true))
fmt("U.codepoint 不给 j 返回个数", select("#", U.codepoint("a中b")))
fmt("U.char(0x110000) 报错?", not pcall(U.char, 0x110000))
if pcall(U.char, 0x110000) then fmt("U.char(0x110000) 字节", bytes(U.char(0x110000))) end
fmt("U.charpattern 首字节上界", U.charpattern:byte(7))
local seg2 = {}
for c in ("a\250\255b"):gmatch(U.charpattern) do seg2[#seg2 + 1] = bytes(c) end
fmt("U.gmatch 切 'a[250][255]b'", #seg2 .. " 段 " .. table.concat(seg2, " "))
