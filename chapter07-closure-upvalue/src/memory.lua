-- 探针 4：闭包持有大表，什么时候回收、什么时候滞留
local function kb()
  return collectgarbage("count")
end
local function kb1(x)
  return string.format("%.1f", x)
end
local function settle()
  collectgarbage("collect")
  collectgarbage("collect")
end

settle()
local base = kb()

-- 1. 闭包捕获整张大表：即使不再使用，只要闭包还活着，大表就回收不了
-- >>> SNIP mem_keeper
local function make_keeper()
  local big = {}
  for i = 1, 120000 do
    big[i] = i
  end
  return function() return big[#big] end
end
-- <<< SNIP mem_keeper

local keep = make_keeper()
settle()
local held = kb()

keep = nil
settle()
local freed = kb()

print("MEM_BASE_KB", kb1(base))
print("MEM_HELD_KB", kb1(held))
print("MEM_FREED_KB", kb1(freed))
print("MEM_DELTA_KB", kb1(held - base))
print("MEM_RECLAIM_KB", kb1(held - freed))
print("MEM_RETAIN_KB", kb1(freed - base))

-- 2. 只捕获一个元素：大表本身可以回收
-- >>> SNIP mem_piece
local function make_piece()
  local big = {}
  for i = 1, 120000 do
    big[i] = i
  end
  local last = big[#big]
  return function() return last end
end
-- <<< SNIP mem_piece
local piece = make_piece()
settle()
local piece_kb = kb()
print("MEM_PIECE_DELTA_KB", kb1(piece_kb - base))
print("PIECE_RET", piece())
