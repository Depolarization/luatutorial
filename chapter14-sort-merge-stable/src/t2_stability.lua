-- t2_stability.lua · 稳定性雷区：table.sort 是快排变体，不保证重复键的相对顺序。
-- 每条记录带 (键 k, 原序号 s)：排完之后同键之内 s 必须仍升序，否则就是换序实锤。
local K = require("sortkit")

KEEP = KEEP or {}

local function recs(keys)
  local t = {}
  for i = 1, #keys do t[i] = { k = keys[i], s = i } end
  return t
end
local byk = function(a, b) return a.k < b.k end

local function stable_after(t)
  for i = 2, #t do
    if t[i - 1].k == t[i].k and t[i - 1].s > t[i].s then return false, i end
  end
  return true
end

local function ids(t, n)
  local m = n or #t
  if m > 16 then m = 16 end
  local s = {}
  for i = 1, m do s[i] = string.format("%.0f", t[i].s) end
  return table.concat(s, ",")
end

local PATS = {
  { "交替 1,2", function(i) return (i % 2) + 1 end },
  { "循环 1,2,3", function(i) return (i % 3) + 1 end },
  { "全等 1", function() return 1 end },
  { "块 1..4", function(i) return ((i - 1) % 4) + 1 end },
  { "嵌套 1,1,2,2", function(i) return math.ceil(i / 2) end },
}

print("== A. 最小复现：从 n=2 往上搜第一个换序规模 ==")
local first_hit                        -- 全部模式里最小的那个翻车样本
for _, p in ipairs(PATS) do
  local found
  for n = 2, 64 do
    local keys = {}
    for i = 1, n do keys[i] = p[2](i) end
    local t = recs(keys)
    table.sort(t, byk)
    if not stable_after(t) then found = { n = n, keys = keys } break end
  end
  if found then
    local t = recs(found.keys)
    table.sort(t, byk)
    print("A " .. p[1] .. " -> 首个翻车 n=" .. found.n .. " 排后序号=" .. ids(t))
    if not first_hit or found.n < first_hit.n then
      first_hit = { n = found.n, keys = found.keys, pat = p[1] }
    end
  else
    print("A " .. p[1] .. " -> n<=64 全部保序")
  end
end

print("== B. 同一个翻车样本：原生 vs 纯 Lua 归并 ==")
if first_hit then
  local tn = recs(first_hit.keys)
  table.sort(tn, byk)
  local tm = recs(first_hit.keys)
  K.msort(tm, byk)
  print("B 样本 -> " .. first_hit.pat .. " n=" .. first_hit.n)
  print("B 原生 排后序号 -> " .. ids(tn))
  print("B 原生 稳定性 -> " .. (stable_after(tn) and "保序" or "不保序"))
  print("B 归并 排后序号 -> " .. ids(tm))
  print("B 归并 稳定性 -> " .. (stable_after(tm) and "保序" or "不保序"))
end

print("== C. 规模扫描：重复键样本上原生翻不翻车 ==")
for _, n in ipairs({ 50, 200, 1000, 5000 }) do
  local line = { "C n=" .. n }
  for _, p in ipairs(PATS) do
    local keys = {}
    for i = 1, n do keys[i] = p[2](i) end
    local t = recs(keys)
    table.sort(t, byk)
    line[#line + 1] = p[1] .. "=" .. (stable_after(t) and "保" or "翻")
  end
  print(table.concat(line, " "))
end

print("== D. 工程后果：先按姓名排、再按分数排，并列名次还认姓名序吗 ==")
local students = {
  { name = "s1", score = 90 }, { name = "s2", score = 88 },
  { name = "s3", score = 88 }, { name = "s4", score = 76 },
  { name = "s5", score = 88 }, { name = "s6", score = 65 },
  { name = "s7", score = 90 }, { name = "s8", score = 70 },
}
local names = function(list)
  local s = {}
  for i = 1, #list do s[i] = list[i].name end
  return table.concat(s, ",")
end
table.sort(students, function(a, b) return a.name < b.name end)   -- 第一步：姓名
local by_score = function(a, b) return a.score < b.score end
table.sort(students, by_score)                                    -- 第二步：分数
print("D 原生两步 -> " .. names(students))
local stable_students = {
  { name = "s1", score = 90 }, { name = "s2", score = 88 },
  { name = "s3", score = 88 }, { name = "s4", score = 76 },
  { name = "s5", score = 88 }, { name = "s6", score = 65 },
  { name = "s7", score = 90 }, { name = "s8", score = 70 },
}
table.sort(stable_students, function(a, b) return a.name < b.name end)
K.msort(stable_students, by_score)                                -- 归并版第二步
print("D 归并两步 -> " .. names(stable_students))
