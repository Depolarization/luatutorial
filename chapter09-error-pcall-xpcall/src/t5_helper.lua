-- t5_helper.lua · 调试助手实战：出错自动打印位置 + 每帧局部变量快照
local errkit = require("errkit")

-- 一个假装从 MOD 里读到的配置：第 3 项缺 speed 字段。
-- 数值全用整数：5.1 只有一个 number 类型，整数结果打印成 26 而不是 26.0，
-- 用小数会给「五端逐行比对」添上与本章无关的差异。每段各拿一份新表，互不污染。
local function fresh_db()
  return {
    { id = 1, hp = 30, speed = 4 },
    { id = 2, hp = 55, speed = 2 },
    { id = 3, hp = 80 },
  }
end

local function step_monster(m, dt)
  local nv = m.speed * dt
  m.hp = m.hp - nv
  return m.hp
end

local function on_tick(entities, dt)
  local moved = 0
  for i = 1, #entities do
    local e = entities[i]
    local remain = step_monster(e, dt)
    moved = moved + 1
  end
  return moved
end

print("== A. 裸奔：错误只有一行，也没说是哪个怪 ==")
local db_a = fresh_db()
local ok_a, e_a = pcall(on_tick, db_a, 1)
print("A ok=" .. tostring(ok_a) .. " -> " .. tostring(e_a))
print("A 崩之前已经扣过的血 -> " .. tostring(db_a[1].hp) .. "," .. tostring(db_a[2].hp)
  .. "," .. tostring(db_a[3].hp))

print("== B. 交给助手：位置 + 每帧局部变量 ==")
local ok_b, diag_b = errkit.call(on_tick, fresh_db(), 1)
print("B ok=" .. tostring(ok_b))
print("B -> " .. tostring(diag_b))

print("== C. 自己造的错也能带现场 ==")
local ok_c, diag_c = errkit.call(function(a, b)
  local sum = a + b
  if sum > 100 then
    error("SUM 溢出", 0)
  end
  return sum
end, 40, 70)
print("C ok=" .. tostring(ok_c) .. " -> " .. tostring(diag_c))

print("== D. 逐项重试，崩在第几项也能报出来 ==")
local db_d = fresh_db()
for attempt = 1, 4 do
  local idx = attempt
  local ok, e = xpcall(function()
    local pick = db_d[idx]
    local rest = step_monster(pick, 1)
    return rest
  end, errkit.handler)
  if ok then
    print("D 第 " .. attempt .. " 项 ok hp=" .. tostring(e))
  else
    print("D 第 " .. attempt .. " 项 fail " .. errkit.clip(tostring(e):gsub("\n", " | "), 150))
  end
end

print("== E. 修好它：缺字段就补默认值 ==")
local function with_default(m)
  if m.speed == nil then
    return setmetatable({ id = m.id, hp = m.hp, speed = 1 }, { __name = "patched" })
  end
  return m
end
local db_e = fresh_db()
local ok_e, e_e = xpcall(function()
  for i = 1, #db_e do
    step_monster(with_default(db_e[i]), 1)
  end
  return "全部处理 " .. #db_e .. " 个"
end, errkit.handler)
print("E ok=" .. tostring(ok_e) .. " -> " .. tostring(e_e))
print("E 补默认后 hp -> " .. tostring(db_e[1].hp) .. "," .. tostring(db_e[2].hp) .. "," .. tostring(db_e[3].hp))

print("== F. 层号从谁开始数：多包一层就整体偏移一层 ==")
local HUNTED = "我要被找到"
local function probe(offset)
  local s = errkit.snapshot(offset, 24, 4000)
  local first = s:match("([%w_%(%)%*%-]+)=")
  return "第 " .. offset .. " 层 首个局部=" .. tostring(first)
    .. " 找到HUNTED=" .. tostring(s:find("HUNTED", 1, true) ~= nil)
end
print("F 主 chunk 里 snapshot(1) -> " .. errkit.snapshot(1, 6))
print("F 主 chunk 里 snapshot(2) 找到HUNTED -> "
  .. tostring(errkit.snapshot(2, 24, 4000):find("HUNTED", 1, true) ~= nil))
print("F 包一层函数、传 2 -> " .. probe(2))
print("F 包一层函数、传 3 -> " .. probe(3))
