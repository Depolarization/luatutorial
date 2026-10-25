-- 1. 旧式 module()：创建全局表并把当前 chunk 的环境换过去
local K = require("modkit")
print(K.envline())
print(string.format("API\tmodule=%s\tseeall=%s",
  type(module), type(package.seeall)))

if type(module) == "function" then
  local before = K.globals()
  local old_chunk = assert(K.loadchunk([[
    module("legacymod")
    function greet() return "hi from legacymod" end
    VALUE = 42
  ]], "=old:legacymod"))
  local ok = pcall(old_chunk)
  local added = K.added(before)
  local old = _G.legacymod
  print(string.format(
    "OLD\tok=%s\tglobals_added=%s\tloaded=%s\tgreet=%s\tVALUE=%s",
    tostring(ok), K.join(added), type(package.loaded["legacymod"]),
    old and type(old.greet) or "nil",
    old and tostring(old.VALUE) or "nil"))

  if type(package.seeall) == "function" then
    local before2 = K.globals()
    local see_chunk = assert(K.loadchunk([[
      module("legacy2", package.seeall)
      LEAK = 1
      return _VERSION
    ]], "=old:legacy2"))
    local ok2, ver = pcall(see_chunk)
    local added2 = K.added(before2)
    local l2 = _G.legacy2
    local fmt = "SEEALL\tok=%s\tread=%s\tglobals_added=%s\t" ..
                "write_global=%s\twrite_module=%s"
    print(string.format(fmt, tostring(ok2), tostring(ver),
      K.join(added2), tostring(_G.LEAK), tostring(l2 and l2.LEAK)))
  else
    print("SEEALL\tunavailable\tpackage.seeall=nil")
  end
else
  print("OLD\tskipped\tmodule() 在该构建里不存在")
end

-- 2. clean module：返回一张表，不碰 _G
local before3 = K.globals()
local clean_chunk = assert(K.loadchunk([[
  local M = {}
  M.VALUE = 42
  function M.greet() return "hi from clean" end
  return M
]], "=clean:cleanmod"))
local c = clean_chunk()
local added3 = K.added(before3)
print(string.format(
  "CLEAN\tglobals_added=%s\treturned=%s\tgreet=%s\tVALUE=%d",
  K.join(added3), type(c), c.greet(), c.VALUE))

-- 3. 反面教材：直接往 _G 撒函数
local before4 = K.globals()
local global_chunk = assert(K.loadchunk([[
  function helper() return 1 end
  function util() return 2 end
]], "=global:style"))
global_chunk()
local added4 = K.added(before4)
print(string.format("GLOBAL_STYLE\tglobals_added=%s\tcount=%d",
  K.join(added4), #added4))
