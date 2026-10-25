-- 1. 环境与包字段：五家解释器各跑一遍，先看它们自报的底牌
-- 画面上的版本差异全部来自这份输出，不抄文档。
local K = require("modkit")
print(K.envline())

print(string.format(
  "API\tsetfenv=%s\tloadstring=%s\ttable.unpack=%s\tseeall=%s",
  type(setfenv), type(loadstring), type(table.unpack),
  type(package.seeall)))

print(string.format(
  "CONFIG\tdirsep=%s\tpathsep=%s\tmark=%s\texec=%s\tignore=%s",
  K.dirsep, K.pathsep, package.config:sub(5, 5),
  package.config:sub(7, 7), package.config:sub(9, 9)))

local pe = K.split(package.path, K.pathsep)
local ce = K.split(package.cpath, K.pathsep)
local le = 0
for _ in pairs(package.loaded) do le = le + 1 end
print(string.format(
  "PKG\tpath_entries=%d\tcpath_entries=%d\tloaded=%d", #pe, #ce, le))

for _, i in ipairs { 1, 2, 3 } do
  if pe[i] then print(string.format("PATH[%d]\t%s", i, pe[i])) end
end
if pe[#pe] then
  print(string.format("PATH[%d]\t%s", #pe, pe[#pe]))
end
if ce[1] then print("CPATH[1]\t" .. ce[1]) end
