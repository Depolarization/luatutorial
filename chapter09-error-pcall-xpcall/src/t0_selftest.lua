-- t0_selftest.lua · 公共库自检：确认 errkit 在五端行为一致，后面各章的输出才可信
local errkit = require("errkit")

local pass, fail = 0, 0
local function check(name, ok, detail)
  if ok then
    pass = pass + 1
    print("PASS " .. name)
  else
    fail = fail + 1
    print("FAIL " .. name .. " -> " .. tostring(detail))
  end
end

-- 1) 可移植编译：能编、能跑、语法错能拿到错误串而不是崩溃
local fn, err = errkit.compile("return 6 * 7", "chunk_calc")
check("compile_returns_function", type(fn) == "function", tostring(fn))
check("compile_runs", fn and fn() == 42, "no 42")
local bad, bad_err = errkit.compile("local x = = 1", "chunk_bad")
check("compile_rejects_syntax", bad == nil, "编译本该失败")
check("compile_gives_message", type(bad_err) == "string", tostring(bad_err))

-- 2) describe：字符串 / 带 code 的表 / 空表 / 数字 / nil
check("describe_string", errkit.describe("plain") == "plain", errkit.describe("plain"))
local e_tbl = errkit.describe({ code = 7, msg = "boom" })
check("describe_table", e_tbl == "table{code=7, msg=boom}", e_tbl)
check("describe_empty_table", errkit.describe({}) == "table{0 keys}", errkit.describe({}))
check("describe_number", errkit.describe(42) == "number(42)", errkit.describe(42))
check("describe_nil", errkit.describe(nil) == "nil(nil)", errkit.describe(nil))

-- 3) redact 把地址抹平（跨端可比对）
local red = errkit.redact({})
check("redact_table_addr", not red:find("0x") and not red:match("%x%x%x%x%x%x%x"), red)

-- 4) snapshot 能看见调用方的局部变量名（level 2 = 调用我的那一帧）
local alpha, beta = 11, 22
local snap = errkit.snapshot(2)
check("snapshot_sees_alpha", snap:find("alpha=11", 1, true) ~= nil, snap)
check("snapshot_sees_beta", snap:find("beta=22", 1, true) ~= nil, snap)

-- 5) handler 在栈未展开时能看到出错那一层
local okh, diag = errkit.call(function(gamma)
  local delta = "d"
  error("HIDDEN", 0)
end, 99)
check("call_detects_error", okh == false, tostring(okh))
check("diag_has_describe", diag:find("[errkit] HIDDEN", 1, true) ~= nil, diag)
check("diag_has_frames", diag:find("  L", 1, true) ~= nil, diag)

-- 6) catch 保留原始错误对象类型
local okc, obj = errkit.catch(function() error({ code = 3 }, 0) end)
check("catch_keeps_table", okc == false and type(obj) == "table" and obj.code == 3, tostring(obj))

print("SUMMARY pass=" .. pass .. " fail=" .. fail)
