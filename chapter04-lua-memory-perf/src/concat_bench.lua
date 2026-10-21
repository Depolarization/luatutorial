-- concat_bench.lua：字符串拼接的实测代价（时间 + 临时垃圾总量）。
-- 临时垃圾用「先停掉 GC 再测内存增量」量出来：这样所有中间串都还没被回收，
-- 差值就是这段循环一共分配了多少字节。
local K = require("perfkit")
local gc = collectgarbage
print("VERSION", _VERSION)

local ms = function(s) return string.format("%.2f", s * 1000) end
local ns = K.ns

-- 1. s = s .. piece 的二次方增长：规模翻倍，耗时应当翻四倍
print("-- 逐段 .. 拼接：规模翻倍后耗时怎么变 --")
local quad = {}
for _, n in ipairs({4000, 8000, 16000, 32000}) do
  local piece = "abc"
  local d = K.bench(function()
    local s = ""
    for i = 1, n do s = s .. piece end
    KEEP[1] = s
  end, 0.15)
  quad[n] = d
  local prev = quad[n / 2]
  print("DOTDOT", n, ms(d) .. "ms", "翻倍比",
        prev and string.format("%.1f", d / prev) .. "x" or "-",
        "每段", ns(d / n) .. "ns", "最终长度", #KEEP[1])
  KEEP[1] = nil
  gc("collect")
end

-- 2. 同一规模下几种写法的耗时与临时垃圾
print("-- n = 8000，五种写法对比 --")
local n = 8000
local piece = "abc"

local function alloc_volume(f)
  K.clean()
  gc("stop")                        -- 停掉回收，让所有中间对象都留在内存里
  local before = K.bytes()
  f()
  local d = K.bytes() - before
  gc("restart")
  gc("collect")
  return d
end

local methods = {
  {"s = s .. piece", function()
     local s = ""
     for i = 1, n do s = s .. piece end
     KEEP[1] = s
   end},
  {"table.insert(t, s) + table.concat", function()
     local t = {}
     for i = 1, n do table.insert(t, piece) end
     KEEP[1] = table.concat(t)
   end},
  {"t[#t+1] = s + table.concat", function()
     local t = {}
     for i = 1, n do t[#t + 1] = piece end
     KEEP[1] = table.concat(t)
   end},
  {"t[i] = s + table.concat", function()
     local t = {}
     for i = 1, n do t[i] = piece end
     KEEP[1] = table.concat(t)
   end},
  {"string.rep(piece, n)", function()
     KEEP[1] = string.rep(piece, n)
   end},
}
for _, m in ipairs(methods) do
  local d = K.bench(m[2], 0.15)                 -- 一次 = 拼完 8000 段
  local res = KEEP[1]
  KEEP[1] = nil
  local a = alloc_volume(m[2])
  KEEP[1] = nil
  gc("collect")
  print("METHOD", m[1], ms(d) .. "ms", "每段", ns(d / n) .. "ns",
        "临时垃圾", string.format("%.0f", a / 1024) .. "KB",
        "结果长度", #res, "结果一致", res == string.rep(piece, n))
end

-- 3. 一条表达式里连拼多个：a..b..c..d..e 是一趟算完，一句一句拼要建五次中间串。
--    每段都从表里现取、最后一段跟着计数变——否则 LuaJIT 会把整条表达式当常量折掉。
print("-- 一条表达式连拼 vs 一句一句拼（每次纳秒）--")
do
  local p = {"aaa", "bbb", "ccc", "ddd", "eee"}
  local j = 0
  local t1 = K.bench(function()
    j = j + 1
    KEEP[1] = p[1] .. p[2] .. p[3] .. p[4] .. p[5] .. p[(j % 5) + 1]
  end, 0.15)
  local out1 = KEEP[1]
  local t2 = K.bench(function()
    j = j + 1
    local s = p[1]
    s = s .. p[2]
    s = s .. p[3]
    s = s .. p[4]
    s = s .. p[5]
    s = s .. p[(j % 5) + 1]
    KEEP[1] = s
  end, 0.15)
  print("CHAIN_VS_STEP", ns(t1) .. "ns", ns(t2) .. "ns", string.format("%.1f", t2 / t1) .. "x",
        "两种写法拼出来一样长", #out1 == #KEEP[1], "长度", #out1)
  KEEP[1] = nil
end

-- 4. 拼接时的数字转字符串：tostring(i) 每次都要造一条新串
print("-- 数字混进 .. 里：逐段拼 vs 存表再 concat --")
do
  local t1 = K.bench(function()
    local s = ""
    for i = 1, 20000 do s = s .. tostring(i) end
    KEEP[1] = s
  end, 0.15)
  KEEP[1] = nil
  local t2 = K.bench(function()
    local t = {}
    for i = 1, 20000 do t[i] = tostring(i) end
    KEEP[1] = table.concat(t)
  end, 0.15)
  KEEP[1] = nil
  print("NUM2STR", ms(t1) .. "ms", ms(t2) .. "ms", string.format("%.1f", t1 / t2) .. "x",
        "每段", ns(t1 / 20000) .. "ns", "vs", ns(t2 / 20000) .. "ns")
end
