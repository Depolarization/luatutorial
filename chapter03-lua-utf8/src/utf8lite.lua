--[[
  utf8lite.lua —— 纯 Lua 的 UTF-8 处理库

  目标环境：Lua 5.1 / 5.2 —— 那里没有 utf8 标准库，也不能假设有 bit32。
  API 与 Lua 5.3+ 的标准库 utf8 同名同签名，所以可以一行接通两个版本：

      utf8 = utf8 or require("utf8lite")   -- 5.1/5.2 补上，5.3+ 用原生的

  语义基准：官方 C 实现 src/lutf8lib.c（Lua 5.4）。位运算一律写成乘除取模，
  所有中间值都小于 2^31，只有 double 的 5.1 也能算准。
]]

local byte   = string.byte
local char   = string.char
local concat = table.concat
local error  = error
local floor  = math.floor
local sub    = string.sub
local type   = type
local unpack = table.unpack or unpack      -- 5.1 叫 unpack

local U = {}

local MAXUNICODE = 0x10FFFF      -- Unicode 的天花板
local MAXUTF     = 0x7FFFFFFF    -- 宽松模式允许解到的最大值（官方 C 里的上限）

--[[
  首字节 → 这个字符占几个字节。UTF-8 的全部规则就在这一段：
  首字节有几个连续的前导 1，字符就有几个字节；续字节固定是 10xxxxxx。

    0xxxxxxx → 1      1110xxxx → 3      111110xx → 5（非法编码形式）
    110xxxxx → 2      11110xxx → 4      1111110x → 6（同上）
    10xxxxxx → 0      落单的续字节，不能当首字节
    1111111x → 0      FE / FF 在 UTF-8 里永远非法
]]
local LEAD = {}
for b = 0, 255 do
  if     b < 0x80 then LEAD[b] = 1
  elseif b < 0xC0 then LEAD[b] = 0
  elseif b < 0xE0 then LEAD[b] = 2
  elseif b < 0xF0 then LEAD[b] = 3
  elseif b < 0xF8 then LEAD[b] = 4
  elseif b < 0xFC then LEAD[b] = 5
  elseif b < 0xFE then LEAD[b] = 6
  else                 LEAD[b] = 0
  end
end

-- 首字节里被前导 1 占掉的值，减掉它，剩下的才是数据位
local PREFIX = { [1] = 0x00, [2] = 0xC0, [3] = 0xE0,
                 [4] = 0xF0, [5] = 0xF8, [6] = 0xFC }

-- n 个字节所能表示的最小码点；解出来比它还小就是 overlong（超长编码）
-- 例：0xC0 0x80 也“能”解出 0，但 U+0000 必须写成单字节 0x00
local MIN_CP = { [1] = 0, [2] = 0x80, [3] = 0x800,
                 [4] = 0x10000, [5] = 0x200000, [6] = 0x4000000 }

local function iscont(b)
  return b ~= nil and b >= 0x80 and b < 0xC0
end

-- 相对位置：负数表示从末尾往前数（对齐 C 里的 u_posrelat）
local function posrelat(pos, len)
  if pos >= 0 then return pos
  elseif -pos > len then return 0
  else return len + pos + 1 end
end

--[[
  核心解码：从第 i 个字节解出一个字符
      成功 → 码点 cp, 下一个字符的起始下标
      失败 → nil
  strict 为 false 时（官方叫 lax 模式）允许代理区和大码点，只校验结构。
]]
local function decode(s, i, strict)
  local b1 = byte(s, i)
  if b1 == nil then return nil end
  if b1 < 0x80 then return b1, i + 1 end      -- ASCII：字节值就是码点

  local n = LEAD[b1]
  if n == 0 then return nil end

  local cp = b1 - PREFIX[n]                   -- 首字节贡献的高位
  for k = 1, n - 1 do                         -- 再吃掉 n-1 个续字节
    local cc = byte(s, i + k)
    if not iscont(cc) then return nil end     -- 续字节缺失或串到了结尾
    cp = cp * 0x40 + (cc - 0x80)              -- 每个续字节贡献 6 位
  end

  if cp > MAXUTF or cp < MIN_CP[n] then return nil end
  if strict then
    if cp > MAXUNICODE then return nil end
    if cp >= 0xD800 and cp <= 0xDFFF then return nil end   -- 代理区不合法
  end
  return cp, i + n
end

-- 编码方向：码点 → 字节数组（从低 6 位往回填，最后补上首字节的前缀）
local function encode_bytes(cp)
  local n = (cp < 0x80 and 1) or (cp < 0x800 and 2) or (cp < 0x10000 and 3)
         or (cp < 0x200000 and 4) or (cp < 0x4000000 and 5) or 6
  local out, rest = {}, cp
  for k = n, 2, -1 do
    out[k] = 0x80 + rest % 0x40
    rest = floor(rest / 0x40)
  end
  out[1] = PREFIX[n] + rest
  return out
end

-- ==================== 与标准库同名同签名 ====================

-- utf8.len(s [, i [, j [, lax]]]) → 起始字节落在 [i, j] 内的字符个数
-- 不合法时不报错，返回 nil 和出错序列的起始位置
function U.len(s, i, j, lax)
  local l = #s
  local posi, posj = posrelat(i or 1, l), posrelat(j or -1, l)
  if posi < 1 or posi - 1 > l then error("initial position out of bounds", 2) end
  if posj > l then error("final position out of bounds", 2) end
  local n = 0
  while posi <= posj do
    local cp, nxt = decode(s, posi, not lax)
    if cp == nil then return nil, posi end
    posi = nxt
    n = n + 1
  end
  return n
end

-- utf8.codepoint(s [, i [, j [, lax]]]) → 区间内各字符的码点
-- 坑：j 的默认值是 i，不是串尾 —— utf8.codepoint(s) 只给你第一个字符
function U.codepoint(s, i, j, lax)
  local l = #s
  local posi, pose = posrelat(i or 1, l), posrelat(j or i or 1, l)
  if posi < 1 then error("bad argument #2 to 'codepoint' (out of bounds)", 2) end
  if pose > l then error("bad argument #3 to 'codepoint' (out of bounds)", 2) end
  if posi > pose then return end              -- 空区间：一个值都不返回
  local out, pos = {}, posi
  while pos <= pose do
    local cp, nxt = decode(s, pos, not lax)
    if cp == nil then error("invalid UTF-8 code", 2) end
    out[#out + 1] = cp
    pos = nxt
  end
  return unpack(out)
end

-- utf8.char(...) → 若干码点拼成字符串
function U.char(...)
  local args, n = { ... }, select("#", ...)
  local bytes = {}
  for k = 1, n do
    local cp = args[k]
    if type(cp) ~= "number" then
      error("bad argument #" .. k .. " to 'char' (number expected)", 2)
    end
    if cp < 0 or cp > MAXUTF then
      error("bad argument #" .. k .. " to 'char' (value out of range)", 2)
    end
    -- 注意：官方只挡到 0x7FFFFFFF，所以 char(0x110000) 会「成功」，
    -- 产出的却是 5/6 字节的非标准 UTF-8（utf8.len 自己都不认）。这里照抄官方，
    -- 保持和原生 utf8 逐字节一致；要挡住在外面自己判 cp <= 0x10FFFF。
    local b = encode_bytes(cp)
    for t = 1, #b do bytes[#bytes + 1] = b[t] end
  end
  if #bytes == 0 then return "" end
  return char(unpack(bytes))
end

-- utf8.offset(s, n [, i]) → 从 i 起算第 n 个字符的起始字节位置
-- n = 0 表示「i 所在的那个字符从哪开始」；负数往回数；找不到返回 nil
function U.offset(s, n, i)
  local l = #s
  local p = posrelat(i or (n >= 0 and 1 or l + 1), l)
  if p < 1 or p - 1 > l then error("position out of bounds", 2) end
  if n == 0 then
    while p > 1 and iscont(byte(s, p)) do p = p - 1 end
  else
    if iscont(byte(s, p)) then
      error("initial position is a continuation byte", 2)   -- 注意是直接报错
    end
    if n < 0 then
      while n < 0 and p > 1 do
        repeat p = p - 1 until p == 1 or not iscont(byte(s, p))
        n = n + 1
      end
    else
      n = n - 1                               -- 第 1 个字符就在原地
      while n > 0 and p <= l do
        repeat p = p + 1 until byte(s, p) == nil or not iscont(byte(s, p))
        n = n - 1
      end
    end
  end
  if n == 0 then return p end
  return nil
end

-- 与标准库一致的「一个字符」字节模式；上界取 0xFD 而不是 0xF4，
-- 好让 5 字节这类畸形序列先被匹配上，再交给 len / codepoint 去判错。
--
-- 这里有个能把人逼疯的坑：官方 charpattern 写作 "[\0-\127...]"，里面是一个
-- 货真价实的 0 字节。5.1 的模式引擎按 C 字符串处理，遇到它就断，直接
--   malformed pattern (missing ']')
-- 而 %z 在 5.1 到 5.4 都表示「零字节」（5.4 源码 lstrlib.c 里标着 deprecated，
-- 但一直管用），所以换成 %z 写法，一个模式通吃所有版本。
U.charpattern = "[%z\1-\127\194-\253][\128-\191]*"

-- ==================== 标准库没有、实战一定用得上的 ====================

-- 暴露核心解码，写上界/校验类逻辑时不用重复造轮子
U.decode = decode

-- for pos, cp in utf8.codes(s) do ... end
function U.codes(s)
  local pos = 1
  return function()
    if pos > #s then return nil end
    local cp, nxt = decode(s, pos, true)
    if cp == nil then error("invalid UTF-8 code", 2) end
    local at = pos
    pos = nxt
    return at, cp
  end
end

-- 第 n 个字符本身（不是码点），越界返回 nil
function U.nth(s, n)
  local p = U.offset(s, n)
  if p == nil then return nil end
  local cp, nxt = decode(s, p, true)
  if cp == nil then return nil end
  return sub(s, p, nxt - 1)
end

-- 按「字符」下标切片。string.sub 只会按字节切，切在字符中间就是半个字 → 乱码
function U.sub(s, i, j)
  local n = U.len(s)
  if not n then error("invalid UTF-8 code", 2) end
  if n == 0 then return "" end
  i = posrelat(i or 1, n)
  j = posrelat(j or -1, n)
  if i > j then return "" end
  local first = U.offset(s, i)
  if first == nil then return "" end
  local after = U.offset(s, j + 1)            -- 第 j 个字符之后的字节位置
  return sub(s, first, (after or #s + 1) - 1)
end

function U.reverse(s)
  local parts, k, pos = {}, 0, 1
  while pos <= #s do
    local cp, nxt = decode(s, pos, true)
    if cp == nil then error("invalid UTF-8 code", 2) end
    k = k + 1
    parts[k] = sub(s, pos, nxt - 1)
    pos = nxt
  end
  local rev = {}
  for t = 1, k do rev[t] = parts[k - t + 1] end
  return concat(rev)
end

-- 安全截断：字节数不超过 maxBytes，但绝不切出半个字符
-- 聊天框限宽、定长协议字段全靠它
function U.fit(s, maxBytes)
  local pos, keep = 1, 0
  while pos <= #s do
    local cp, nxt = decode(s, pos, true)
    if cp == nil then break end
    if nxt - 1 > maxBytes then break end       -- 这个字符放不下，停在上一处
    keep = nxt - 1
    pos = nxt
  end
  return sub(s, 1, keep), keep
end

-- 校验并给出原因：true | false, 出错位置, 原因
function U.check(s)
  local pos, l = 1, #s
  while pos <= l do
    local cp, nxt = decode(s, pos, true)
    if cp == nil then
      local b1 = byte(s, pos)
      if iscont(b1) then return false, pos, "落单的续字节" end
      local n = LEAD[b1]
      if n == 0 then return false, pos, "非法首字节" end
      for k = 1, n - 1 do
        if not iscont(byte(s, pos + k)) then return false, pos, "续字节不够" end
      end
      local v = b1 - PREFIX[n]
      for k = 1, n - 1 do v = v * 0x40 + (byte(s, pos + k) - 0x80) end
      if v < MIN_CP[n] then return false, pos, "超长编码 overlong" end
      if v > MAXUNICODE then return false, pos, "码点超出 U+10FFFF" end
      if v >= 0xD800 and v <= 0xDFFF then return false, pos, "代理区码点" end
      return false, pos, "不合法"
    end
    pos = nxt
  end
  return true
end

-- 打印友好：ASCII 原样，合法字符转成 \u{XXXX}，非法字节转成 \{NN}
-- 故意做成「-total-」的：调试时喂进去的串往往正是坏掉的，不能反过来报错
function U.escape(s)
  local out, pos = {}, 1
  while pos <= #s do
    local cp, nxt = decode(s, pos, true)
    if cp == nil then
      out[#out + 1] = string.format("\\{%02X}", byte(s, pos))
      pos = pos + 1
    else
      if cp < 0x20 or cp == 0x7F then out[#out + 1] = string.format("\\%d", cp)
      elseif cp < 0x80 then out[#out + 1] = sub(s, pos, pos)
      else out[#out + 1] = string.format("\\u{%X}", cp) end
      pos = nxt
    end
  end
  return concat(out)
end

return U
