-- modkit.lua：探针公共库（run_lua.py 通过 package.preload["modkit"] 注入）
-- 只做版本适配与观测，不产生输出，避免污染各脚本的终端画面。
local M = {}

M.VERSION = _VERSION
M.isjit = (type(jit) == "table" and jit.version) or "nil"
M.searchers = package.searchers or package.loaders
M.searchers_name = package.searchers and "package.searchers" or "package.loaders"
M.dirsep = package.config:sub(1, 1)
M.pathsep = package.config:sub(3, 3)

function M.envline()
  return string.format("ENV\t%s\tjit=%s\t%s=%d\tmodule=%s\tsearchpath=%s",
    _VERSION, M.isjit, M.searchers_name, #M.searchers,
    type(module), type(package.searchpath))
end

-- 5.1 用 loadstring + setfenv；5.2+ 用 load(..., "t", _G)
function M.loadchunk(src, name)
  if loadstring then
    local f, err = loadstring(src, name)
    if f and setfenv then setfenv(f, _G) end
    return f, err
  end
  return load(src, name, "t", _G)
end

function M.split(s, sep)
  local out = {}
  for part in (s .. sep):gmatch("(.-)" .. sep) do out[#out + 1] = part end
  return out
end

-- require 的搜索名：点号换成目录分隔符（a.b -> a\b）
function M.namepath(name)
  return (name:gsub("%.", M.dirsep))
end

-- 某条 package.path 模板代入模块名：?.lua -> src/mods/a.lua
function M.apply(tmpl, name)
  return (tmpl:gsub("%?", M.namepath(name)))
end

function M.globals()
  local set = {}
  for k in pairs(_G) do set[k] = true end
  return set
end

function M.added(before)
  local names = {}
  for k in pairs(_G) do
    if not before[k] then names[#names + 1] = tostring(k) end
  end
  table.sort(names)
  return names
end

function M.join(t)
  return table.concat(t, ",")
end

return M
