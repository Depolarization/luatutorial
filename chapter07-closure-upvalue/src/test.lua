-- 自检：把本集关键结论写成断言，在当前解释器上逐条验证
local total, pass = 0, 0
local function check(ok, msg)
  total = total + 1
  if ok then pass = pass + 1 else print("CHECK_FAIL", msg) end
end

-- 数值 for 每轮是新变量
local t = {}
for i = 1, 3 do t[i] = function() return i end end
check(t[1]() == 1 and t[2]() == 2 and t[3]() == 3, "numeric-for should be 1,2,3")

-- while 共享外层变量
local u = {}
local i = 1
while i <= 3 do
  u[i] = function() return i end
  i = i + 1
end
check(u[1]() == 4 and u[2]() == 4 and u[3]() == 4, "while should share i=4")

-- local v = i 修复
local v3 = {}
for k = 1, 3 do
  local v = k
  v3[k] = function() return v end
end
check(v3[1]() == 1 and v3[2]() == 2 and v3[3]() == 3, "local-copy fix")

-- 立即执行函数修复
local w = {}
for k = 1, 3 do
  w[k] = (function(v) return function() return v end end)(k)
end
check(w[1]() == 1 and w[2]() == 2 and w[3]() == 3, "iife fix")

-- 两个闭包共享同一个 upvalue
local n = 0
local inc = function() n = n + 1; return n end
local get = function() return n end
check(inc() == 1 and get() == 1 and inc() == 2 and get() == 2, "shared upvalue")

-- debug.getupvalue 可用
local name, val = debug.getupvalue(inc, 1)
check(name == "n" and val == 2, "debug.getupvalue")

-- 计数器实例互相独立
local function counter()
  local x = 0
  return function()
    x = x + 1
    return x
  end
end
local a, b = counter(), counter()
check(a() == 1 and a() == 2 and b() == 1 and a() == 3, "independent counters")

-- 闭包持有的大表在释放后可以回收
collectgarbage("collect")
collectgarbage("collect")
local before = collectgarbage("count")
local function keeper()
  local big = {}
  for j = 1, 80000 do big[j] = j end
  return function() return big[#big] end
end
local keep = keeper()
collectgarbage("collect")
collectgarbage("collect")
local held = collectgarbage("count")
keep = nil
collectgarbage("collect")
collectgarbage("collect")
local after = collectgarbage("count")
check(held > before, "closure should retain memory")
check(held - after > 100, "big table should be reclaimed")

print("SELF-CHECK", pass, total)
