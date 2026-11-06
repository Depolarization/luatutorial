-- t0_selftest.lua · 公共库自检：确认 sortkit 在五端行为一致，后面各章的输出才可信
local K = require("sortkit")

print("VERSION", _VERSION, "LUAJIT", type(jit) == "table")

local pass, fail = 0, 0
local function check(name, ok, detail)
  if ok then
    pass = pass + 1
    print("PASS " .. name)
  else
    fail = fail + 1
    print("FAIL " .. name .. " -> " .. tostring(detail))
  end
end

local function recs(keys)
  local t = {}
  for i = 1, #keys do t[i] = { k = keys[i], s = i } end
  return t
end
local byk = function(a, b) return a.k < b.k end

-- 1) 确定性随机：同种子同序列，五端必须逐位一致
local a = K.gen(12, 50, 2026)
local b = K.gen(12, 50, 2026)
local same = true
for i = 1, 12 do if a[i] ~= b[i] then same = false end end
check("gen_same_seed_same_seq", same, K.dump(a, 12))
print("GEN " .. K.dump(a, 12))

-- 2) 归并排序：随机数组排好且内容不丢（与原生 sort 结果逐位对上）
for _, n in ipairs({2, 7, 100, 2000}) do
  local src = K.gen(n, 1000, n)
  local x, y = K.copy(src), K.copy(src)
  K.msort(x)
  table.sort(y)
  local ok1, bad = K.sorted(x)
  local ok2, key = K.same_multiset(x, y)
  check("msort_sorted_n" .. n, ok1, bad)
  check("msort_content_n" .. n, ok2, key or K.dump(x, 8))
end

-- 3) 极端样本：空 / 单元素 / 已序 / 逆序 / 全等
local e0 = {}
K.msort(e0)
check("msort_empty", #e0 == 0, #e0)
local e1 = {5}
K.msort(e1)
check("msort_single", e1[1] == 5, e1[1])
local sorted_in, rev_in, all_eq = {1, 2, 3, 4, 5}, {5, 4, 3, 2, 1}, {7, 7, 7, 7}
K.msort(sorted_in); K.msort(rev_in); K.msort(all_eq)
check("msort_presorted", K.sorted(sorted_in), K.dump(sorted_in))
check("msort_reversed", K.sorted(rev_in), K.dump(rev_in))
check("msort_all_equal", K.sorted(all_eq), K.dump(all_eq))

-- 4) 稳定性：重复键样本，同键之内 s 必须保序
local rec = recs(K.gen(2000, 10, 77))
K.msort(rec, byk)
local st = K.stable_by(rec, function(r) return r.k end)
check("msort_stable_2000", st == true, st)
print("STABLE msort -> " .. K.dump(rec, 12, function(r) return r.s end))

-- 5) 参照实现互证：稳定插入排序与归并在同一份记录上顺序完全一致
local r1 = recs(K.gen(300, 25, 31))
local r2 = recs(K.gen(300, 25, 31))
K.msort(r1, byk)
K.isort(r2, byk)
local ident = true
for i = 1, 300 do if r1[i].s ~= r2[i].s then ident = false end end
check("msort_matches_isort", ident, K.dump(r1, 8, function(r) return r.s end))

-- 6) 契约自检：合法比较器放行，>= 当场暴露
local ok1, msg1 = K.check_cmp(K.lt, K.gen(50, 100, 3))
check("checkcmp_passes_valid", ok1 == true, msg1)
local bad = recs(K.gen(50, 9, 4))
local ok2, msg2 = K.check_cmp(function(p, q) return p.k >= q.k end, bad)
check("checkcmp_catches_ge", ok2 == false, msg2)
print("CMPMSG " .. tostring(msg2))

-- 7) msort_checked：非法比较器给可读报错（level=2 指回调用方），而不是带病排完
local ok3, err3 = pcall(K.msort_checked, recs(K.gen(40, 7, 5)),
  function(p, q) return p.k >= q.k end)
check("msort_checked_raises", ok3 == false, tostring(err3))
print("CHECKEDERR " .. tostring(err3))

-- 8) bench 自检：量出来的耗时必须是正数，重复次数会被放大
local t, r = K.bench(function() local s = 0 for i = 1, 100 do s = s + i end end)
check("bench_positive", t > 0 and r >= 1, tostring(t) .. " / " .. tostring(r))

-- 9) 预分配：n 个槽全部就位
local p = K.prealloc({}, 1000)
local filled = true
for i = 1, 1000 do if p[i] ~= false then filled = false end end
check("prealloc_slots", filled and #p == 1000, tostring(#p))

print("SUMMARY pass=" .. pass .. " fail=" .. fail)
