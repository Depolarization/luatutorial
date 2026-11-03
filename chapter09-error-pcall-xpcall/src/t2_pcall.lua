-- t2_pcall.lua · pcall 的双刃剑：返回值结构、被吞掉的错误、非字符串错误对象
local errkit = require("errkit")

print("== A. pcall 的返回值个数 ==")
local ok_a, r1, r2, r3 = pcall(function() return 1, 2, 3 end)
print("A 成功 select#=" .. select("#", pcall(function() return 1, 2, 3 end))
  .. " 值=" .. tostring(r1) .. "," .. tostring(r2) .. "," .. tostring(r3))
local ok_b, e_b = pcall(function() error("bad", 0) end)
print("A 失败 select#=" .. select("#", pcall(function() error("bad", 0) end))
  .. " ok=" .. tostring(ok_b) .. " 第二个返回值=" .. tostring(e_b))
print("A 返回 0 个值时 select#=" .. select("#", pcall(function() return end)))
local no_ret = pcall(function() error(nil, 0) end)
print("A 错误对象是 nil 时 select#=" .. select("#", pcall(function() error(nil, 0) end))
  .. " 值=" .. tostring(select(2, pcall(function() error(nil, 0) end))))

print("== B. 被 pcall 吞掉的错误：调用方分不清「没有」和「坏了」 ==")
local function load_item_db(name)
  local raw = nil
  if name == "sword" then raw = { atk = 10 } end
  return raw
end
local function read_atk_swallow(name)
  local ok, val = pcall(function() return load_item_db(name).atk end)
  if not ok then return nil end
  return val
end
local function read_atk_loud(name)
  return load_item_db(name).atk
end
print("B 吞错版 正常      -> atk=" .. tostring(read_atk_swallow("sword")))
print("B 吞错版 查无此项  -> atk=" .. tostring(read_atk_swallow("shield")) .. "  (其实崩了)")
print("B 吞错版 两者相同吗 -> " .. tostring(read_atk_swallow("shield") == read_atk_swallow("不存在")))
local ok_broken, e_broken = pcall(read_atk_loud, "shield")
print("B 不吞时同一调用抛 -> " .. tostring(e_broken))

print("== C. 非字符串错误对象一路保留 ==")
local ErrObj = setmetatable({ code = 404, msg = "no such item" }, {
  __name = "mod_error",
  __tostring = function(self) return "mod_error(" .. tostring(self.code) .. ")" end
})
local ok_c, e_c = pcall(function() error(ErrObj, 0) end)
print("C type=" .. type(e_c) .. " 同一个表=" .. tostring(e_c == ErrObj)
  .. " code=" .. tostring(rawget(e_c, "code")))
print("C tostring=" .. tostring(e_c))
print("C 裸表加 __name 的 tostring=" .. errkit.redact(tostring(setmetatable({}, { __name = "mytype" }))))
local ok_d, e_d = pcall(function() error("prefix") end)
print("C 字符串错误 pcall 后=" .. tostring(e_d))

print("== D. xpcall 的额外参数到底给了谁 ==")
local seen_f, seen_h = nil, nil
local function target(a, b)
  seen_f = "a=" .. tostring(a) .. " b=" .. tostring(b) .. " select#=" .. select("#", a, b)
  return "ok"
end
local function msgh(e)
  seen_h = "select#=" .. select("#", e) .. " e=" .. tostring(e)
  return "handled"
end
local ok_e = xpcall(target, msgh, "A1", "B2")
print("D 成功路径 f 收到 [" .. tostring(seen_f) .. "] handler 未执行=" .. tostring(seen_h))
seen_f = nil
local ok_f, msg_f = xpcall(function(a, b)
  seen_f = "a=" .. tostring(a) .. " b=" .. tostring(b)
  error("IN_F", 0)
end, function(e)
  seen_h = "handler 只拿到 [" .. tostring(e) .. "]"
  return "final"
end, "X", "Y")
print("D 失败路径 f 收到 [" .. tostring(seen_f) .. "]")
print("D " .. tostring(seen_h) .. " ok=" .. tostring(ok_f) .. " 返回=" .. tostring(msg_f))

print("== E. handler 自己再抛 ==")
local ok_g, msg_g = xpcall(function() error("原始错误", 0) end, function(e) error("handler 里的错", 0) end)
print("E ok=" .. tostring(ok_g) .. " -> " .. tostring(msg_g))

print("== F. yield 能不能穿过 pcall ==")
local co = coroutine.create(function()
  local res = { pcall(function() return coroutine.yield("从 pcall 里 yield 出来") end) }
  return "pcall.ok=" .. tostring(res[1]) .. " 值=" .. tostring(res[2])
end)
local r_ok, v1, v2 = coroutine.resume(co)
print("F resume=" .. tostring(r_ok) .. " " .. tostring(v1) .. " " .. tostring(v2))
