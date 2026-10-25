-- 探针 2：五种修复写法，逐个跑真实输出
-- 每个例子都从同一个坑出发：值先写进一个会被后续迭代改掉的变量。

-- 修复 1：local v = i（每轮新建局部变量）
-- >>> SNIP fix_local
local f1 = {}
local i = 1
while i <= 3 do
  local v = i
  f1[i] = function() return v end
  i = i + 1
end
print("FIX1", f1[1](), f1[2](), f1[3]())
-- <<< SNIP fix_local

-- 修复 2：立即执行函数（把值作为参数传进去）
-- >>> SNIP fix_iife
local f2 = {}
local i = 1
while i <= 3 do
  f2[i] = (function(v) return function() return v end end)(i)
  i = i + 1
end
print("FIX2", f2[1](), f2[2](), f2[3]())
-- <<< SNIP fix_iife

-- 修复 3：表字段（每轮新建一个盒子对象）
-- >>> SNIP fix_box
local f3 = {}
local i = 1
while i <= 3 do
  local box = {v = i}
  f3[i] = function() return box.v end
  i = i + 1
end
print("FIX3", f3[1](), f3[2](), f3[3]())
-- <<< SNIP fix_box

-- 修复 4：工厂函数（参数是一份独立的值）
-- >>> SNIP fix_factory
local function getter(v)
  return function() return v end
end
local f4 = {}
local i = 1
while i <= 3 do
  f4[i] = getter(i)
  i = i + 1
end
print("FIX4", f4[1](), f4[2](), f4[3]())
-- <<< SNIP fix_factory

-- 修复 5：先做快照表，再用泛型 for 遍历
-- >>> SNIP fix_snapshot
local f5 = {}
local snapshot = {1, 2, 3}
for k, v in ipairs(snapshot) do
  f5[k] = function() return v end
end
print("FIX5", f5[1](), f5[2](), f5[3]())
-- <<< SNIP fix_snapshot

-- 证据：修复 1 的三个闭包，upvalue 各自独立
-- >>> SNIP fix_up
for k = 1, 3 do
  local name, val = debug.getupvalue(f1[k], 1)
  print("FIX1_UP", k, name, val)
end
-- <<< SNIP fix_up
