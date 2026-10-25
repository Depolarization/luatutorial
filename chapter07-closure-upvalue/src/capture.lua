-- 探针 1：捕获的是变量，不是值
-- 每一行输出都来自当前解释器，不手写结论。
print("ENGINE", _VERSION, (type(jit) == "table") and jit.version or "no-jit")

local function hexhead(s)
  return (s:gsub(".", function(c) return string.format("%02x", string.byte(c)) end))
end
print("DUMP_HEAD", hexhead(string.dump(function() return 1 end):sub(1, 12)))

-- 1. 最小复现：while 循环里，三个闭包共享同一个 i
-- >>> SNIP repro
local cbs = {}
local i = 1
while i <= 3 do
  cbs[i] = function() return i end
  i = i + 1
end
print("WHILE_RET", cbs[1](), cbs[2](), cbs[3]())
-- <<< SNIP repro

-- 2. 数值 for：每轮都是新的局部变量（和 JS 的 var 坑不同）
-- >>> SNIP forsafe
local fcbs = {}
for k = 1, 3 do
  fcbs[k] = function() return k end
end
print("FOR_RET", fcbs[1](), fcbs[2](), fcbs[3]())
-- <<< SNIP forsafe

-- 3. 把值写回循环外的变量：for 一样会共享
-- >>> SNIP forshared
local shared
local scbs = {}
for k = 1, 3 do
  shared = k
  scbs[k] = function() return shared end
end
print("SHARED_RET", scbs[1](), scbs[2](),
      scbs[3]())
-- <<< SNIP forshared

-- 4. 两个闭包共享同一个 upvalue 单元格
-- >>> SNIP share
local n = 0
local inc = function() n = n + 1; return n end
local get = function() return n end
print("SHARE_RET", inc(), get(), inc(), get())
-- <<< SNIP share

-- 5. debug.getupvalue 取证：名字与当前值
-- >>> SNIP upvals
for k = 1, 3 do
  local name, val = debug.getupvalue(cbs[k], 1)
  print("UP_WHILE", k, name, val)
end
for k = 1, 3 do
  local name, val = debug.getupvalue(fcbs[k], 1)
  print("UP_FOR", k, name, val)
end
for k = 1, 3 do
  local name, val = debug.getupvalue(scbs[k], 1)
  print("UP_SHARED", k, name, val)
end
-- <<< SNIP upvals
