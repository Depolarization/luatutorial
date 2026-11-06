--=====================================================================
-- t0_selftest.lua
-- 公共库自检闸门：u64 已知答案 / splitmix64 已知答案 / xoshiro 已知答案 /
-- 同种子确定性 / 全零状态 / 向量文件载入。任何一项 FAIL 都不该上画面。
-- 已知答案全部来自 tools/gen_ref.py（官方 C 参考实现的 Python 逐行翻译）。
--=====================================================================
local K = require("prngkit")
local u = K.u64
local V, verr = K.loadvectors()

local jit_on = type(jit) == "table"
print("VERSION\t" .. (jit_on and ("LuaJIT " .. jit.version) or _VERSION) ..
      "\tLUAJIT\t" .. tostring(jit_on))
print("K7 bit32来源\t" .. K.bit32mode)
print("K6 向量载入\t" .. (V and ("raw=" .. #V.raw .. " luarandom=" .. #V.luarandom ..
      " luarandom2=" .. #V.luarandom2) or ("失败:" .. tostring(verr))))

local pass, fail, spass, sfail, fails = 0, 0, 0, 0, {}

local function check(tag, got, want)
  if got == want then
    pass, spass = pass + 1, spass + 1
  else
    fail, sfail = fail + 1, sfail + 1
    fails[#fails + 1] = tag .. " got " .. tostring(got) .. " 期望 " .. tostring(want)
  end
end

local function endsec(tag)
  print(tag .. "\t" .. spass .. "/" .. (spass + sfail))
  spass, sfail = 0, 0
end

-- 1. u64 已知答案（add/mul/bxor/shl/shr/rotl，大数走十进制字符串）
if V then
  for _, c in ipairs(V.u64kat) do
    local op, a, b, k, want = c[1], c[2], c[3], c[4], c[5]
    local x, y, kk = u.fromString(a), u.fromString(b), tonumber(k)
    local got
    if op == "add" then got = u.add(x, y)
    elseif op == "mul" then got = u.mul(x, y)
    elseif op == "bxor" then got = u.bxor(x, y)
    elseif op == "shl" then got = u.shl(x, kk)
    elseif op == "shr" then got = u.shr(x, kk)
    else got = u.rotl(x, kk) end
    check(op, u.hex(got), u.hex(u.fromString(want)))
  end
end
endsec("K1 u64已知答案")

-- 2. splitmix64(42) 前 3 个输出
if V then
  local g = K.splitmix64.new(42)
  local h = {}
  for i = 1, 3 do
    local z = g:next()
    h[i] = u.hex(z)
    check("splitmix#" .. i, h[i], u.hex(u.fromString(V.smkat[i])))
  end
  print("KX splitmix64(42)前三\t" .. table.concat(h, "\t"))
end
endsec("K2 splitmix64已知答案")

-- 3. 反面教材 + 已知答案：状态 {1,2,3,4} 的前 3 个输出（首个只有 11520）
if V then
  local g = K.xoshiro256.naiveSeed(1)
  local h, d = {}, {}
  for i = 1, 3 do
    local z = g:draw()
    h[i] = u.hex(z)
    d[i] = u.hex(z)
    check("xoNaive#" .. i, h[i], u.hex(u.fromString(V.xokat[i])))
  end
  print("KX 状态{1,2,3,4}首三\t" .. table.concat(h, "\t"))
end
endsec("K3 naive状态已知答案")

-- 4. 同种子确定性：两个实例各抽 16 个，逐位相同
do
  local ga = K.xoshiro256.fromSeed(20260213)
  local gb = K.xoshiro256.fromSeed(20260213)
  local same = 0
  for _ = 1, 16 do
    if u.eq(ga:draw(), gb:draw()) then same = same + 1 end
  end
  check("同种子同序列", same, 16)
end
endsec("K4 同种子确定性")

-- 5. 全零状态：** 唯一的坏状态，输出恒 0
do
  local z = u.fromNumber(0)
  local g = K.xoshiro256.fromState({ z, z, z, z })
  local zeros = 0
  for _ = 1, 5 do
    local r = g:draw()
    if r.hi == 0 and r.lo == 0 then zeros = zeros + 1 end
  end
  check("全零状态恒零", zeros, 5)
end
endsec("K5 全零状态")

-- 6. splitmix 播种后的状态与首输出对上主向量（把 KAT 和 1000 值连起来）
if V then
  local g = K.xoshiro256.fromSeed(V.seed)
  check("主向量首输出", u.hex(g:draw()), u.hex(u.fromString(V.raw[1])))
end
endsec("K8 主向量首输出")

print("SELF-CHECK\t" .. pass .. "/" .. (pass + fail))
for i = 1, math.min(#fails, 3) do print("FAILDETAIL\t" .. fails[i]) end
if fail == 0 then print("结论\t公共库五项自检全过，对拍才作数") end
