-- t3_traceback.lua · xpcall + debug.traceback：栈只在 handler 里活着
local errkit = require("errkit")

local function oneline(s)
  return (tostring(s):gsub("\n", " <BR> "))
end
local function nlcount(s)
  return select(2, tostring(s):gsub("\n", "")) + 1  -- 行数 = 换行数 + 1，结尾不带换行
end

print("== A. xpcall 不给 handler ==")
local ok_a, e_a = pcall(function() xpcall(function() error("NH", 0) end) end)
print("A -> " .. tostring(e_a))

print("== B. 同一个错误，栈还活着 vs 已经展开 ==")
local tb_in, tb_after
local ok_b = xpcall(function()
  local depth = 1
  local function inner()
    error("BOOM", 0)
  end
  inner()
end, function(e)
  tb_in = debug.traceback(e)
  return e
end)
pcall(function()
  local depth = 1
  local function inner()
    error("BOOM", 0)
  end
  inner()
end)
tb_after = debug.traceback("事后")
print("B handler 内 traceback 行数=" .. nlcount(tb_in))
print("B pcall 之后 traceback 行数=" .. nlcount(tb_after))
print("B handler 内 -> " .. oneline(tb_in))
print("B 事后       -> " .. oneline(tb_after))

print("== C. debug.traceback 的三种调用 ==")
local function deep()
  return debug.traceback("消息", 1), debug.traceback("消息", 2), debug.traceback("消息", 3)
end
local c1, c2, c3 = deep()
print("C level=1 行数=" .. nlcount(c1))
print("C level=2 行数=" .. nlcount(c2))
print("C level=3 行数=" .. nlcount(c3))
print("C level=1 -> " .. oneline(c1))
print("C level=2 -> " .. oneline(c2))
print("C level=3 -> " .. oneline(c3))

print("== D. 把 traceback 直接当 handler ==")
local ok_d, msg_d = xpcall(function()
  local hp = 3
  local function use_nil(t) return t.field end
  use_nil(nil)
end, debug.traceback)
print("D ok=" .. tostring(ok_d) .. " 行数=" .. nlcount(msg_d))
print("D -> " .. oneline(msg_d))
local ok_e, msg_e = xpcall(function() error("E", 0) end, debug.traceback, "额外")
print("D 带额外参数调用 xpcall(f, tb, \"额外\") -> ok=" .. tostring(ok_e) .. " " .. oneline(msg_e))

print("== E. 挂起的协程也能 traceback ==")
local co = coroutine.create(function()
  local tag = "in-coroutine"
  local function susp()
    return coroutine.yield("pause")
  end
  return susp()
end)
local r_e = { coroutine.resume(co) }
local ok_tb, tb_co = pcall(debug.traceback, co)
print("E resume=" .. tostring(r_e[1]) .. " 值=" .. tostring(r_e[2]) .. " status=" .. tostring(coroutine.status(co)))
print("E traceback(co) 可用=" .. tostring(ok_tb) .. " -> " .. oneline(tb_co))

print("== F. errkit 助手 vs 原生 traceback ==")
local ok_f, diag_f = errkit.call(function(count)
  local label = "hp"
  local cfg = { max = 100 }
  error("需要现场变量", 0)
end, 7)
print("F ok=" .. tostring(ok_f))
print("F -> " .. tostring(diag_f))
