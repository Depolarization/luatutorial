-- t4_nilchain.lua · nil 的静默传播链，与「一句错误文案」的版本差异
local errkit = require("errkit")

local nillocal = nil   -- 对下面的闭包来说，它是 upvalue

local function grab(fn)
  local ok, e = pcall(fn)
  return tostring(e)
end

print("== A. 同一种坏法，文案里能不能报出名字 ==")
print("A 索引 local      -> " .. grab(function() local t = nil return t.field end))
print("A 索引 upvalue    -> " .. grab(function() return nillocal.field end))
print("A 索引 global     -> " .. grab(function() return zz_missing_global.field end))
print("A 索引 表字段     -> " .. grab(function() local t = {} return t.missing.deep end))
print("A 索引 表达式结果 -> " .. grab(function() return ({})[1].field end))
print("A 调用 local      -> " .. grab(function() local f = nil return f() end))
print("A 调用 global     -> " .. grab(function() return zz_missing_global() end))
print("A 取 nil 长度     -> " .. grab(function() local v = nil return #v end))
print("A 拼接 nil        -> " .. grab(function() local v = nil return "x" .. v end))
print("A 算术 nil        -> " .. grab(function() local v = nil return v + 1 end))
print("A 比较 nil        -> " .. grab(function() local v = nil return v < 1 end))

print("== B. 三层配置链：文案只说值坏在哪，不说哪一层取错 ==")
local config = { db = { host = "127.0.0.1", port = 5432 } }
local function get(node, key)
  if type(node) ~= "table" then
    return nil
  end
  return node[key]
end
local function open_conn_ok(cfg)
  local db = get(cfg, "db")
  local host = get(db, "host")
  local port = get(db, "port")
  return "tcp://" .. tostring(host) .. ":" .. tostring(port)
end
local function open_conn_bug(cfg)
  local host = get(cfg, "db")     -- 少取一层：host 其实是 db 这张表
  local port = get(host, "port")
  return "tcp://" .. host .. ":" .. port
end
local function open_conn_miss(cfg)
  local host = get(cfg, "db")     -- 配置里根本没有 db
  local port = get(host, "port")
  return "tcp://" .. host .. ":" .. port
end
print("B 链取对了        -> " .. grab(function() return open_conn_ok(config) end))
print("B host 少取一层   -> " .. grab(function() return open_conn_bug(config) end))
print("B 配置里没有 db   -> " .. grab(function() return open_conn_miss({}) end))
print("B 整份配置是 nil  -> " .. grab(function() return open_conn_miss(nil) end))

print("== C. 守卫写法各自把错误变成什么 ==")
local missing = nil
print("C t and t.x       -> " .. tostring(missing and missing.x))
print("C (t or {}).x     -> " .. tostring((missing or {}).x))
print("C rawget 用在 nil -> " .. grab(function() return rawget(missing, "x") end))
print("C pcall 包一层    -> ok=" .. tostring((pcall(function() return missing.x end)))
  .. " 值=" .. tostring(select(2, pcall(function() return missing.x end))))

print("== D. 尽早炸：带 level 的字段检查，位置指回调用方 ==")
local function need(node, key, site)
  if type(node) ~= "table" then
    error("E_TYPE 配置节点不是表: " .. tostring(site), 2)
  end
  local v = node[key]
  if v == nil then
    error("E_MISSING 缺字段 " .. tostring(key) .. " 于 " .. tostring(site), 2)
  end
  return v
end
local function open_conn_strict(cfg)
  local db = need(cfg, "db", "config.db")
  local host = need(db, "host", "config.db.host")
  local port = need(db, "port", "config.db.port")
  return "tcp://" .. host .. ":" .. port
end
print("D 少 db      -> " .. grab(function() return open_conn_strict({}) end))
print("D 整份是 nil -> " .. grab(function() return open_conn_strict(nil) end))
print("D 少 port    -> " .. grab(function() return open_conn_strict({ db = { host = "h" } }) end))
print("D 正常       -> " .. grab(function() return open_conn_strict(config) end))
local function table_error_case()
  local function need2(node, key)
    if node == nil then
      error({ code = "E_TYPE", msg = key }, 2)
    end
    return node[key]
  end
  return need2(nil, "db")
end
print("D 表错误对象 -> " .. errkit.describe(select(2, pcall(table_error_case)))
  .. " type=" .. type(select(2, pcall(table_error_case)))
  .. " 带位置前缀吗=" .. tostring(tostring(select(2, pcall(table_error_case))):find(":%d+: ") ~= nil))

print("== E. 静默传播的代价：算错了也没人报错 ==")
local function stat_of(unit, key)
  local s = unit and unit.stats
  return s and s[key]
end
local function dps(unit)
  local atk = stat_of(unit, "atk")
  local mult = stat_of(unit, "mult")
  return (atk or 0) * (mult or 1)
end
local unit_ok = { stats = { atk = 50, mult = 2 } }
local unit_typo = { stats = { atk = 50, multi = 2 } }
local unit_nil = nil
print("E 正常单位        dps=" .. tostring(dps(unit_ok)) .. " type=" .. type(dps(unit_ok)))
print("E 字段名打错      dps=" .. tostring(dps(unit_typo)) .. "  <- 静默按 1 算，一声不吭")
print("E 单位是 nil      dps=" .. tostring(dps(unit_nil)) .. "  <- 静默按 0 算，一声不吭")
print("E 三种结果一样吗  -> " .. tostring(dps(unit_ok) == dps(unit_typo)))
