-- runtime_probe.lua —— 同一份文件在五端各自打印自己那份语义。
-- 刻意不含任何只有新版本才有的语法：位运算符、整除一律在运行时用 load 试探，
-- 所以这份文件本身在 5.1 上也能编译通过。

local loader = loadstring or load      -- 5.1 的 load 只吃函数，字符串要用 loadstring

local function show(v) return tostring(v) end

-- 试探某段源码在当前解释器上能不能编译并运行（编译失败 = 这个语法不存在，
-- 运行失败就把它自己的报错原文打出来，那正是我们要的证据）
local function try(src)
  local f, err = loader(src)
  if not f then return "不支持" end
  local ok, v = pcall(f)
  if not ok then
    local e = tostring(v)
    return "运行报错：" .. (e:match("]:?%d*:?%s*(.*)$") or e)
  end
  return show(v)
end

-- 把一个数打成「它真实的十进制」：5.3+ 的整数必须用 %d，用 %.0f 会先降级成 double
local function exact(n)
  if math.type and math.type(n) == "integer" then
    return string.format("%d", n)
  end
  return string.format("%.0f", n)
end

print(":: 语言与库")
print(string.format("  _VERSION            %s", _VERSION))
print(string.format("  bit32 库            %s", type(bit32)))
print(string.format("  utf8 库             %s", type(utf8)))
print(string.format("  load 吃字符串        %s", try('return type(load("return 1"))')))
print(string.format("  位运算符 6 & 3      %s", try("return 6 & 3")))
print(string.format("  位运算符 1 << 4     %s", try("return 1 << 4")))
print(string.format("  整除 7 // 2         %s", try("return 7 // 2")))
print(string.format("  math.type(3)        %s",
  math.type and show(math.type(3)) or "没有 math.type（number 不分整数浮点）"))

print(":: 整数到底几位（决定哈希能不能信这一端）")
print(string.format("  0xFFFFFFFF          %s", exact(0xFFFFFFFF)))
print(string.format("  0xFFFFFFFF+1        %s", exact(0xFFFFFFFF + 1)))
print(string.format("  0x7FFFFFFFFFFFFFFF  %s", try("return 0x7FFFFFFFFFFFFFFF")))
print(string.format("  2^32 当表索引        %s",
  show(pcall(function() local t = {}; t[4294967296] = 1; return t[4294967296] end))))

print(":: 精度（5.1/5.2 最要命的一条）")
local prod = 4294967295 * 16777619          -- FNV 最坏情况的一次乘法，积约 2^56
print(string.format("  乘积（按类型打准）   %s", exact(prod)))
print(string.format("  乘积（用 %%.0f 打）    %s  ← 5.3+ 用这个也会被改坏",
  string.format("%.0f", prod)))
print(string.format("  与 Python 精确值一致 %s（精确值 72059324892970605）",
  tostring(exact(prod) == "72059324892970605")))
print(string.format("  用 == 比字面量       %s  ← 字面量同样被舍入，判不出精度",
  tostring(prod == 72059324892970605)))
print(string.format("  2^53+2 与 2^53+1     %s %s",
  string.format("%.0f", 2^53 + 2), string.format("%.0f", 2^53 + 1)))

print(":: 取模与除法（位运算层全靠它）")
print(string.format("  -7 %% 3               %s", show(-7 % 3)))
print(string.format("  7 %% -3               %s", show(7 % -3)))
print(string.format("  math.floor(-7/3)     %s", show(math.floor(-7 / 3))))
print(string.format("  4294967295 %% 4096     %s", exact(4294967295 % 4096)))

print(":: 同一次乘法，模数怎么写（哈希最容易踩的一刀）")
-- 整段用 load 包起来再 pcall：int32 的平台连模数都能算成 0，
-- 这里要的是「它到底怎么坏的」，不是让整个探针脚本挂掉。
local function mod(gist)
  local f = loader("local prod = 0xFFFFFFFF * 16777619 return prod " .. gist)
  if not f then return "编译不过" end
  local ok, r = pcall(f)
  if not ok then
    local err = tostring(r)
    return "报错：" .. (err:match("]:?%d*:?%s*(.*)$") or err)
  end
  return exact(r)
end
print(string.format("  %-20s %s  ← 2^32 算出来永远是浮点", "% 2^32", mod("% 2^32")))
print(string.format("  %-20s %s  ← 连乘出来的模数", "% (65536*65536)", mod("% (65536*65536)")))
print(string.format("  %-20s %s  ← 写成字面量", "% 4294967296", mod("% 4294967296")))
print(string.format("  %-20s %s  ← 位运算符（5.3+）", "& 0xFFFFFFFF", mod("& 0xFFFFFFFF")))
print("  真值（Python 精确算）  4278189677 = 0xfefffe6d")
print(string.format("  math.type(2^32)        %s", math.type and show(math.type(2 ^ 32)) or "没有 math.type"))
print(string.format("  math.type(65536*65536) %s", math.type and show(math.type(65536 * 65536)) or "没有 math.type"))

print(":: bit32 到底给了哪些函数")
if type(bit32) == "table" then
  local names = { "band", "bor", "bxor", "bnot", "lshift", "rshift", "lrotate", "rol", "extract", "tobit" }
  local have, miss = {}, {}
  for _, k in ipairs(names) do
    if type(bit32[k]) == "function" then have[#have + 1] = k else miss[#miss + 1] = k end
  end
  print("  有: " .. table.concat(have, " "))
  print("  无: " .. table.concat(miss, " ") .. "  ← rol 是 LuaJIT 的 bit.rol，bit32 叫 lrotate")
else
  print("  这台没有 bit32 —— 上面 _VERSION 那一行说了算（实测只有 5.2 / 5.3 两端带）")
end

print(":: 这台有没有现成的哈希（把全局表找一遍）")
local cands = { "bit", "bit32", "crypt", "crypto", "digest", "md5", "sha1", "sha256",
                "hmac", "crc32", "openssl", "ssl", "lzma" }
local have = {}
for _, k in ipairs(cands) do
  if rawget(_G, k) then have[#have + 1] = k .. "(" .. type(rawget(_G, k)) .. ")" end
end
print("  试过的名字      " .. table.concat(cands, " "))
print("  这台真有的      " .. (next(have) and table.concat(have, " ") or "一个都没有"))
local hits, total = {}, 0
for k in pairs(_G) do
  total = total + 1
  local s = tostring(k):lower()
  if s:find("md5") or s:find("sha") or s:find("crc") or s:find("hash") then
    hits[#hits + 1] = tostring(k)
  end
end
table.sort(hits)
print(string.format("  全表 %d 项，带 md5/sha/crc/hash 的 %d 个：%s",
  total, #hits, next(hits) and table.concat(hits, " ") or "（空）"))

print(":: 十六进制输出（哈希最后一步要用）")
local function hex(fmt, n)
  local ok, r = pcall(string.format, fmt, n)
  return ok and r or ("报错: " .. tostring(r))
end
print(string.format("  %%08x of 0xFFFFFFFF   %s", hex("%08x", 4294967295)))
print(string.format("  %%08x of 2^31         %s", hex("%08x", 2147483648)))
print(string.format("  %%08x of 0            %s", hex("%08x", 0)))
print(string.format("  string.byte('\\255')   %s", show(string.byte("\255"))))
