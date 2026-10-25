-- jsonkit.lua — 纯 Lua 的 JSON 解析器：tokenizer → 递归下降 parser
-- 目标：Lua 5.1 / 5.2 / 5.3 / 5.4 / LuaJIT 2.1 五个解释器同一份源码。
local M = {}

M.VERSION = "1.0"
M.MAX_DEPTH = 200

-- [snip:null]
-- JSON 的 null 不能直接用 Lua 的 nil：
-- nil 一旦放进数组就会挖出一个洞，#arr 和遍历全都会失真。
-- 所以用一张唯一的小表当哨兵，decode/encode 两端都认它。
M.null = setmetatable({}, { __tostring = function() return "null" end })
-- [/snip]

local sub, find, byte, char = string.sub, string.find, string.byte, string.char
local concat, sort = table.concat, table.sort
local floor, huge = math.floor, math.huge
local fmt = string.format

local function is_digit(c)
  return c ~= "" and c >= "0" and c <= "9"
end

local function is_ws(c)
  return c == " " or c == "\t" or c == "\n" or c == "\r"
end

-- [snip:esc_map]
-- 规范只认这八种转义；其余 \x 一律报错。
local ESC = {
  ['"'] = '"', ["\\"] = "\\", ["/"] = "/",
  b = "\b", f = "\f", n = "\n", r = "\r", t = "\t",
}
-- [/snip]

-- [snip:utf8]
-- Lua 5.1 没有 utf8 库，\uXXXX 必须自己编成字节。
local function utf8_encode(cp)
  if cp < 0x80 then
    return char(cp)
  elseif cp < 0x800 then
    return char(0xC0 + floor(cp / 0x40), 0x80 + cp % 0x40)
  elseif cp < 0x10000 then
    return char(0xE0 + floor(cp / 0x1000),
                0x80 + floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
  else
    return char(0xF0 + floor(cp / 0x40000),
                0x80 + floor(cp / 0x1000) % 0x40,
                0x80 + floor(cp / 0x40) % 0x40,
                0x80 + cp % 0x40)
  end
end
-- [/snip]

-- [snip:tok_state]
-- 词法分析器只有三样状态：原文 text、游标 pos、输出 token 表。
-- JSON 的空白只有四种，别的控制字符不是空白。
function M.tokenize(text)
  if type(text) ~= "string" then return nil, "输入必须是字符串" end
  local n = #text
  local pos = 1
  local toks = {}
-- [/snip]

  local function hex4()
    if pos + 3 > n then return nil, "\\u 后需要 4 位十六进制" end
    local h = sub(text, pos, pos + 3)
    if find(h, "[^0-9a-fA-F]") then return nil, "\\u 后面不是十六进制" end
    pos = pos + 4
    return tonumber(h, 16)
  end

  local function read_string()
    pos = pos + 1
    local out = {}
    while pos <= n do
      local c = sub(text, pos, pos)
      if c == '"' then
        pos = pos + 1
        return concat(out)
      elseif c == "\\" then
        local e = sub(text, pos + 1, pos + 1)
        if ESC[e] then
          out[#out + 1] = ESC[e]
          pos = pos + 2
        elseif e == "u" then
          pos = pos + 2
          local cp, err = hex4()
          if not cp then return nil, err end
          -- [snip:surrogate]
          -- 高代理 D800-DBFF 必须紧跟低代理 DC00-DFFF。
          -- 合法组合拼成完整码点；非法组合统一落到 U+FFFD。
          if cp >= 0xD800 and cp <= 0xDBFF then
            local ok = false
            if sub(text, pos, pos + 1) == "\\u" then
              local h2 = sub(text, pos + 2, pos + 5)
              if #h2 == 4 and not find(h2, "[^0-9a-fA-F]") then
                local lo = tonumber(h2, 16)
                if lo >= 0xDC00 and lo <= 0xDFFF then
                  pos = pos + 6
                  cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
                  ok = true
                end
              end
            end
            if not ok then cp = 0xFFFD end
          elseif cp >= 0xDC00 and cp <= 0xDFFF then
            cp = 0xFFFD
          end
          -- [/snip]
          out[#out + 1] = utf8_encode(cp)
        else
          return nil, fmt("非法转义 \\%s @ %d", e == "" and "EOF" or e, pos)
        end
      else
        local b = byte(c)
        if b < 0x20 then
          return nil, fmt("字符串里有未转义的控制字符 0x%02X @ %d", b, pos)
        end
        out[#out + 1] = c
        pos = pos + 1
      end
    end
    return nil, "字符串未闭合 @" .. pos
  end

  -- [snip:tok_number]
  -- 数字先按 JSON 文法扫描，绝不让 tonumber 兜底：
  -- 前导零、+1、.5、5.、1e 这些都必须在这里拦下。
  local function read_number()
    local start = pos
    if sub(text, pos, pos) == "-" then pos = pos + 1 end
    local c = sub(text, pos, pos)
    if c == "0" then
      pos = pos + 1
      if is_digit(sub(text, pos, pos)) then
        return nil, "数字不能有前导零 @" .. start
      end
    elseif is_digit(c) then
      repeat pos = pos + 1; c = sub(text, pos, pos) until not is_digit(c)
    else
      return nil, "数字缺少整数部分 @" .. start
    end
    if sub(text, pos, pos) == "." then
      pos = pos + 1
      if not is_digit(sub(text, pos, pos)) then
        return nil, "小数点后需要数字 @" .. start
      end
      repeat pos = pos + 1 until not is_digit(sub(text, pos, pos))
    end
    local e = sub(text, pos, pos)
    if e == "e" or e == "E" then
      pos = pos + 1
      local s = sub(text, pos, pos)
      if s == "+" or s == "-" then pos = pos + 1 end
      if not is_digit(sub(text, pos, pos)) then
        return nil, "指数部分需要数字 @" .. start
      end
      repeat pos = pos + 1 until not is_digit(sub(text, pos, pos))
    end
    local after = sub(text, pos, pos)
    if after ~= "" and not is_ws(after) and after ~= "," and after ~= "]"
        and after ~= "}" then
      return nil, fmt("数字后跟了意外字符 '%s' @ %d", after, pos)
    end
    local s = sub(text, start, pos - 1)
    local v = tonumber(s)
    if v == nil then return nil, "无法解析数字 " .. s end
    return v
  end
  -- [/snip]

  -- [snip:tok_literal]
  -- 前缀匹配之后必须再查分隔符，否则 nullx 会被当成 null + 尾巴。
  local function read_literal(word, value)
    if sub(text, pos, pos + #word - 1) == word then
      local after = sub(text, pos + #word, pos + #word)
      if after == "" or is_ws(after) or after == "," or after == "]"
          or after == "}" then
        pos = pos + #word
        return value
      end
    end
    return nil, "非法字面量（前缀匹配后必须是分隔符）@" .. pos
  end
  -- [/snip]

  while true do
    while pos <= n and is_ws(sub(text, pos, pos)) do pos = pos + 1 end
    if pos > n then
      toks[#toks + 1] = { kind = "eof", pos = pos }
      return toks
    end
    local at = pos
    local c = sub(text, pos, pos)
    if c == "{" or c == "}" or c == "[" or c == "]"
        or c == ":" or c == "," then
      pos = pos + 1
      toks[#toks + 1] = { kind = c, pos = at }
    elseif c == '"' then
      local v, err = read_string()
      if v == nil then return nil, err end
      toks[#toks + 1] = { kind = "string", value = v, pos = at }
    elseif c == "-" or is_digit(c) then
      local v, err = read_number()
      if v == nil then return nil, err end
      toks[#toks + 1] = { kind = "number", value = v, pos = at }
    elseif c == "n" then
      local v, err = read_literal("null", M.null)
      if v == nil then return nil, err end
      toks[#toks + 1] = { kind = "null", value = v, pos = at }
    elseif c == "t" then
      local v, err = read_literal("true", true)
      if v == nil then return nil, err end
      toks[#toks + 1] = { kind = "true", value = v, pos = at }
    elseif c == "f" then
      local v, err = read_literal("false", false)
      if v == nil then return nil, err end
      toks[#toks + 1] = { kind = "false", value = v, pos = at }
    else
      return nil, fmt("意外字符 '%s' @ %d", c, at)
    end
  end
end

function M.decode(text)
  local toks, err = M.tokenize(text)
  if not toks then return nil, err end
  local i = 1
  local function peek() return toks[i] end
  local function take() local t = toks[i]; i = i + 1; return t end
  local parse_value

  -- [snip:parse_array]
  local function parse_array(depth)
    take()                                    -- [
    local arr = {}
    if peek().kind == "]" then take(); return arr end
    local k = 0
    while true do
      local v, e = parse_value(depth + 1)
      if e then return nil, e end
      k = k + 1
      arr[k] = v
      local t = peek()
      if t.kind == "," then
        take()                                -- 逗号后必须还有值
      elseif t.kind == "]" then
        take()
        return arr
      else
        return nil, fmt("数组里期望 ',' 或 ']' @ %d", t.pos)
      end
    end
  end
  -- [/snip]

  -- [snip:parse_object]
  local function parse_object(depth)
    take()                                    -- {
    local obj = {}
    if peek().kind == "}" then take(); return obj end
    while true do
      local k = peek()
      if k.kind ~= "string" then
        return nil, fmt("对象的键必须是字符串 @ %d", k.pos)
      end
      take()
      if peek().kind ~= ":" then
        return nil, fmt("对象缺少 ':' @ %d", peek().pos)
      end
      take()
      local v, e = parse_value(depth + 1)
      if e then return nil, e end
      obj[k.value] = v                        -- 重复键：后者覆盖前者
      local t = peek()
      if t.kind == "," then
        take()
      elseif t.kind == "}" then
        take()
        return obj
      else
        return nil, fmt("对象里期望 ',' 或 '}' @ %d", t.pos)
      end
    end
  end
  -- [/snip]

  -- [snip:parse_value]
  -- 递归下降的入口：看一个 token，决定走哪条产生式。
  parse_value = function(depth)
    if depth > M.MAX_DEPTH then
      return nil, "嵌套过深（>" .. M.MAX_DEPTH .. "）"
    end
    local t = peek()
    local k = t.kind
    if k == "string" or k == "number" then
      take(); return t.value
    elseif k == "null" then
      take(); return M.null
    elseif k == "true" then
      take(); return true
    elseif k == "false" then
      take(); return false
    elseif k == "{" then
      return parse_object(depth)
    elseif k == "[" then
      return parse_array(depth)
    end
    return nil, fmt("期望一个值 @ %d", t.pos)
  end
  -- [/snip]

  local v, e = parse_value(0)
  if e then return nil, e end
  local t = peek()
  if t.kind ~= "eof" then
    return nil, fmt("尾部多余内容 @ %d", t.pos)
  end
  return v
end

-- [snip:encode_num]
-- 数字回写：5.3+ 的 integer 用 %d，float 用 %.17g。
-- 17 位保证 double 往返严格相等；浮点整值补 ".0"，避免重回 integer。
local function encode_number(n)
  if n ~= n then return nil, "JSON 不能表示 nan" end
  if n == huge or n == -huge then return nil, "JSON 不能表示 inf" end
  if math.type and math.type(n) == "integer" then
    return fmt("%d", n)
  end
  local s = fmt("%.17g", n)
  if not find(s, "[%.eE]") then s = s .. ".0" end
  return s
end
-- [/snip]

-- [snip:encode_string]
local function encode_string(s, out)
  out[#out + 1] = '"'
  for i = 1, #s do
    local b = byte(s, i)
    if b == 34 then out[#out + 1] = '\\"'
    elseif b == 92 then out[#out + 1] = "\\\\"
    elseif b == 8 then out[#out + 1] = "\\b"
    elseif b == 12 then out[#out + 1] = "\\f"
    elseif b == 10 then out[#out + 1] = "\\n"
    elseif b == 13 then out[#out + 1] = "\\r"
    elseif b == 9 then out[#out + 1] = "\\t"
    elseif b < 0x20 then out[#out + 1] = fmt("\\u%04x", b)
    else out[#out + 1] = char(b) end
  end
  out[#out + 1] = '"'
end
-- [/snip]

local function is_array(t)
  local n = #t
  if n == 0 then return false end             -- 空表约定写成对象 {}
  local count = 0
  for k in pairs(t) do
    if type(k) ~= "number" or k < 1 or k > n or k ~= floor(k) then
      return false
    end
    count = count + 1
  end
  return count == n
end

-- [snip:encode_table]
-- Lua 表既可能是数组也可能是对象：键恰好是 1..n 且没有别的键 → 数组。
local function encode_value(v, out, seen, depth)
  if v == M.null then
    out[#out + 1] = "null"; return true
  end
  local tv = type(v)
  if tv == "boolean" then
    out[#out + 1] = v and "true" or "false"; return true
  elseif tv == "number" then
    local s, e = encode_number(v)
    if not s then return false, e end
    out[#out + 1] = s; return true
  elseif tv == "string" then
    encode_string(v, out); return true
  elseif tv == "table" then
    if depth > M.MAX_DEPTH then return false, "嵌套过深" end
    if seen[v] then return false, "循环引用" end
    seen[v] = true
    if is_array(v) then
      out[#out + 1] = "["
      for i = 1, #v do
        if i > 1 then out[#out + 1] = "," end
        local ok, e = encode_value(v[i], out, seen, depth + 1)
        if not ok then return false, e end
      end
      out[#out + 1] = "]"
    else
      local keys = {}
      for k in pairs(v) do
        if type(k) ~= "string" then
          return false, "对象键必须是字符串"
        end
        keys[#keys + 1] = k
      end
      sort(keys)                              -- 键排序 → 输出稳定可复现
      out[#out + 1] = "{"
      for i = 1, #keys do
        if i > 1 then out[#out + 1] = "," end
        encode_string(keys[i], out)
        out[#out + 1] = ":"
        local ok, e = encode_value(v[keys[i]], out, seen, depth + 1)
        if not ok then return false, e end
      end
      out[#out + 1] = "}"
    end
    seen[v] = nil
    return true
  end
  return false, "无法序列化的类型：" .. tv
end
-- [/snip]

function M.encode(v)
  local out = {}
  local ok, err = encode_value(v, out, {}, 0)
  if not ok then return nil, err end
  return concat(out)
end

-- [snip:deep_equal]
-- 深度相等：5.3+ 还要比较 integer / float 子类型，
-- 否则 1 和 1.0 在 Lua 里 == 为真，会把类型回写的 bug 放过去。
function M.deep_equal(a, b)
  local ta, tb = type(a), type(b)
  if ta ~= tb then return false end
  if ta == "number" then
    if a ~= b then return false end
    if math.type and math.type(a) ~= math.type(b) then return false end
    return true
  end
  if ta ~= "table" then return a == b end
  local na, nb = 0, 0
  for k in pairs(a) do
    na = na + 1
    if b[k] == nil then return false end
    if not M.deep_equal(a[k], b[k]) then return false end
  end
  for _ in pairs(b) do nb = nb + 1 end
  return na == nb
end
-- [/snip]

local HEX = "0123456789abcdef"

local function num_hex(x)
  if x ~= x then return "nan" end
  if x == huge then return "inf" end
  if x == -huge then return "-inf" end
  local sign = ""
  if x < 0 then sign = "-"; x = -x end
  if x == 0 then return sign .. "0x0.0p+0" end
  local e = 0
  while x >= 2 do x = x / 2; e = e + 1 end
  while x < 1 do x = x * 2; e = e - 1 end
  local m = (x - 1) * 4503599627370496
  if m < 0 then m = 0 end
  if m > 4503599627370495 then m = 4503599627370495 end
  m = floor(m + 0.5)
  local d = {}
  for i = 13, 1, -1 do
    local q = floor(m / 16)
    d[i] = sub(HEX, m - q * 16 + 1, m - q * 16 + 1)
    m = q
  end
  return sign .. "0x1." .. concat(d) .. fmt("p%+d", e)
end

local function bytes_hex(s)
  local out = {}
  for i = 1, #s do out[i] = fmt("%02x", byte(s, i)) end
  return concat(out)
end
M.bytes_hex = bytes_hex

-- 与 Python 侧对拍用的语义摘要：数字按 IEEE754 精确十六进制，
-- 字符串按 UTF-8 字节，对象键排序，数组保序。
local function digest(v)
  if v == M.null then return "N" end
  local t = type(v)
  if t == "boolean" then return v and "T" or "F" end
  if t == "number" then return "#" .. num_hex(v + 0.0) end
  if t == "string" then return "S" .. bytes_hex(v) end
  if t == "table" then
    if is_array(v) then
      local parts = {}
      for i = 1, #v do parts[i] = digest(v[i]) end
      return "A[" .. concat(parts, ",") .. "]"
    end
    local keys = {}
    for k in pairs(v) do
      if type(k) ~= "string" then return "!badkey" end
      keys[#keys + 1] = k
    end
    sort(keys)
    local parts = {}
    for i = 1, #keys do
      parts[i] = bytes_hex(keys[i]) .. ":" .. digest(v[keys[i]])
    end
    return "O{" .. concat(parts, ",") .. "}"
  end
  return "!type"
end
M.digest = digest

return M
