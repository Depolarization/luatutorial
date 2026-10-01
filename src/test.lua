-- test.lua : 拿 Python 大整数算好的标准答案，逐条对照
local I = require("int64")
local V = require("vectors")

local ops = {
  add = I.add, sub = I.sub, mul = I.mul, div = I.div, mod = I.mod,
  band = I.band, bor = I.bor, bxor = I.bxor, shl = I.shl, shr = I.shr,
}

local pass, fail = 0, 0
for _, c in ipairs(V) do
  local op, xs, ys, want = c[1], c[2], c[3], c[4]
  local a = I.fromString(xs)
  local b = (op == "shl" or op == "shr") and tonumber(ys) or I.fromString(ys)
  local got = I.tostring(ops[op](a, b))
  if got == want then
    pass = pass + 1
  else
    fail = fail + 1
    if fail <= 3 then print("FAIL", op, xs, ys, "got", got, "want", want) end
  end
end
print(string.format("自检：%d 条用例，通过 %d，失败 %d", pass + fail, pass, fail))
if fail == 0 then print("结论：与 Python 大整数结果完全一致") end
