-- t4_merge.lua · 纯 Lua 稳定归并：正确性、稳定性、契约自检、预分配的代价（第 4 章联动）
local K = require("sortkit")

KEEP = KEEP or {}

local function recs(keys)
  local t = {}
  for i = 1, #keys do t[i] = { k = keys[i], s = i } end
  return t
end
local byk = function(a, b) return a.k < b.k end
local getk = function(r) return r.k end

print("== A. 正确性：极端样本 + 随机样本 ==")
local cases = {
  { "空表", {} },
  { "单元素", { 42 } },
  { "两元素", { 2, 1 } },
  { "已序", { 1, 2, 3, 4, 5, 6, 7, 8 } },
  { "逆序", { 8, 7, 6, 5, 4, 3, 2, 1 } },
  { "全等", { 9, 9, 9, 9, 9 } },
  { "含重复", { 3, 1, 2, 3, 1, 2, 3 } },
}
for _, c in ipairs(cases) do
  local t = K.copy(c[2])
  K.msort(t)
  local ok, bad = K.sorted(t)
  print("A " .. c[1] .. " -> " .. (ok and ("ok " .. K.dump(t, 8)) or ("坏在 " .. bad)))
end
for _, n in ipairs({ 100, 2000 }) do
  local src = K.gen(n, 1000, n * 3 + 1)
  local a, b = K.copy(src), K.copy(src)
  K.msort(a)
  table.sort(b)
  local ok = K.sorted(a) and K.same_multiset(a, b)
  print("A 随机 n=" .. n .. " -> " .. (ok and "ok（与原生逐位一致）" or "NG"))
end

print("== B. 稳定性：同一份重复键记录，原生 vs 归并 ==")
local keys = K.gen(2000, 10, 77)
local r_native, r_merge = recs(keys), recs(keys)
table.sort(r_native, byk)
K.msort(r_merge, byk)
print("B 原生 稳定性 -> " .. (K.stable_by(r_native, getk) and "保序" or "不保序"))
print("B 原生 前12序号 -> " .. K.dump(r_native, 12, function(r) return r.s end))
print("B 归并 稳定性 -> " .. (K.stable_by(r_merge, getk) and "保序" or "不保序"))
print("B 归并 前12序号 -> " .. K.dump(r_merge, 12, function(r) return r.s end))

print("== C. comparator 契约自检 ==")
local arr = K.gen(60, 20, 11)
local ok1, msg1 = K.check_cmp(K.lt, arr)
print("C 合法比较器 -> " .. (ok1 and "通过" or msg1))
local ok2, msg2 = K.check_cmp(function(a, b) return a >= b end, arr)
print("C >= 比较器 -> " .. (ok2 and "通过" or msg2))
local ok3, err3 = pcall(K.msort_checked, K.copy(arr), function(a, b) return a >= b end)
print("C msort_checked -> " .. (ok3 and "居然放行" or tostring(err3)))

print("== D. aux 预分配的代价（第 4 章表内存） ==")
local gc = collectgarbage
local function bytes() return gc("count") * 1024 end
gc("collect"); gc("collect")
local b0 = bytes()
local up = K.prealloc({}, 100000)
KEEP.up = up
print("D aux 升序填 100000 槽 -> " .. string.format("%.0f", bytes() - b0) .. " 字节")
gc("collect"); gc("collect")
local b2 = bytes()
local down = {}
for i = 100000, 1, -1 do down[i] = false end
KEEP.down = down
print("D aux 倒序填 100000 槽 -> " .. string.format("%.0f", bytes() - b2) .. " 字节")
gc("collect"); gc("collect")
local b3 = bytes()
local floatk = {}
for i = 1, 100000 do floatk[i + 0.5] = false end
KEEP.floatk = floatk
print("D 对照 浮点键 100000 个 -> " .. string.format("%.0f", bytes() - b3) .. " 字节")
