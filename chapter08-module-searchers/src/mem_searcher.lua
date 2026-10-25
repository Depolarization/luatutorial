-- 1. 模块源码不放文件系统，直接放在一张 Lua 表里
local K = require("modkit")
print(K.envline())

local SOURCES = {
  memat = [[
    MEM_RUNS = (MEM_RUNS or 0) + 1
    local M = { name = "memat", runs = MEM_RUNS }
    function M.hello(who) return "hello " .. who end
    return M
  ]],
  memdep = [[
    local a = require("memat")
    return { from = "memdep", dep = a.name }
  ]],
}

-- 2. 自定义 searcher：命中就返回 loader，未命中返回一段错误说明
local S = K.searchers
local function memsearcher(name)
  local src = SOURCES[name]
  if not src then
    return "\n\tno memory module '" .. name .. "'"
  end
  local f, err = K.loadchunk(src, "=mem:" .. name)
  if not f then return "\n\tmem load error: " .. tostring(err) end
  local function loader(...)
    local n = select("#", ...)
    local extra = select(2, ...)
    print(string.format("LOADER\t%s\targs=%d\targ2=%s",
      name, n, extra == nil and "nil" or tostring(extra)))
    return f(...)
  end
  return loader, "mem:" .. name
end
table.insert(S, 1, memsearcher)

-- 3. 文件系统里根本没有 memat.lua，先证明内置 searcher 全部落空
local miss = 0
for i = 2, #S do
  local r = S[i]("memat")
  if type(r) ~= "function" then miss = miss + 1 end
end
print(string.format("SEARCHERS\t%s\tcount=%d\tfs_miss=%d",
  K.searchers_name, #S, miss))
local fh = io.open("memat.lua", "r")
print("DISK_ONLY\tio.open(\"memat.lua\")=" .. tostring(fh))
if fh then fh:close() end

-- 4. 绕过文件系统 require：loader 参数、缓存、模块体执行次数
local m1 = require("memat")
print(string.format("FIRST\truns=%d\thello=%s",
  m1.runs, m1.hello("lua")))
local m2 = require("memat")
print(string.format("SECOND\tsame_table=%s\truns=%d",
  tostring(m1 == m2), MEM_RUNS))

package.loaded["memat"] = nil
local m3 = require("memat")
print(string.format("RELOAD\tnew_table=%s\truns=%d",
  tostring(m3 ~= m1), MEM_RUNS))

-- 5. 内存模块之间也能互相 require
local d = require("memdep")
print(string.format("DEP\tfrom=%s\tdep=%s", d.from, d.dep))

-- 6. 未命中：走到内存 searcher 时返回可读的失败信息
local ok, err = pcall(require, "nope_zzz")
print(string.format("MISS\tok=%s\thas_mem_msg=%s",
  tostring(ok),
  tostring(tostring(err):find("no memory module", 1, true) ~= nil)))

-- 7. 卸载 searcher 后，同一个名字不再能加载
table.remove(S, 1)
local ok2 = pcall(require, "memat2_after_uninstall")
print("UNINSTALL\trequire_after=" .. (ok2 and "hit" or "miss"))
