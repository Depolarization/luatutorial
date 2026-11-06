-- t1_cmp.lua · 比较器行为实测：正常的、非法的、内部报错的、返回 nil 的。
-- 全部包 pcall：本机五个解释器上这些案例都被实测为「普通 Lua 错误」，接得住才放进这里。
local K = require("sortkit")

KEEP = KEEP or {}

local function try_sort(t, cmp, tag)
  local ok, err = pcall(table.sort, t, cmp)
  if ok then
    print(tag .. " 返回成功 result=" .. K.dump(t))
  else
    print(tag .. " 报错被接住 err=" .. tostring(err))
  end
  return ok
end

print("== A. 正常比较器 ==")
local nums = K.gen(16, 100, 9)
print("A 输入 -> " .. K.dump(nums))
table.sort(nums)
print("A 默认升序 -> " .. K.dump(nums))
local desc = K.copy(nums)
table.sort(desc, function(a, b) return a > b end)
print("A 显式降序 -> " .. K.dump(desc))
local rec = {}
for i = 1, 10 do rec[i] = { k = (i * 7) % 10, s = i } end
table.sort(rec, function(a, b) return a.k < b.k end)
print("A 记录按键 -> " .. K.dump(rec, 10, function(r) return r.s end))

print("== B. 非法比较器家族 ==")
-- B1: >= 在 3 个元素上：护栏根本不触发，静默错序
local t1 = { 2, 2, 1 }
try_sort(t1, function(a, b) return a >= b end, "B GE3 {2,2,1} ->")
-- B2: >= 在 64 个重复键上
local t2 = {}
for i = 1, 64 do t2[i] = (i % 4) + 1 end
try_sort(t2, function(a, b) return a >= b end, "B GE64 重复键 ->")
-- B3: 永远 true
local t3 = {}
for i = 1, 64 do t3[i] = i end
try_sort(K.copy(t3), function() return true end, "B TRUE64 ->")
-- B4: 返回 nil（"永远不小于"）
try_sort(K.copy(t3), function() return nil end, "B NILCMP64 ->")
-- B5: 掷硬币
try_sort(K.copy(t3), function() return math.random() < 0.5 end, "B COIN64 ->")
-- B6: 比较器内部报错（普通 Lua 错误，从 C 层一路传出来）
local t6 = {}
for i = 1, 64 do t6[i] = (i % 8) + 1 end
local calls = 0
try_sort(t6, function(a, b)
  calls = calls + 1
  if a == 5 or b == 5 then error("boom inside cmp #" .. calls, 0) end
  return a < b
end, "B CMPERR ->")
print("B CMPERR 比较次数 -> " .. calls)

print("== C. 护栏覆盖率：>= 比较器扫 200 组随机重复键（n=40） ==")
local invalid, other, silent, wrong = 0, 0, 0, 0
local example, other_err
for k = 1, 200 do
  local inp = K.gen(40, 8, 1000 + k)
  local t = K.copy(inp)
  local ok, err = pcall(table.sort, t, function(a, b) return a >= b end)
  if not ok then
    if tostring(err):find("invalid order", 1, true) then
      invalid = invalid + 1
    else
      other = other + 1
      if not other_err then other_err = tostring(err) end
    end
  else
    silent = silent + 1
    for i = 2, #t do
      if t[i - 1] < t[i] then wrong = wrong + 1 break end
    end
    if not example then
      example = "输入 " .. K.dump(inp) .. " | 输出 " .. K.dump(t)
    end
  end
end
print("C 统计 -> invalid=" .. invalid .. " 其他报错=" .. other ..
  " 静默成功=" .. silent .. " 其中结果无序=" .. wrong)
if other_err then
  print("C 其他报错一例 -> " .. other_err)
end
if example then
  print("C 静默一例 -> " .. example)
end
