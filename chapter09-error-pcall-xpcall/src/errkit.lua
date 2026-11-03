-- errkit.lua · 错误处理公共库（选题10）
-- 一份源码同时在 Lua 5.1 / 5.2 / 5.3 / 5.4 / LuaJIT 上跑，不用任何 5.2+ 独有语法。
-- 流水线会把它 package.preload 注入，脚本用 require("errkit") 取。
--
-- 层号规矩（本章最大的坑）：debug.getinfo / debug.getlocal 的 level 都从「此刻正在执行的
-- 那个函数」开始数，1 就是它自己。所以谁调用它们，谁就得自己数层号——
-- 把 getlocal 封装进一个函数，层号会整体偏移一层。errkit.handler 故意不封装局部变量抓取。

local errkit = {}

local unpack_fn = table.unpack or unpack

-- 截断到 max 字节，并且绝不切断一个 UTF-8 字符
function errkit.clip(s, max)
  s = tostring(s)
  if #s <= max then
    return s
  end
  local cut = max
  while cut > 1 and s:byte(cut) >= 128 and s:byte(cut) < 192 do
    cut = cut - 1
  end
  return s:sub(1, cut) .. ".."
end

-- 地址每进程每解释器都不同，先抹平，跨端输出才能逐行比对；长值顺手截断
function errkit.redact(v)
  local s = tostring(v)
  s = s:gsub("0x%x%x%x+", "<addr>")
  s = s:gsub("%x%x%x%x%x%x%x+", "<addr>")
  return errkit.clip(s, 40)
end

-- 可移植编译：5.1 的 load 不接受字符串（要用 loadstring），5.2 起 loadstring 被删
function errkit.compile(src, name)
  if loadstring then
    return loadstring(src, name)
  end
  return load(src, name)
end

-- 把任意错误对象变成一行文本：字符串原样，table 取 code/msg，其余走 type(值)
function errkit.describe(e)
  local t = type(e)
  if t == "string" then
    return e
  end
  if t == "table" then
    local code = rawget(e, "code")
    local msg = rawget(e, "msg") or rawget(e, "message")
    if code ~= nil or msg ~= nil then
      return "table{code=" .. tostring(code) .. ", msg=" .. tostring(msg) .. "}"
    end
    local n = 0
    for _ in pairs(e) do n = n + 1 end
    return "table{" .. tostring(n) .. " keys}"
  end
  return t .. "(" .. errkit.redact(e) .. ")"
end

-- 从「调用本函数的那一层」往下抓局部变量。level 直接交给 debug.getlocal，
-- 所以 1 = errkit.snapshot 自己，2 = 调用我的那一帧——传参加一即是「我的调用方」。
function errkit.snapshot(level, limit, max_chars)
  if not debug.getinfo(level, "S") then
    return ""
  end
  local parts = {}
  local i = 1
  local max = limit or 14
  while i <= max do
    local name, val = debug.getlocal(level, i)
    if not name then
      break
    end
    parts[#parts + 1] = name .. "=" .. errkit.redact(val)
    i = i + 1
  end
  return errkit.clip(table.concat(parts, " "), max_chars or 220)
end

-- 上值按函数对象抓，不吃层号，所以可以安全封装
function errkit.upvalue_dump(fn, limit)
  if type(fn) ~= "function" then
    return ""
  end
  local parts = {}
  local i = 1
  local max = limit or 10
  while i <= max do
    local name, val = debug.getupvalue(fn, i)
    if not name then
      break
    end
    parts[#parts + 1] = name .. "=" .. errkit.redact(val)
    i = i + 1
  end
  return table.concat(parts, " ")
end

-- 抓某一层的局部变量。故意写成 handler 内部的局部函数并在调用处 +1 换算：
-- 本函数自己也占一层，不换算就会整体少一层——这正是「封装调试助手」最容易踩的坑。
local function locals_at(level_from_handler, max)
  local parts = {}
  local i = 1
  local level = level_from_handler + 1
  while i <= max do
    local name, val = debug.getlocal(level, i)
    if not name then
      break
    end
    parts[#parts + 1] = name .. "=" .. errkit.redact(val)
    i = i + 1
  end
  return table.concat(parts, " ")
end

-- 调试助手主入口：错误描述 + 每一帧的位置、局部变量、上值。
-- 给 xpcall 当 msgh 用——此刻栈还没展开，还能一层层问。
function errkit.handler(e)
  local lines = {"[errkit] " .. errkit.clip(errkit.describe(e), 120)}
  local level = 2
  while level <= 5 do
    local ar = debug.getinfo(level, "Snluf")
    if not ar then
      break
    end
    local tag = ar.namewhat
    if not tag or tag == "" then
      tag = tostring(ar.what)
    end
    lines[#lines + 1] = "  L" .. tostring(level) .. " " .. tostring(ar.short_src)
      .. ":" .. tostring(ar.currentline) .. " " .. tostring(tag) .. "(" .. tostring(ar.name) .. ")"
    local loc = locals_at(level, 8)
    if loc ~= "" then
      lines[#lines + 1] = "      局部 " .. errkit.clip(loc, 160)
    end
    local up = errkit.upvalue_dump(ar.func, 6)
    if up ~= "" then
      lines[#lines + 1] = "      上值 " .. errkit.clip(up, 120)
    end
    level = level + 1
  end
  return errkit.clip(table.concat(lines, "\n"), 900)
end

-- 一行式调用：返回 ok, 结果或单行诊断。参数用闭包透传，五端行为一致
-- （xpcall 自己转发额外参数的能力是 5.2 才有的，见 t2/t6）。
function errkit.call(f, ...)
  local args = { ... }
  local n = select("#", ...)
  local function invoke()
    return f(unpack_fn(args, 1, n))
  end
  local ok, e = xpcall(invoke, errkit.handler)
  if ok then
    return true, tostring(e)
  end
  return false, tostring(e):gsub("\n", " \\n ")
end

-- 只捕获，不加工：保留原始错误对象的类型
function errkit.catch(f, ...)
  return pcall(f, ...)
end

return errkit
