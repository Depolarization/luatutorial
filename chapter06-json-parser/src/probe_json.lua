-- probe_json.lua — 把 JSON 解析器的每个知识点在真实解释器上跑一遍。
-- 输出分节：[SECTION] name ... [/SECTION]；@K 行供数据页做表格。
local J = require("jsonkit")

local sub, fmt = string.sub, string.format
local concat = table.concat

local function mtype(v)
  if math.type then return math.type(v) end
  return "number"                       -- 5.1/5.2 只有 double，Lua 类型名仍是 number
end

local function show_num(v)
  if math.type and math.type(v) == "integer" then return fmt("%d", v) end
  if v ~= v then return "nan" end
  if v == math.huge then return "inf" end
  if v == -math.huge then return "-inf" end
  if v == math.floor(v) and math.abs(v) < 1e19 then return fmt("%.0f", v) end
  return fmt("%.17g", v)
end

local function vis(s)
  local out = {}
  for i = 1, #s do
    local b = string.byte(s, i)
    if b == 34 then out[#out + 1] = '\\"'
    elseif b == 92 then out[#out + 1] = "\\\\"
    elseif b == 10 then out[#out + 1] = "\\n"
    elseif b == 9 then out[#out + 1] = "\\t"
    elseif b == 13 then out[#out + 1] = "\\r"
    elseif b == 8 then out[#out + 1] = "\\b"
    elseif b == 12 then out[#out + 1] = "\\f"
    elseif b < 32 then out[#out + 1] = fmt("\\u%04X", b)
    else out[#out + 1] = string.char(b) end
  end
  return concat(out)
end

local function sec(name) print("[SECTION] " .. name) end
local function endsec() print("[/SECTION]") end
local function kv(k, v) print("@K\t" .. k .. "\t" .. tostring(v)) end

local total, passed = 0, 0
local function check(name, cond, detail)
  total = total + 1
  if cond then
    passed = passed + 1
    print("  [PASS] " .. name .. (detail and ("  " .. detail) or ""))
  else
    print("  [FAIL] " .. name .. (detail and ("  " .. detail) or ""))
  end
end

local jitv = rawget(_G, "jit") and jit.version or "无"
local rt = _VERSION .. (jitv ~= "无" and (" / " .. jitv) or "")

-- 1. 环境
sec("env")
print("RUNTIME\t" .. rt)
print("math.type\t" .. (math.type and "有（integer / float 子类型）" or "无（只有 double）"))
print("Lua 版本\t" .. _VERSION)
kv("runtime", rt)
kv("has_math_type", math.type and "yes" or "no")
endsec()

-- 2. tokenizer
sec("tokens")
local SAMPLE = [=[{"name":"lua","n":3,"ok":true,"none":null}]=]
local toks, terr = J.tokenize(SAMPLE)
print("输入 " .. #SAMPLE .. " 字节：" .. SAMPLE)
if not toks then
  print("错误：" .. terr)
else
  for i, t in ipairs(toks) do
    local val = ""
    if t.kind == "string" then val = '"' .. vis(t.value) .. '"'
    elseif t.kind == "number" then val = show_num(t.value)
    elseif t.kind == "null" then val = "null"
    end
    print(fmt("%2d  %-7s %-14s @%d", i, t.kind, val, t.pos))
  end
  kv("token_count", #toks)
end
check("tokenizer 产出完整 token 流", toks ~= nil and #toks >= 15,
      toks and ("#=" .. #toks) or "nil")
endsec()

-- 3. 字面量
sec("literals")
local function try(label, txt)
  local v, e = J.decode(txt)
  if e then
    print(label .. " → 拒绝：" .. e)
    return nil, e
  end
  print(label .. " → " .. (v == J.null and "null 哨兵" or tostring(v)))
  return v, nil
end
local vnull = try("null", "null")
try("true", "true")
try("false", "false")
local _, e_nullx = try("nullx", "nullx")
local _, e_true1 = try("true1", "true1")
local _, e_nul = try("nul", "nul")
local arr = J.decode("[null,true,false]")
print("[null,true,false] → 长度 " .. #arr .. "，第 1 个是 " .. tostring(arr[1]))
kv("lit_nullx_err", e_nullx or "")
kv("lit_true1_err", e_true1 or "")
kv("lit_nul_err", e_nul or "")
kv("lit_array_len", #arr)
check("null 用哨兵而不是 nil", vnull == J.null and #arr == 3)
check("nullx 被拒绝", e_nullx ~= nil)
check("true1 被拒绝", e_true1 ~= nil)
endsec()

-- 4. 数字文法
sec("numbers")
local good = { "0", "-0", "3.25", "-1.5e-3", "1E+9", "123", "0.5", "10" }
local bad = { "01", "+1", ".5", "5.", "1e", "1e+", "--1", "nan",
              "Infinity", "0x10", "1..2" }
local good_ok, bad_ok = 0, 0
for _, s in ipairs(good) do
  local v, e = J.decode(s)
  if e then
    print(fmt("接受 %-8s → 错误 %s", s, e))
  else
    print(fmt("接受 %-8s → %s", s, show_num(v)))
    good_ok = good_ok + 1
  end
end
for _, s in ipairs(bad) do
  local v, e = J.decode(s)
  if e then
    print(fmt("拒绝 %-8s → %s", s, e))
    bad_ok = bad_ok + 1
  else
    print(fmt("拒绝 %-8s → 竟然接受了 %s", s, show_num(v)))
  end
end
kv("num_accept", good_ok .. "/" .. #good)
kv("num_reject", bad_ok .. "/" .. #bad)
check("合法数字全部接受", good_ok == #good)
check("非法数字全部拒绝", bad_ok == #bad)
endsec()

-- 5. double 精度边界
sec("precision")
local cases = {
  { "2^53", "9007199254740992" },
  { "2^53+1", "9007199254740993" },
  { "int64 上限", "9223372036854775807" },
  { "30 位整数", "123456789012345678901234567890" },
  { "1e308", "1e308" },
  { "1e309", "1e309" },
  { "1e999", "1e999" },
  { "1e-400", "1e-400" },
}
for _, c in ipairs(cases) do
  local v, e = J.decode(c[2])
  if e then
    print(c[1] .. " → 错误 " .. e)
  else
    print(fmt("%-10s %-32s type=%-7s math.type=%-7s tostring=%s",
      c[1], show_num(v), type(v), mtype(v), tostring(v)))
  end
end
local p2 = J.decode("9007199254740993")
local p2exact = J.decode("9007199254740992")
local pint = J.decode("9223372036854775807")
local pbig = J.decode("123456789012345678901234567890")
local pinf = J.decode("1e999")
local pzero = J.decode("1e-400")
local p308 = J.decode("1e308")
local p309 = J.decode("1e309")
kv("p_2p53", show_num(p2exact))
kv("p_2p53p1", show_num(p2))
kv("p_int64max", show_num(pint))
kv("p_big30", show_num(pbig))
kv("p_1e308", tostring(p308))
kv("p_1e309", tostring(p309))
kv("p_1e999", tostring(pinf))
kv("p_1e999_type", mtype(pinf))
kv("p_underflow", show_num(pzero))
check("精度边界都能解析", p2 ~= nil and pint ~= nil and pbig ~= nil and pinf ~= nil)
check("1e999 溢出为 inf", pinf == math.huge)
check("1e-400 下溢为 0", pzero == 0)
endsec()

-- 6. 5.3 整数子类型与回写
sec("types")
local type_cases = { "1", "1.0", "1e0", "-7", "0.5" }
for _, txt in ipairs(type_cases) do
  local v = J.decode(txt)
  local enc, e = J.encode(v)
  print(fmt("%-5s → type=%-6s math.type=%-7s encode=%s",
    txt, type(v), math.type and mtype(v) or "-", e or enc))
end
local t_int = J.decode("1")
local t_float = J.decode("1.0")
local t_exp = J.decode("1e0")
kv("t_int_type", mtype(t_int))
kv("t_float_type", mtype(t_float))
kv("t_exp_type", mtype(t_exp))
kv("t_enc_int", J.encode(t_int) or "err")
kv("t_enc_float", J.encode(t_float) or "err")
kv("t_enc_exp", J.encode(t_exp) or "err")
if math.type then
  check("纯整数解析为 integer", math.type(t_int) == "integer")
  check("带小数点解析为 float", math.type(t_float) == "float")
  check("1.0 回写保留小数", J.encode(t_float) == "1.0")
  check("1 回写为整数", J.encode(t_int) == "1")
else
  check("5.1/5.2 无 integer 子类型，全部 double", math.type == nil)
  check("整数 1 回写为 1.0（double）", J.encode(t_int) == "1.0")
end
endsec()

-- 7. 字符串转义
sec("escapes")
local raw = [=["a\"b\\c\/d\b\f\n\r\t"]=]
local s = J.decode(raw)
print("输入 " .. raw)
print("解析后长度 " .. #s .. " 字节")
print("字节 " .. J.bytes_hex(s))
print("可见 " .. vis(s))
kv("esc_len", #s)
kv("esc_vis", vis(s))
kv("esc_hex", J.bytes_hex(s))
local esc_bad = { '"\\q"', '"\\u12"', '"\\uZZZZ"' }
local esc_bad_ok = 0
for _, txt in ipairs(esc_bad) do
  local v, e = J.decode(txt)
  if e then esc_bad_ok = esc_bad_ok + 1 end
  print("非法 " .. txt .. " → " .. (e or "竟然通过了"))
end
local ctrl = '"a' .. string.char(1) .. 'b"'
local _, e_ctrl = J.decode(ctrl)
print("裸控制字符 → " .. (e_ctrl or "竟然通过了"))
kv("esc_bad_ok", esc_bad_ok .. "/" .. #esc_bad)
kv("esc_ctrl_err", e_ctrl or "")
check("八种转义长度正确", s ~= nil and #s == 12)
check("\\/ 解码为 /", s ~= nil and sub(s, 6, 6) == "/")
check("非法转义全部拒绝", esc_bad_ok == #esc_bad)
check("裸控制字符被拒绝", e_ctrl ~= nil)
endsec()

-- 8. \uXXXX 与代理对
sec("unicode")
local u_cases = {
  { "BMP", [=["\u4e2d\u6587"]=] },
  { "合法代理对", [=["\ud83d\ude00"]=] },
  { "孤立高代理", [=["\ud83d"]=] },
  { "孤立低代理", [=["\ude00"]=] },
  { "高代理+普通字符", [=["\ud83dX"]=] },
}
for _, u in ipairs(u_cases) do
  local v, e = J.decode(u[2])
  if e then
    print(fmt("%-14s → 错误 %s", u[1], e))
  else
    print(fmt("%-14s %-10s 字节=%s len=%d", u[1], v, J.bytes_hex(v), #v))
  end
end
local cn = J.decode([=["\u4e2d\u6587"]=])
local emoji = J.decode([=["\ud83d\ude00"]=])
local lone = J.decode([=["\ud83d"]=])
local mixed = J.decode([=["\ud83dX"]=])
kv("u_cn_hex", J.bytes_hex(cn))
kv("u_emoji_hex", J.bytes_hex(emoji))
kv("u_lone_hex", J.bytes_hex(lone))
kv("u_mixed_hex", J.bytes_hex(mixed))
local _, e_short = J.decode([=["\u12"]=])
kv("u_short_err", e_short or "")
check("\\u4e2d\\u6587 编码为 UTF-8", J.bytes_hex(cn) == "e4b8ade69687")
check("代理对合成 U+1F600", J.bytes_hex(emoji) == "f09f9880")
check("孤立高代理输出 U+FFFD", J.bytes_hex(lone) == "efbfbd")
check("高代理+普通字符保持后续字符", J.bytes_hex(mixed) == "efbfbd58")
check("\\u 长度不足被拒绝", e_short ~= nil)
endsec()

-- 9. 对象键去重
sec("dedupe")
local d = J.decode([=[{"a":1,"b":2,"a":3}]=])
local nkeys = 0
for _ in pairs(d) do nkeys = nkeys + 1 end
print('{"a":1,"b":2,"a":3} → a=' .. show_num(d.a) .. " b=" .. show_num(d.b))
print("key 数量 " .. nkeys)
local d2 = J.decode([=[{"k":{"x":1},"k":{"y":2}}]=])
print("重复的嵌套对象 → k.x=" .. tostring(d2.k.x) .. " k.y=" .. show_num(d2.k.y))
local d3 = J.decode([=[{"1":1,"01":2}]=])
local n3 = 0
for _ in pairs(d3) do n3 = n3 + 1 end
print('"1" 与 "01" 是不同键，key 数 ' .. n3)
kv("dedupe_a", show_num(d.a))
kv("dedupe_b", show_num(d.b))
kv("dedupe_count", nkeys)
kv("dedupe_nested_x", d2.k.x == nil and "nil（被覆盖）" or "存在")
kv("dedupe_nested_y", show_num(d2.k.y))
kv("dedupe_numeric_keys", n3)
check("重复键后者覆盖", d.a == 3 and d.b == 2 and nkeys == 2)
check("嵌套对象同样后者覆盖", d2.k.x == nil and d2.k.y == 2)
endsec()

-- 10. 序列化
sec("serializer")
local function show_enc(label, v)
  local s, e = J.encode(v)
  print(label .. " → " .. (e and ("错误：" .. e) or s))
end
show_enc("数组 {1,2,3}", { 1, 2, 3 })
show_enc("对象", { name = "lua", ok = true, none = J.null })
show_enc("空表", {})
show_enc("浮点 1.0", 1.0)
show_enc("整数 1", 1)
show_enc("inf", math.huge)
show_enc("nan", 0 / 0)
local cyc = {}
cyc.self = cyc
show_enc("循环引用", cyc)
show_enc("非字符串键", { [1] = "x", [3] = "y" })
local arr_enc = J.encode({ 1, 2, 3 })
local obj_enc = J.encode({ name = "lua", ok = true, none = J.null })
kv("s_array", arr_enc or "err")
kv("s_obj", obj_enc or "err")
kv("s_empty", J.encode({}) or "err")
local _, e_inf = J.encode(math.huge)
local _, e_nan = J.encode(0 / 0)
local _, e_cyc = J.encode(cyc)
local _, e_key = J.encode({ [1] = "x", [3] = "y" })
kv("s_inf_err", e_inf or "")
kv("s_nan_err", e_nan or "")
kv("s_cycle_err", e_cyc or "")
kv("s_key_err", e_key or "")
check("数组序列化", arr_enc ~= nil and sub(arr_enc, 1, 1) == "[")
check("对象键排序稳定", obj_enc == '{"name":"lua","none":null,"ok":true}')
check("inf / nan 拒绝回写", e_inf ~= nil and e_nan ~= nil)
check("循环引用被拦截", e_cyc ~= nil)
check("非字符串键被拦截", e_key ~= nil)
endsec()

-- 11. 结构错误
sec("errors")
local errs = {
  { "[1,]", "数组尾逗号" },
  { '{"a":1,}', "对象尾逗号" },
  { '{"a" 1}', "缺冒号" },
  { "1 2", "尾部多余" },
  { "", "空输入" },
  { '{"a":}', "缺值" },
  { "[1 2]", "缺逗号" },
  { '"未闭合', "字符串未闭合" },
}
local err_ok = 0
for _, c in ipairs(errs) do
  local v, e = J.decode(c[1])
  if e then err_ok = err_ok + 1 end
  print(fmt("%-10s %-14s → %s", c[2], "[" .. c[1] .. "]", e or "竟然通过了"))
end
kv("struct_err", err_ok .. "/" .. #errs)
check("结构错误全部拒绝", err_ok == #errs)
endsec()

-- 12. 往返示例
sec("roundtrip")
local tree = {
  name = "lua",
  nums = { 1, 2.5, -3 },
  ok = true,
  none = J.null,
  nested = { ["中文键"] = "值", list = { J.null, false } },
}
local text = J.encode(tree)
local back, berr = J.decode(text)
print("编码：" .. tostring(text))
print("再解析：" .. (berr or "成功"))
print("深度相等：" .. tostring(not berr and J.deep_equal(tree, back)))
kv("sample_roundtrip", (not berr and J.deep_equal(tree, back)) and "yes" or "no")
kv("sample_text", tostring(text))
kv("sample_digest", J.digest(back))
check("固定样本往返深度相等", not berr and J.deep_equal(tree, back))
endsec()

-- 汇总
sec("selfcheck")
print(fmt("SELF-CHECK %d/%d", passed, total))
kv("selfcheck", passed .. "/" .. total)
kv("selfcheck_total", total)
endsec()
