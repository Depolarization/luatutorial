-- perfkit.lua：探针工具箱。只用 Lua 5.1 就有的语法（不碰位运算、不碰整数字面量、不碰 //）。
-- 所有数字都必须由真实解释器跑出来，所以这里只提供「测量」手段，不提供任何结论。
local M = {}
local gc = collectgarbage
local clock = os.clock

-- 探针之间用全局 KEEP 抓住被测对象，防止它被回收后内存归零
function M.bytes()
  return gc("count") * 1024          -- Lua 自己报告的已用字节（含分配器开销）
end

function M.clean()
  gc("collect"); gc("collect")        -- 收两遍：第一遍可能只清了一半
end

-- 量一次「构造 f(n)」前后的字节差。
-- 只在测量前清场：循环里的中间数组已经被 realloc 同步还给了分配器，
-- 所以 f() 一返回就可以直接读数；再清一遍会把刚测的对象当成垃圾。
-- 第二个返回值是对象本身，调用方必须马上挂到 KEEP 上，否则它只是当前 local，可能被回收。
function M.cost(n, f)
  M.clean()
  KEEP[1] = nil
  local before = M.bytes()
  local obj = f(n)
  local after = M.bytes()
  KEEP[1] = obj
  return after - before, obj
end

-- 同一个测量跑三遍取最小，压掉分配器抖动
function M.best(n, f)
  local m
  for _ = 1, 3 do
    local d = M.cost(n, f)
    if not m or d < m then m = d end
  end
  KEEP[1] = nil
  return m
end

function M.time(f)
  local t0 = clock()
  f()
  return clock() - t0
end

function M.mintime(f, r)
  local m
  for _ = 1, r do
    local d = M.time(f)
    if not m or d < m then m = d end
  end
  return m
end

-- Windows 上 os.clock() 只有 1ms 分辨率，跑一次根本量不准。
-- 先自动把重复次数放大到总耗时超过 target 秒，再用这个次数跑三轮取最小值。
-- 返回值：单次耗时、实际用的重复次数。
function M.bench(f, target)
  target = target or 0.12
  local reps = 1
  for _ = 1, 8 do
    local t0 = clock()
    for _ = 1, reps do f() end
    local total = clock() - t0
    if total >= target then break end
    local per = total / reps
    if per <= 0 then reps = reps * 16
    else
      local want = math.ceil(target / per)
      if want <= reps then want = reps * 4 end
      if want > 65536 then want = 65536 end
      reps = want
    end
    if reps > 65536 then reps = 65536; break end
  end
  local best
  for _ = 1, 3 do
    local t0 = clock()
    for _ = 1, reps do f() end
    local d = (clock() - t0) / reps
    if not best or d < best then best = d end
  end
  return best, reps
end

-- 纳秒：把秒换算成「每次操作多少纳秒」，屏幕上比 0.0ms 好读
function M.ns(s)
  return string.format("%.0f", s * 1e9)
end

-- pairs 的遍历顺序会先走数组部分（升序连续），再走哈希部分。
-- 于是「从头开始连续整数键的最长前缀」就是数组部分的可见边界。
function M.first_run(t)
  local want, run, total, broken = 1, 0, 0, false
  for k in pairs(t) do
    total = total + 1
    if not broken and k == want then
      run, want = k, k + 1
    else
      broken = true
    end
  end
  return run, total
end

function M.maxnumkey(t)
  local mx = 0
  for k in pairs(t) do
    if type(k) == "number" and k > mx then mx = k end
  end
  return mx
end

-- 只关心相对量级，输出整数比值
function M.ratio(a, b)
  if b == 0 then return 0 end
  local r = a / b
  return math.floor(r + 0.5)
end

return M
