-- t3_nil.lua · 含 nil 的约束：# 给的是「一个边界」，sort 只认 [1..#t]。
-- 洞的位置不同、构造方式不同，同一个数组在五端的 # 都可能不一样——全部实测。
local K = require("sortkit")

KEEP = KEEP or {}

local function try(t, tag, n)
  print(tag .. " # -> " .. #t)
  local ok, err = pcall(table.sort, t)
  if ok then
    print(tag .. " sort -> 成功 " .. K.dump(t, n or #t))
  else
    print(tag .. " sort -> 报错被接住 err=" .. tostring(err))
  end
end

print("== A. 字面量里的洞 ==")
try({ 3, nil, 1 }, "A {3,nil,1}", 4)

print("== B. 排好再挖中间：{1..5} 挖掉第 3 个 ==")
local u = { 1, 2, 3, 4, 5 }
u[3] = nil
try(u, "B {1,2,_,4,5}", 6)

print("== C. 挖中间再补尾：{1..5} 挖 3、挂 t[6]=9 ==")
local v = { 1, 2, 3, 4, 5 }
v[3] = nil
v[6] = 9
try(v, "C {1,2,_,4,5,9}", 7)

print("== D. 比较器见到了 nil 吗 ==")
local w = { 5, 4, 3, 2, 1 }
w[4] = nil
local nils, calls = 0, 0
local ok3, err3 = pcall(table.sort, w, function(a, b)
  calls = calls + 1
  if a == nil or b == nil then nils = nils + 1 end
  return (a or 0) < (b or 0)
end)
print("D 比较次数 -> " .. calls .. " 次，其中见到 nil " .. nils .. " 次")
if ok3 then
  print("D 容错比较器 -> 成功 " .. K.dump(w, 6))
else
  print("D 容错比较器 -> 报错被接住 err=" .. tostring(err3))
end

print("== E. 默认比较器撞上 nil 的文案 ==")
local x = { 1, nil, 3 }
local ok4, err4 = pcall(table.sort, x)
print("E {1,nil,3} -> " .. (ok4 and ("成功 " .. K.dump(x, 4)) or tostring(err4)))
local y = { 3, 2, 1 }
y[2] = nil
local ok5, err5 = pcall(table.sort, y)
print("E {3,_,1} -> " .. (ok5 and ("成功 " .. K.dump(y, 4)) or tostring(err5)))
