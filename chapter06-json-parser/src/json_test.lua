-- json_test.lua — 随机 JSON 树回归：生成 → 序列化 → 再解析 → 深度相等。
-- 同时把样本写成 TSV，交给 tools/json_crosscheck.py 与 Python json 对拍。
local J = require("jsonkit")

local fmt, concat = string.format, table.concat
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
local function sec(name) print("[SECTION] " .. name) end
local function endsec() print("[/SECTION]") end
local function kv(k, v) print("@K\t" .. k .. "\t" .. tostring(v)) end

-- [snip:lcg]
-- 固定种子 + Park-Miller 生成器：只做 31 位乘法，
-- 中间结果 < 2^53，五家解释器拿到的序列完全一样。
local SEED = 20261025
local state = SEED
local function rnd(m)
  state = (state * 16807) % 2147483647
  return state % m + 1
end
-- [/snip]

local KEYS = {
  "a", "b", "name", "id", "x", "y", "中文键", "slash/key",
  'quote"key', "back\\key", "tab\tkey", "空", "k1", "k2", "k3",
}
local STRS = {
  "", "lua", "中文", "line\nbreak", 'quote"and\\slash', "tab\there",
  "emoji 😀", "ctrl\1", "/slash/", "5.3", "null", "true",
}

local function rand_num()
  local k = rnd(6)
  if k == 1 then return rnd(2000) - 1001 end
  if k == 2 then return (rnd(20001) - 10000) / 8 end
  if k == 3 then return rnd(1000) * 1024 end
  if k == 4 then return (rnd(101) - 50) * 0.25 end
  if k == 5 then return (rnd(10000) - 5000) / 1000 end
  return rnd(100000) - 50000
end

-- [snip:gen]
local function gen(depth)
  local r = rnd(10)
  if depth <= 0 or r <= 4 then
    local k = rnd(4)
    if k == 1 then return STRS[rnd(#STRS)]
    elseif k == 2 then return rand_num()
    elseif k == 3 then return (rnd(2) == 1)
    else return J.null end
  elseif r <= 7 then
    local n = rnd(3)
    local arr = {}
    for i = 1, n do arr[i] = gen(depth - 1) end
    return arr
  end
  local obj, used = {}, {}
  local n, guard = rnd(3), 0
  while n > 0 and guard < 20 do
    guard = guard + 1
    local key = KEYS[rnd(#KEYS)]
    if not used[key] then
      used[key] = true
      obj[key] = gen(depth - 1)
      n = n - 1
    end
  end
  return obj
end
-- [/snip]

local function write_file(path, text)
  local f, e = io.open(path, "w")
  if not f then return false, e end
  f:write(text)
  f:close()
  return true
end

-- 1. 随机往返
sec("roundtrip")
local N = 200
local cases, ok_n = {}, 0
for i = 1, N do
  local tree = gen(4)
  local text, enc_err = J.encode(tree)
  local ok, back, err = false, nil, enc_err
  if text then
    back, err = J.decode(text)
    ok = (not err) and J.deep_equal(tree, back)
  end
  if ok then ok_n = ok_n + 1 end
  local dig = "ERR"
  if back ~= nil then dig = J.digest(back) end
  cases[i] = { id = i, text = text or "", digest = dig, ok = ok, err = err }
end
print(fmt("种子 %d，生成 %d 棵随机 JSON 树（深度≤4）", SEED, N))
print(fmt("序列化 → 再解析 → 深度相等：%d/%d", ok_n, N))
local sample = J.encode({ name = "lua", nums = { 1, 2.5, -3 },
                          ok = true, none = J.null })
print("固定样例：" .. sample)
kv("roundtrip_ok", ok_n)
kv("roundtrip_total", N)
kv("random_total", N)
kv("sample_case", sample)
check("200 棵随机树往返深度相等", ok_n == N, ok_n .. "/" .. N)

-- 2. 写对拍样本
local random_lines = {}
for _, c in ipairs(cases) do
  random_lines[#random_lines + 1] = c.id .. "\t" .. c.digest .. "\t" .. c.text .. "\n"
end
local ok1, e1 = write_file("out/cases/random_cases.tsv", concat(random_lines))

local fixed = {
  { id = "f1", kind = "dedupe", json = [=[{"a":1,"b":2,"a":3}]=] },
  { id = "f2", kind = "escapes", json = [=["a\"b\\c\/d\b\f\n\r\t"]=] },
  { id = "f3", kind = "unicode", json = [=["\u4e2d\u6587\ud83d\ude00"]=] },
  { id = "f4", kind = "literals", json = "[true,false,null]" },
}
local fixed_ok, fixed_lines = 0, {}
for _, c in ipairs(fixed) do
  local v, e = J.decode(c.json)
  if v ~= nil and not e then fixed_ok = fixed_ok + 1 end
  fixed_lines[#fixed_lines + 1] =
    c.id .. "\t" .. c.kind .. "\t" .. (v and J.digest(v) or "ERR") .. "\t" .. c.json .. "\n"
end
local ok2, e2 = write_file("out/cases/fixed_cases.tsv", concat(fixed_lines))

local boundary = {
  { id = "b1", kind = "double_overflow", json = "1e999" },
  { id = "b2", kind = "double_overflow", json = "-1e999" },
  { id = "b3", kind = "bigint_2p53", json = "9007199254740993" },
  { id = "b4", kind = "bigint_int64", json = "9223372036854775807" },
  { id = "b5", kind = "bigint_30", json = "123456789012345678901234567890" },
  { id = "b6", kind = "underflow", json = "1e-400" },
}
local boundary_lines = {}
for _, c in ipairs(boundary) do
  boundary_lines[#boundary_lines + 1] = c.id .. "\t" .. c.kind .. "\t" .. c.json .. "\n"
end
local ok3, e3 = write_file("out/cases/boundary_cases.tsv", concat(boundary_lines))

print("样本落盘：random_cases.tsv / fixed_cases.tsv / boundary_cases.tsv")
kv("fixed_ok", fixed_ok)
kv("fixed_total", #fixed)
kv("boundary_n", #boundary)
kv("cases_written", (ok1 and ok2 and ok3) and "yes" or "no")
check("固定样本可解析", fixed_ok == #fixed, fixed_ok .. "/" .. #fixed)
check("对拍样本落盘", ok1 and ok2 and ok3, tostring(e1 or e2 or e3 or "ok"))
endsec()

-- 3. 关键行为
sec("checks")
local d = J.decode([=[{"a":1,"b":2,"a":3}]=])
check("重复键后者覆盖", d.a == 3 and d.b == 2)
local esc = J.decode([=["a\"b\\c\/d\b\f\n\r\t"]=])
check("转义解码 12 字节", esc ~= nil and #esc == 12)
local emoji = J.decode([=["\ud83d\ude00"]=])
check("代理对合成 U+1F600", J.bytes_hex(emoji) == "f09f9880")
local lone = J.decode([=["\ud83d"]=])
check("非法代理对 U+FFFD", J.bytes_hex(lone) == "efbfbd")
local arr = J.decode("[null,true,false]")
check("null 哨兵不挖洞", #arr == 3)
local big = J.decode("9007199254740993")
check("2^53+1 可解析", big ~= nil)
local inf = J.decode("1e999")
check("1e999 溢出为 inf", inf == math.huge)
local ok_bad = J.decode("nullx") == nil and J.decode("01") == nil
check("前缀字面量/前导零被拒绝", ok_bad)
local _, e_inf = J.encode(math.huge)
local cyc = {}
cyc.self = cyc
local _, e_cyc = J.encode(cyc)
check("inf / 循环引用拒绝回写", e_inf ~= nil and e_cyc ~= nil)
if math.type then
  check("5.3+ integer 子类型回写一致",
        math.type(J.decode("1")) == "integer" and J.encode(J.decode("1")) == "1"
        and math.type(J.decode("1.0")) == "float" and J.encode(J.decode("1.0")) == "1.0")
else
  check("5.1/5.2 无子类型，double 回写补 .0",
        math.type == nil and J.encode(J.decode("1")) == "1.0")
end
local t = { a = 1, b = { true, J.null } }
check("digest 稳定", J.digest(t) == J.digest(J.decode(J.encode(t))))
endsec()

-- 4. 自检汇总
sec("selfcheck")
print(fmt("SELF-CHECK %d/%d", passed, total))
kv("selfcheck", passed .. "/" .. total)
kv("selfcheck_total", total)
endsec()
