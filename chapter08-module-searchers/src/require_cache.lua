-- 1. 改文件不生效：require 只认 package.loaded，不认文件时间戳
local K = require("modkit")
print(K.envline())
package.path = "out/?.lua;" .. package.path

local function write_mod(v)
  local f = assert(io.open("out/probe_mod.lua", "w"))
  local tpl = "PROBE_RUNS = (PROBE_RUNS or 0) + 1\n" ..
              "return { v = %d, run = PROBE_RUNS }\n"
  f:write(tpl:format(v))
  f:close()
end

write_mod(1)
local m1 = require("probe_mod")
write_mod(2)  -- 磁盘上的文件已经改成 v=2

local f = io.open("out/probe_mod.lua", "r")
local disk_v = tonumber(f:read("*a"):match("v = (%d+)"))
f:close()

-- 2. 第二次 require：文件变了，但缓存还在
local m2 = require("probe_mod")
print(string.format("DISK\tfile_v=%d\tchunk_runs=%d",
  disk_v, PROBE_RUNS))
print(string.format("CACHED\trequire_v=%d\tsame_table=%s\truns=%d",
  m2.v, tostring(m1 == m2), PROBE_RUNS))

-- 3. 手动清缓存：package.loaded[name] = nil 才会真正重跑模块体
package.loaded["probe_mod"] = nil
local m3 = require("probe_mod")
print(string.format("FORCE_NIL\trequire_v=%d\tnew_table=%s\truns=%d",
  m3.v, tostring(m3 ~= m1), PROBE_RUNS))

-- 4. 把 loaded 写成哨兵表：require 直接返回它，连 searcher 都不跑
local sentinel = { v = 99, tag = "sentinel" }
package.loaded["probe_mod"] = sentinel
local m4 = require("probe_mod")
print(string.format("SENTINEL\tgot=%s\tv=%d\truns=%d",
  tostring(m4.tag), m4.v, PROBE_RUNS))

-- 5. loaded = false：5.1 与 5.2+ 的语义分歧点，实测说话
package.loaded["probe_mod"] = false
local ok, m5 = pcall(require, "probe_mod")
local shown = (type(m5) == "table" and tostring(m5.v))
  or tostring(m5)
print(string.format("FALSE_CACHE\tok=%s\ttype=%s\tvalue=%s\truns=%d",
  tostring(ok), type(m5), shown, PROBE_RUNS))

os.remove("out/probe_mod.lua")
