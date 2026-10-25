-- 真实文件模块：证明 require 走的是文件系统 searcher
DEMO_RUNS = (DEMO_RUNS or 0) + 1
return {
  tag = "demo_mod@src/mods",
  runs = DEMO_RUNS,
  ver = _VERSION,
}
