-- sortkit.lua：探针工具箱。只用 Lua 5.1 就有的语法（五端一份源码）。
-- 这里只提供「测量手段」和稳定归并排序本体，不写死任何结论；
-- 画面上的每个数字都由调用它的探针在真实解释器上跑出来。
local M = {}
local clock = os.clock
local floor = math.floor

--------------------------------------------------------------------
-- 测量：Windows 上 os.clock() 只有 1ms 分辨率，
-- 先自动把重复次数放大到总耗时超过 target 秒，再同次数再跑两轮取最小。
-- 返回（单次耗时秒, 实际重复次数）。
--------------------------------------------------------------------
function M.bench(f, target)
  target = target or 0.12
  local r, d = 1, 0
  while true do
    local t0 = clock()
    for _ = 1, r do f() end
    d = clock() - t0
    if d >= target or r >= 1048576 then break end
    r = r + r
  end
  local best = d / r
  for _ = 1, 2 do
    local t0 = clock()
    for _ = 1, r do f() end
    local d2 = clock() - t0
    if d2 / r < best then best = d2 / r end
  end
  return best, r
end

--------------------------------------------------------------------
-- 确定性随机：Park-Miller。全程浮点、结果都在 2^53 内精确，
-- 所以五个解释器跑同一份种子得到逐位相同的序列。
--------------------------------------------------------------------
function M.rng(seed)
  local s = (seed or 20261104) + 0.0    -- +0.0 强制浮点，5.3/5.4 不会走整数回绕
  return function()
    s = (s * 16807.0) % 2147483647.0
    return s
  end
end

function M.gen(n, mod, seed)
  local rnd = M.rng(seed)
  local t = {}
  for i = 1, n do t[i] = rnd() % mod end
  return t
end

function M.copy(t)
  local c = {}
  for i = 1, #t do c[i] = t[i] end
  return t and c
end

-- 短预览：前 n 项。数字格式化成整数样，nil 显示成 _（带洞数组的洞）
function M.dump(t, n, get)
  local m = n or #t
  if m > 16 then m = 16 end
  local s = {}
  for i = 1, m do
    local v = get and get(t[i]) or t[i]
    if v == nil then
      s[i] = "_"
    elseif type(v) == "number" then
      s[i] = string.format("%.0f", v)
    else
      s[i] = tostring(v)
    end
  end
  return table.concat(s, ",")
end

--------------------------------------------------------------------
-- 稳定归并排序（自底向上，无递归）
--------------------------------------------------------------------
M.lt = function(a, b) return a < b end

-- 预分配：升序把 1..n 填满，把数组部分撑到 n 个槽（第 4 章的知识：
-- 倒着填第一个键就是大整数，整张表落进哈希部分，内存翻几倍）。
function M.prealloc(t, n)
  for i = 1, n do t[i] = false end
  return t
end

-- 稳定归并的核心一步：src[lo..mid] 与 src[mid+1..hi]（各自有序）并进 dst[lo..hi]。
-- 取右边的前提是 cmp(右, 左) 为真；相等时 cmp(右, 左) 为假 → 左边先走 → 稳定。
function M.merge(src, dst, lo, mid, hi, cmp)
  local i, j, k = lo, mid + 1, lo
  while i <= mid and j <= hi do
    if cmp(src[j], src[i]) then
      dst[k] = src[j]
      j = j + 1
    else
      dst[k] = src[i]
      i = i + 1
    end
    k = k + 1
  end
  while i <= mid do dst[k] = src[i]; i = i + 1; k = k + 1 end
  while j <= hi do dst[k] = src[j]; j = j + 1; k = k + 1 end
end

-- 自底向上：宽度 1,2,4,8… 翻倍；两个缓冲区轮流当源，扫完一整遍才换手。
-- 无递归 → 没有栈溢出风险；相等元素永远左先右后 → 天然稳定。
function M.msort(arr, cmp, aux)
  local n = #arr
  if n < 2 then return arr end
  cmp = cmp or M.lt
  aux = aux or M.prealloc({}, n)
  local src, dst = arr, aux
  local width = 1
  while width < n do
    local lo = 1
    while lo <= n do
      local mid = lo + width - 1
      if mid >= n then
        for k = lo, n do dst[k] = src[k] end   -- 只剩一段，整段照抄
      else
        local hi = lo + width + width - 1
        if hi > n then hi = n end
        M.merge(src, dst, lo, mid, hi, cmp)
      end
      lo = lo + width + width
    end
    src, dst = dst, src
    width = width + width
  end
  if src ~= arr then                            -- 结果落在 aux，抄回原表
    for k = 1, n do arr[k] = src[k] end
  end
  return arr
end

--------------------------------------------------------------------
-- 比较器契约自检（抽查，不是全量验证；O(几×rounds)）：
--   ① 严格性：cmp(x,x) 必须为假 —— >= / <= 在这里当场暴露
--   ② 反对称：cmp(a,b) 与 cmp(b,a) 不得同时为真
--   ③ 传递性：cmp(a,b) 且 cmp(b,c) 则 cmp(a,c)（抽查测不出全部违例）
-- 返回 ok, msg
--------------------------------------------------------------------
function M.check_cmp(cmp, arr, rounds)
  local n = #arr
  if n == 0 then return true, "" end
  rounds = rounds or 24
  local step = floor(n / rounds)
  if step < 1 then step = 1 end
  local function at(i) return arr[(i - 1) * step % n + 1] end
  for i = 1, rounds do
    if cmp(at(i), at(i)) then
      return false, "cmp(x,x) 为真，不是严格序（常见于 >= / <=）"
    end
  end
  for i = 1, rounds do
    local a, b = at(i), at(i + 7)
    if cmp(a, b) and cmp(b, a) then
      return false, "cmp(a,b) 与 cmp(b,a) 同时为真，互相矛盾"
    end
  end
  for i = 1, rounds do
    local a, b, c = at(i), at(i * 3 + 1), at(i * 7 + 2)
    if cmp(a, b) and cmp(b, c) and not cmp(a, c) then
      return false, "a<b 且 b<c 却不 a<c，传递性被破坏"
    end
  end
  return true, ""
end

-- 带契约自检的排序：非法比较器给可读报错（level=2 指到调用方），不让上层崩
function M.msort_checked(arr, cmp)
  local ok, msg = M.check_cmp(cmp or M.lt, arr)
  if not ok then
    error("comparator 契约自检失败: " .. msg, 2)
  end
  return M.msort(arr, cmp)
end

--------------------------------------------------------------------
-- 验证助手
--------------------------------------------------------------------
-- 是否非降序（按 cmp 的语义），返回 ok, 首个坏位置
function M.sorted(t, cmp)
  cmp = cmp or M.lt
  for i = 2, #t do
    if cmp(t[i], t[i - 1]) then return false, i end
  end
  return true
end

-- 内容没被排序改掉（多重集一致）；get 取比较键，默认取元素本身
function M.same_multiset(t, ref, get)
  get = get or function(v) return v end
  local a, b = {}, {}
  for i = 1, #t do
    local k = tostring(get(t[i]))
    a[k] = (a[k] or 0) + 1
  end
  for i = 1, #ref do
    local k = tostring(get(ref[i]))
    b[k] = (b[k] or 0) + 1
  end
  for k, v in pairs(a) do
    if b[k] ~= v then return false, k end
  end
  for k, v in pairs(b) do
    if a[k] ~= v then return false, k end
  end
  return true
end

-- 稳定性检查：记录带 .s（原序号），同键之内 s 必须仍升序
-- 相邻对检查是充分的：顺序若不是升序，必有相邻一对比原来还大
function M.stable_by(t, get)
  for i = 2, #t do
    if get(t[i - 1]) == get(t[i]) and t[i - 1].s > t[i].s then
      return false, i
    end
  end
  return true
end

-- 稳定插入排序：小规模对拍用的参照实现
function M.isort(t, cmp)
  cmp = cmp or M.lt
  for i = 2, #t do
    local v = t[i]
    local j = i - 1
    while j >= 1 and cmp(v, t[j]) do
      t[j + 1] = t[j]
      j = j - 1
    end
    t[j + 1] = v
  end
  return t
end

return M
