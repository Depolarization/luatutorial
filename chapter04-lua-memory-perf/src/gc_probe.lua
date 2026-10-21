-- gc_probe.lua：实测 GC 的接口、调参效果、停顿随活对象规模的增长、临时对象的代价。
local K = require("perfkit")
local gc = collectgarbage
local unpack = table.unpack or unpack
print("VERSION", _VERSION, "LUAJIT", type(jit) == "table")

local ms = function(s) return string.format("%.1f", s * 1000) end
local kb = function(b) return string.format("%.0f", b / 1024) .. "KB" end

-- 1. 接口实测：每个选项都真的调用一次，成败与返回值照抄
print("-- collectgarbage 选项实测 --")
local opts = {
  {"count", {}}, {"collect", {}}, {"stop", {}}, {"restart", {}},
  {"step", {1}}, {"isrunning", {}},
  {"setpause", {200}}, {"setstepmul", {200}}, {"setstepsize", {1024}},
  {"generational", {}}, {"incremental", {}},
  {"param", {"pause"}}, {"setgoal", {20}},
}
for _, o in ipairs(opts) do
  local res = {pcall(gc, o[1], unpack(o[2]))}
  local ok = res[1]
  if ok then
    print("OPTION", o[1], "支持", "返回", tostring(res[2]))
  else
    print("OPTION", o[1], "拒绝", tostring(res[2]):match("%(invalid option '.*%)") or "错误")
  end
end
gc("restart"); gc("collect")

-- 2. 造一堆短命表：pause 调大调小，时间和峰值内存各是多少
print("-- 调 pause：30 万张短命表 --")
local function workload(n)
  local s, peak = 0, 0
  for i = 1, n do
    local t = {i, i, i}
    s = s + t[1]
    if i % 2000 == 0 then
      local c = gc("count") * 1024
      if c > peak then peak = c end
    end
  end
  KEEP[1] = s
  return s, peak
end
local function measure(pause)
  if pause then pcall(gc, "setpause", pause) end
  gc("collect")
  local t0 = os.clock()
  local _, peak = workload(300000)
  local dt = os.clock() - t0
  gc("collect")
  return dt, peak
end
local d_def, p_def = measure(nil)
print("PAUSE", "默认", ms(d_def) .. "ms", "峰值", kb(p_def))
for _, p in ipairs({20, 100, 1000, 2000}) do
  local dt, pk = measure(p)
  print("PAUSE", p, ms(dt) .. "ms", "峰值", kb(pk),
        "时间/默认", string.format("%.2f", dt / d_def),
        "内存/默认", string.format("%.2f", pk / p_def))
end
pcall(gc, "setpause", 200)

-- 3. 增量 / 分代（只有支持的实现才有），同一工作量各跑三遍取最快
print("-- GC 模式对比 --")
for _, mode in ipairs({"incremental", "generational"}) do
  local ok, err = pcall(gc, mode)
  if ok then
    local best
    for _ = 1, 3 do
      gc("collect")
      local t0 = os.clock()
      workload(300000)
      local dt = os.clock() - t0
      if not best or dt < best then best = dt end
    end
    print("MODE", mode, ms(best) .. "ms")
  else
    print("MODE", mode, "不支持", tostring(err):match("%(invalid option '.*%)") or err)
  end
end
pcall(gc, "incremental")

-- 3b. 换一种负载：堆里常驻 20 万张表，同时反复造短命垃圾。
--     活集一大，两种模式的强弱会不会反过来？量了才知道，不猜。
print("-- 常驻集 + 短命垃圾：两种模式对比 --")
do
  local resident = {}
  for i = 1, 200000 do resident[i] = {i, i} end
  KEEP[1] = resident
  for _, mode in ipairs({"incremental", "generational"}) do
    local ok = pcall(gc, mode)
    if ok then
      local best
      for _ = 1, 2 do
        gc("collect")
        local t0 = os.clock()
        workload(300000)
        local dt = os.clock() - t0
        if not best or dt < best then best = dt end
      end
      print("MODE_RESIDENT", mode, ms(best) .. "ms", "堆", kb(gc("count") * 1024))
    else
      print("MODE_RESIDENT", mode, "不支持")
    end
  end
  pcall(gc, "incremental")
  KEEP[1] = nil
  gc("collect")
end

-- 4. 停顿：一次 full collect 要阻塞多久，它随「活对象」的多少增长
print("-- 一次 collect 的阻塞时间 --")
do
  for _, n in ipairs({50000, 200000, 800000}) do
    local keep = {}
    for i = 1, n do keep[i] = {i} end
    KEEP[1] = keep
    gc("collect")
    local best
    for _ = 1, 3 do
      local t0 = os.clock()
      gc("collect")
      local dt = os.clock() - t0
      if not best or dt < best then best = dt end
    end
    print("PAUSE_COLLECT", n, "张活表", ms(best) .. "ms", "堆", kb(gc("count") * 1024))
    KEEP[1] = nil
    gc("collect")
  end
  -- 同样多的垃圾、但活对象很少：停顿应该小得多
  local holder = {}
  for i = 1, 400000 do holder = {i} end
  KEEP[1] = holder
  gc("collect")
  local t0 = os.clock()
  gc("collect")
  print("PAUSE_LITTLE_LIVE", "40 万张已经变垃圾的表", ms(os.clock() - t0) .. "ms")
  KEEP[1] = nil
end

-- 5. 临时对象：每次都新建一张表 vs 复用一张表
print("-- 临时表的代价（100 万次）--")
do
  local function anew()
    local s = 0
    for i = 1, 1000000 do
      local t = {i, i}
      s = s + t[1]
    end
    KEEP[1] = s
  end
  local function reuse()
    local t = {}
    local s = 0
    for i = 1, 1000000 do
      t[1] = i; t[2] = i
      s = s + t[1]
    end
    KEEP[1] = s
  end
  -- 同一个循环体在 LuaJIT 上跑不满 1 ms，会被计时分辨率吃掉：
  -- 一轮跑 4 遍再除以 4，报出来的还是「每 100 万次」的价钱。
  local function x4(f) return function() for _ = 1, 4 do f() end end end
  local d1 = K.mintime(x4(anew), 2) / 4
  KEEP[1] = nil
  local d2 = K.mintime(x4(reuse), 2) / 4
  KEEP[1] = nil
  print("TEMP_TABLE", "新建", ms(d1) .. "ms", "复用", ms(d2) .. "ms",
        d2 > 0 and string.format("%.1f", d1 / d2) .. "倍" or "复用到量不出")

  gc("collect"); gc("stop")
  local b0 = K.bytes()
  for i = 1, 200000 do
    KEEP[1] = {i, i}
  end
  local vol = K.bytes() - b0
  gc("restart"); gc("collect"); KEEP[1] = nil
  print("ALLOC_VOLUME", "20万次新建表累计分配", kb(vol), "每张", string.format("%.1f", vol / 200000))
end

-- 6. LuaJIT：接口里到底有什么，临时表的分配为什么不要钱
do
  if type(jit) == "table" then
    local names = {}
    for k, v in pairs(jit) do names[#names + 1] = k .. "(" .. type(v) .. ")" end
    table.sort(names)
    print("LJIT_API", table.concat(names, " "))
    local ok, st = pcall(function() return jit.status() end)
    print("LJIT_STATUS", "jit.on", tostring(ok and st),
          "vm", tostring(ok and select(2, st) or "?"))
    -- 同样测 100 万次新建表：开着 JIT 与关掉 JIT 各多少毫秒
    local function anew()
      local s = 0
      for i = 1, 1000000 do
        local t = {i, i}
        s = s + t[1]
      end
      KEEP[1] = s
    end
    -- 开着 JIT 的这一轮短到 1 ms 都填不满，所以一轮跑 8 遍再除以 8：
    -- 报出来的还是「100 万次」的价钱，但计时分辨率高了 8 倍，倍数才算得出来。
    local function eight() for _ = 1, 8 do anew() end end
    local d_on = K.mintime(eight, 2) / 8
    pcall(jit.flush)
    pcall(jit.off)
    local d_off = K.mintime(eight, 2) / 8
    pcall(jit.on)
    pcall(jit.flush)
    KEEP[1] = nil
    print("LJIT_TEMP_TABLE", "jit 开", ms(d_on) .. "ms", "jit 关", ms(d_off) .. "ms",
          d_on > 0 and string.format("%.1f", d_off / d_on) .. "倍" or "开 JIT 后短于计时分辨率")
    print("LJIT_ALLOCATION", "jit.gcstep", type(jit.gcstep) == "function",
          "jit.stat", type(jit.stat) == "function")
  else
    print("LJIT", "非 LuaJIT，跳过")
  end
end
