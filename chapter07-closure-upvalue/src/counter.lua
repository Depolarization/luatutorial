-- 探针 3：计数器工厂，以及状态放错位置的后果
-- >>> SNIP counter_a
local function new_counter()
  local n = 0
  return function()
    n = n + 1
    return n
  end
end
local c1 = new_counter()
print("COUNTER_A", c1(), c1(), c1())
-- <<< SNIP counter_a

-- >>> SNIP counter_b
local function new_counter_box()
  local box = {n = 0}
  return function()
    box.n = box.n + 1
    return box.n
  end
end
local c2 = new_counter_box()
print("COUNTER_B", c2(), c2(), c2())
-- <<< SNIP counter_b

-- >>> SNIP counter_c
local Counter = {}
Counter.__index = Counter
function Counter.new()
  return setmetatable({n = 0}, Counter)
end
function Counter:inc()
  self.n = self.n + 1
  return self.n
end
local c3 = Counter.new()
print("COUNTER_C", c3:inc(), c3:inc(), c3:inc())
-- <<< SNIP counter_c

-- 两个计数器互不影响：每个闭包有自己的 upvalue 单元
-- >>> SNIP counter_indep
local a = new_counter()
local b = new_counter()
print("INDEP", a(), a(), b(), a(), b())
-- <<< SNIP counter_indep

-- 反例：状态放在工厂外，所有计数器共享同一个 n
-- >>> SNIP counter_bad
local shared_n = 0
local function bad_counter()
  return function()
    shared_n = shared_n + 1
    return shared_n
  end
end
local bad_a = bad_counter()
local bad_b = bad_counter()
print("BAD_SHARED", bad_a(), bad_b(), bad_a(), bad_b())
-- <<< SNIP counter_bad

-- 取证：c1 / c2 各自捕获的 upvalue 名字
-- >>> SNIP counter_up
local name_a = debug.getupvalue(c1, 1)
local name_b = debug.getupvalue(c2, 1)
print("COUNTER_UP_A", name_a)
print("COUNTER_UP_B", name_b)
-- <<< SNIP counter_up
