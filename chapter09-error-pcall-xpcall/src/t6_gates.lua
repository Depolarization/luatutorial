-- t6_gates.lua · 版本能力门：一次跑完，得到一张 5 端矩阵表
local errkit = require("errkit")

local function verdict(name, f)
  local ok, v = pcall(f)
  if ok then
    print("G " .. name .. " -> " .. tostring(v))
  else
    print("G " .. name .. " -> ERR " .. tostring(v))
  end
end

-- 语法门：能不能编译，不执行
local function syntax(name, src)
  local f, e = errkit.compile(src, "g_" .. name)
  if f then
    return "可用"
  end
  return "编译失败: " .. tostring(e)
end
print("G goto 语法 -> " .. syntax("goto", "goto lab ::lab:: return 1"))
print("G <close> 属性 -> " .. syntax("close", "local o <close> = nil return 1"))
print("G <const> 属性 -> " .. syntax("const", "local k <const> = 1 return k"))
print("G 普通代码 -> " .. syntax("plain", "return 7"))

-- API 门
verdict("loadstring 存在", function() return type(rawget(_G, "loadstring")) end)
verdict("load 能吃字符串", function()
  local ok, res = pcall(function() return load("return 7", "g_loadstr") end)
  if not ok then
    return "报错 " .. tostring(res)
  end
  if not res then
    return "编译失败"
  end
  return "可用 值=" .. tostring(res())
end)
verdict("warn 存在", function() return type(rawget(_G, "warn")) end)
verdict("bit32 存在", function() return type(rawget(_G, "bit32")) end)
verdict("bit 存在", function() return type(rawget(_G, "bit")) end)
verdict("table.unpack 存在", function() return type(rawget(_G, "table") and rawget(_G, "table").unpack) end)
verdict("math.type 存在", function() return type(rawget(_G, "math") and rawget(_G, "math").type) end)

-- 语义门（错误处理相关）
verdict("error 接受整数 level", function()
  local ok, e = pcall(function() local k = 1 error("L", 1.7) end)
  if tostring(e):find("bad argument") then return "拒绝浮点" end
  return "接受浮点"
end)
verdict("xpcall 转发额外参数给被保护函数", function()
  local got = "没收到"
  xpcall(function(a) got = tostring(a) end, function(e) return e end, "SENT")
  return got
end)
verdict("xpcall 缺 handler 的文案", function()
  local ok, e = pcall(function() xpcall(function() error("x", 0) end) end)
  return tostring(e):gsub(".*xpcall' ", ""):sub(1, 40)
end)
verdict("tostring 尊重 __name", function()
  return errkit.redact(tostring(setmetatable({}, { __name = "mytype" })))
end)
verdict("索引 nil 的原始文案", function()
  local ok, e = pcall(function()
    local t = nil
    return t.k
  end)
  return tostring(e)
end)
verdict("yield 能穿过 pcall", function()
  local co = coroutine.create(function()
    local r = { pcall(function() return coroutine.yield("V") end) }
    return tostring(r[1]) .. "," .. tostring(r[2])
  end)
  local ok, v = coroutine.resume(co)
  if not ok then return "resume 失败 " .. tostring(v) end
  if tostring(v):find("yield across") then return "不能" end
  return "能 " .. tostring(v)
end)
verdict("traceback 里带不带 C 帧 pcall", function()
  local tb = nil
  xpcall(function() error("T", 0) end, function(e) tb = debug.traceback(e) return e end)
  if tostring(tb):find("in function 'pcall'") or tostring(tb):find("in 'pcall'") then
    return "有 [C] pcall 帧"
  end
  return "无 pcall 帧"
end)

-- 伪局部命名：调用表达式求值的那一瞬间，主 chunk 那一帧里躺着临时槽。
-- 必须像下面这样「从主 chunk 直接调、还多传一个参数」才抓得到那层槽。
local function scan_pseudo()
  for lvl = 1, 6 do
    local s = errkit.snapshot(lvl, 24, 4000)
    if s:find("(C temporary)", 1, true) then
      return "(C temporary) 5.4 的 C 帧槽 第" .. lvl .. "层"
    end
    if s:find("(*temporary)", 1, true) then
      return "(*temporary) 5.1-5.3/LuaJIT 第" .. lvl .. "层"
    end
    if s:find("(temporary)", 1, true) then
      return "(temporary) 5.4 第" .. lvl .. "层"
    end
  end
  return "没找到伪局部"
end
print("G getlocal 伪局部命名 -> " .. scan_pseudo("LITERAL_ARG"))
