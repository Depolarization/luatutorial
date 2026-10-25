-- 1. 把 package.path 当模板：逐条代入模块名，第一条命中的就是 require 选中的文件
local K = require("modkit")
print(K.envline())

local A = "src/mods/a/?.lua;src/mods/b/?.lua;"
package.path = A .. "src/mods/?.lua;" .. package.path
local hits = 0
for i, tmpl in ipairs(K.split(package.path, K.pathsep)) do
  if i > 4 then break end
  local cand = K.apply(tmpl, "same")
  local f = io.open(cand, "r")
  local ok = f ~= nil
  if f then f:close(); hits = hits + 1 end
  print(string.format("CAND[%d]\t%s\t%s", i, cand,
    ok and "HIT" or "miss"))
end

-- 2. 先 a 后 b：顺序决定同名模块谁生效
local B = "src/mods/b/?.lua;src/mods/a/?.lua;"
local first = require("same")
package.loaded["same"] = nil
package.path = B .. "src/mods/?.lua;" .. package.path
local second = require("same")
print(string.format("ORDER\tfirst=%s\tafter_swap=%s\thits=%d",
  first.tag, second.tag, hits))

-- 3. package.searchpath 就是 C 源码里那套 searchpath（5.1 无，LuaJIT 有）
if package.searchpath then
  local p = package.searchpath("demo_mod", package.path)
  print("SEARCHPATH\tdemo_mod\t" .. tostring(p))
else
  print("SEARCHPATH\tnil\tLua 5.1 没有这个函数")
end

-- 4. 点号转目录：a.b -> a/b，再代入 ? 占位符
local dotted = K.namepath("pkg.sub")
local dcand = K.apply("src/mods/?.lua", "pkg.sub")
print(string.format("DOTTED\tpkg.sub\t%s\t%s", dotted, dcand))
local sub = require("pkg.sub")
print(string.format("DOTTED_LOAD\t%s\t%s", sub.tag, sub.file))

-- 5. 同一个文件模块 require 两次：表相同，模块体只跑一次
local m1 = require("demo_mod")
local m2 = require("demo_mod")
print(string.format("FILE_CACHE\tsame_table=%s\truns=%d\ttag=%s",
  tostring(m1 == m2), m1.runs, m1.tag))
