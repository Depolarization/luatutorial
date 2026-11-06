# luatutorial —— Lua 实战教程系列

一系列围绕 **Lua** 的实战教程。每一章是一个独立、可运行的专题，配有核心 Lua 源码与一段讲解视频。
**章节文件夹以核心 Lua 源码为主**（GitHub 仅作为视频的源码附件托管，构建/录制等流水线不入库）；
第九章例外地带了 `dual/` —— 那一章的内容就是各版本报错文案本身，只给脚本不给输出等于让读者自己复现一遍；
第十、十四章同样附了 `dual/`（五端原始输出），第十四章另有崩溃矩阵 `crash_results.json`。

## 章节

| # | 标题 | 一句话简介 | 视频 | 源码 |
| --- | --- | --- | --- | --- |
| 1 | 用两个 32 位整数，拼出 64 位整数 | 在只有 `double` 与 32 位 `bit32` 的 Lua 5.1/5.2 里，用 hi/lo 模拟 64 位整数（加减乘除、位运算、移位、二进制长除法、转字符串），330 组算例对照 Python 全部一致 | 见 B 站（搜索标题） | [chapter01-lua-int64/](chapter01-lua-int64/) |
| 2 | Lua 的「数字」到底是什么 | `double` 的精度边界与整数陷阱：位级解剖 IEEE 754、2^53 天花板与 ulp 阶梯、`0.1 + 0.2` 的二进制长除法、取整与取模的三个坑，以及 5.3 拆出 `integer`/`float` 子类型这条分水岭。同一份源码在 5.1 / 5.2 / 5.3 / 5.4 / LuaJIT 2.1 上各跑一遍，再用 Python 精确有理数独立复核 | 见 B 站（搜索标题） | [chapter02-lua-number/](chapter02-lua-number/) |
| 3 | Lua 5.1 里没有 utf8 —— 用纯算术手写一个 | 变长编码在字节层面怎么解：首字节连续 1 的个数就是序列长度、`10xxxxxx` 续字节各带 6 位，全程只用乘法和取模（5.1 连 `bit32` 都没有）；九类非法输入的判定（超长编码、代理区、超 `0x10FFFF`、截断、多余续字节）、官方 `charpattern` 里那个真 0 字节为什么会让 5.1 当场崩掉，以及 `len`/`codepoint`/`char`/`offset`/`gmatch` 在 5.1 / 5.3 / 5.4 的语义分歧。322 行纯 Lua，三端实跑，40925 处断言 + 654826 处逐字节对拍 0 差异 | 见 B 站（搜索标题） | [chapter03-lua-utf8/](chapter03-lua-utf8/) |
| 4 | Lua 的表：内存与速度实测 | 一张 `table` 其实是「数组半 + 哈希半」两台各自按 2 的幂扩容的机器：空表 56 B、数组槽 16 B、哈希节点 32 B（5.3 实测），1000 个键占 1024 格而 1025 个键占 2048 格；`#t` 给的是边界不是个数（`{1,2,nil,4,5}` 五家都给 5，`pairs` 只连续走到 2）；追加、预分配、头部插入、尾部删除四种写法的实测单价（头插 8000 次是倒着建的 290 倍）；`..` 拼接造出 93957KB 临时串而 `table.concat` 只要 152KB；字符串驻留在第 41 个字符掉头（5.1 全程驻留，5.2/5.3/5.4 从此逐份实付）；一次全量 GC 的阻塞时间随活表规模超线性增长。7 份探针脚本 × 5 个真实解释器 = 35 组，948 行实测输出，12 条结构性自检 × 5 端零失败 | 见 B 站（搜索标题） | [chapter04-lua-memory-perf/](chapter04-lua-memory-perf/) |
| 5 | Lua 5.1 连位运算符都没有 —— 只用乘法和取模手写 CRC32 / FNV / MD5 | 位运算层复用第三章的纯算术写法并扩到 64 位（`and/or/xor/bnot/lshift/rshift/rotl/mul32`，中间值不超过 2^53，与真 `bit32` 逐函数对拍 2422 项、五端一致），按 `_VERSION` 自动在原生运算符 / `bit32` / 纯算术三个后端间降级；5.1 与 5.3 的分水岭全部现场跑出：`0x7FFFFFFFFFFFFFFF` 被折成 4294967295、`& 0xFFFFFFFF` 编译不过、大数乘法静默丢精度（Python 精确值 `…605`，5.1 给 `…608`，而 `==` 比字面量还返回 `true`）、`% 2^32` 因为 `2^32` 永远是浮点而算成 4278189680（真值 4278189677）；CRC-32 的反射多项式 `0xEDB88320` 与 check 值 `cbf43926`、正向位序为什么对不上 zlib、查表比逐位快 4.6 倍；FNV-1a 一乘一异或、64 位得手搭 limb；MD5 的 K 表 64 项逐个对上 `floor(2^32*|sin i|)`、补位零的个数 `(55-n) mod 64` 的九档边界、四个状态字必须小端逐字节 dump。库本体 546 行，五端实跑 424 / 425 / 447 / 446 / 403 项断言 0 失败，21 条样本与系统 `md5sum`、Windows `certutil`、Python `hashlib` / `zlib` 逐字节对齐 | 见 B 站（搜索标题） | [chapter05-lua-hash/](chapter05-lua-hash/) |
| 6 | 纯手写一个 JSON 解析器 —— 递归下降与精度陷阱 | tokenizer 把字节切成 token，递归下降 parser 把 token 组装成 table，再手写序列化器写回 JSON 字节，全程只用自带字符串与 table。陷阱逐个实测：`null`/`true`/`false` 的前缀匹配（`nullx` 必须报错）、数字严格文法接住 double 的 2^53 与 `1e999`→`inf`、5.3+ 的 `integer` 子类型与回写一致性、八种转义与 `\uXXXX` 代理对合成、对象重复键后者覆盖。200 棵随机树往返 + 与 Python `json` 对拍各 200/200，五端零 FAIL | 见 B 站（搜索标题） | [chapter06-json-parser/](chapter06-json-parser/) |
| 7 | 闭包与 upvalue —— 为什么所有回调打印同一个值 | 用 `while` 在循环里建三个回调，循环结束后依次调用输出 `4 4 4`，五个解释器一致：upvalue 是按引用捕获的单元格，不是按值拷贝；数值 `for` 每轮新建局部变量并关闭（1/2/3），`while` 全程共享（4/4/4）——分水岭在字节码的 `CLOSE`/`JMP` 里（`string.dump` 导出后手工解析，不是手写示意）；最小修复 `local v = i` 与四种等价写法对照，计数器工厂、闭包持有大表的内存滞留配合 `collectgarbage` 实测。9 条断言 × 5 端 0 失败 | 见 B 站（搜索标题） | [chapter07-closure-upvalue/](chapter07-closure-upvalue/) |
| 8 | require 与 package.path —— 模块系统与自定义 searcher | 不背文档，把模块系统拆开实测：`package.path`/`cpath` 的 `?` 占位与顺序短路、`LUA_PATH` 与 `;;` 展开（各版本条目数现场数）、`package.loaded` 缓存与三种强制重载手段的坑、searcher 四段查找（5.1 叫 `package.loaders`、5.2+ 叫 `package.searchers`，loader 参数个数 5.1 只传 name）、手写内存 searcher 把模块源码放进 table 完全绕开文件系统、`module()` 的退场与 clean module 写法。5 脚本 × 5 解释器 = 25 组合全部运行成功 | 见 B 站（搜索标题） | [chapter08-module-searchers/](chapter08-module-searchers/) |
| 9 | error / pcall / xpcall —— 错误处理的三个层级 | `error(msg, level)` 的 level 把位置钉在哪一行（0~6 逐个实测，五家输出完全一致），尾调用会把栈帧折叠掉、同一个 level=1 行号直接指回主 chunk；十一种取空值的写法（索引/调用/取长度/拼接/算术/比较）逐行对照，5.1 / 5.2 / LuaJIT 说 `attempt to index local 't' (a nil value)`，5.3 / 5.4 把名字挪进括号倒过来说；位置前缀只给字符串，`error` 传 table 永远不带行号；pcall 的返回值结构（`select('#')` 实测 4 / 2 / 1 / 2 四种）与吞掉错误之后「没有」和「坏了」长得一样；xpcall 的 handler 里栈才活着（handler 内 8 帧、事后只剩 3 行标题），`debug.traceback` 自己的 level 4→3→2 每加一层少一帧；nil 的静默传播与四种守卫；手写调试助手 `errkit.lua` 出错自动打印位置 + 每帧局部变量快照，一次 pcall 都不用。7 份探针 × 5 个真实解释器 = 35 组输出，181 行里同位置五家一致 122 行，自检 `pass=16 fail=0` 五端全过，另附 19 项能力门 × 5 家一张表 | 见 B 站（搜索标题） | [chapter09-error-pcall-xpcall/](chapter09-error-pcall-xpcall/) |
| 10 | 手写 xoshiro256** —— 可复现随机数与播种陷阱 | 随机数的最高级形态不是「更随机」而是「可复现」：同一个种子必须吐出同一条序列。五家解释器同种子输出全不同源（5.1/5.2/5.3 是 C 运行库 `rand()` 的近亲，LuaJIT 与 5.4 各自独立）；Windows 上 5.3 的 `rand()` 只有 15 位熵（`math.random(0, 2^24)` 抽 2000 次全落在 512 的倍数上）；5.4 内部就是 xoshiro256**，`randomseed(42)` 摆状态 `{42, 0xff, 0, 0}` 丢弃 16 个输出后与官方 C 参考翻译的 1000 值向量逐值全中；纯 Lua 实现复用第一章 int64 方案（hi/lo 双 32 位 + `bit32` 纯算术兜底），同一份代码五端逐位一致；splitmix64 播种的反面教材 `{1,2,3,4}`、全零状态不动点、8×8 世界存档只存一个 u64。5 份探针 × 5 个真实解释器 = 25 组输出，自检 22 项 × 5 端全过，1000 值对拍差异 0 | 见 B 站（搜索标题） | [chapter10-lua-xoshiro/](chapter10-lua-xoshiro/) |
| 14 | table.sort 的雷区 —— 稳定归并排序与比较器契约 | 非法比较器不会让 Lua 真崩：`invalid order function for sorting` 是五端 `pcall` 都接得住的普通错误；但 5.1 的护栏会漏（扫描越界把栈垃圾喂给比较器，200 组里 135 组先撞上 `compare nil`），`{2,2,1}` 配 `>=` 五端全部「返回成功、结果没排」；排序不稳定的最小复现只要 4 个元素，两步排序把并列名次打散；带洞数组与 `#` 的边界逐端实测。自写自底向上稳定归并（gap 翻倍无递归 + 相等取左 + 比较器契约自检），10 万随机数组与 Python `sorted` 五端 0 差异，LuaJIT 上归并 13ms 反超原生 25ms。8 份探针 × 5 个真实解释器 = 40 组输出（原始输出与崩溃矩阵在 `dual/`、`crash_results.json`），自检 `pass=21 fail=0` 五端全过 | 见 B 站（搜索标题） | [chapter14-sort-merge-stable/](chapter14-sort-merge-stable/) |

## 适合谁

- 在用 Lua 5.1 / 5.2（含 AndroLua、OpenResty 早期版本、某些游戏 MOD 环境）做底层数值的人；
- 想搞清楚「为什么 64 位整数在 Lua 里是个难题」的人；
- 被 `0.1 + 0.2 ~= 0.3`、`9007199254740993 == 2^53` 这类判等坑到过，想知道二进制层面到底发生了什么的人；
- 在 5.1 / 5.2 里处理中文，发现 `#s` 数的是字节、`utf8` 和 `bit32` 两个库都不在的人；
- 被「这张表到底占多少内存」「`#t` 为什么时有时无」「`..` 拼一下就 GC 一下」卡过的人；
- 要在 5.1 / 5.2 里给资源包、存档做完整性校验，却发现没有 `md5`、没有 `crc32`、连 `&` 都写不出来的人；
- 明明已经用 `pcall` 包住了、线上还是崩，而崩溃日志只有一行 `attempt to index a nil value`、找不到位置的人；
- 想看「确定性网页渲染 + 配音 + 逐帧录制」怎么做技术讲解视频的人（第一章附带完整生产线）。

## 约定

- 每章文件夹各自独立，只含核心 Lua 源码；视频与封面随章节在 B 站发布，不在仓库内。
- 第一章源码以 Lua 5.1 / 5.2 为目标环境（只有 `double` 与 32 位 `bit32`）；第二章源码在 5.1 / 5.2 / 5.3 / 5.4 / LuaJIT 2.1 上都能直接跑；第三章源码在 5.1 / 5.2 / 5.3 / 5.4 上都能直接跑（只用乘法和取模，不碰 `bit32`，也不碰 5.3 才有的位运算符）；第四章源码在 5.1 / 5.2 / 5.3 / 5.4 / LuaJIT 2.1 上都能直接跑（`perfkit.lua` 只用 5.1 就有的语法）；第五章源码在 5.1 / 5.2 / 5.3 / 5.4 上都能直接跑（位运算一律走 `bitop.lua`，纯算术路径只用乘法和取模，中间值不超过 2^53）；第六、七章源码在 5.1 / 5.2 / 5.3 / 5.4 / LuaJIT 2.1 上都能直接跑；第八章源码五家都能跑（`loaders` vs `searchers`、loader 参数个数这些版本差异本身就是内容，以实测输出为准）。
- 第二章入口：在 `src/` 目录下 `lua test.lua`（自检，版本无关的断言 + 分版本的断言），其余 `precision.lua` / `float_cmp.lua` / `rounding.lua` / `version_diff.lua` 是视频里逐行展示的算例。
- 第三章入口：在 `src/` 目录下 `lua test.lua`（三层自检：对照 `vectors.lua` 里 Python 独立实现算出的标准答案 → 对照真实 5.4 的原生 `utf8` 逐字节对拍 → 随机字节串对拍）。`utf8lite.lua` 是库本体（322 行，`require` 即用），`demo.lua` / `version_probe.lua` 是视频里逐行展示的算例，`smoke.lua` 是最小冒烟。
- 第四章入口：在 `src/` 目录下 `lua test.lua`（12 条**结构性**自检，五个解释器各跑一遍）；`perfkit.lua` 是测量工具箱（重复取最优、停 GC 测内存增量、纳秒单价），其余 6 份是视频里逐行展示的探针：`table_mem.lua`（两半计价与 2 的幂扩容）· `hash_border.lua`（`#t` 的边界语义）· `insert_cost.lua`（追加/预分配/头插/尾删）· `concat_bench.lua`（拼接耗时与临时垃圾）· `str_intern.lua`（驻留边界与判等）· `gc_probe.lua`（GC 接口、停顿规模、临时表、LuaJIT）。
- 第四章的注意事项（**随构建而异，视频里没有当结论讲**）：
  · 耗时读数跟机器走，只作同机对比；换机器请重跑，别拿本仓库的数字当基准。亚毫秒级的循环先放大 4~8 倍再除，因为 Windows 的 `os.clock()` 只有 1ms 精度。
  · `collectgarbage` 的 `setstepsize` / `param` / `setgoal` 在这五个解释器上全部被拒（`invalid option`），`setpause` / `setstepmul` 五家都收；`incremental` / `generational` 只有 5.2 与 5.4 这两个构建接受，5.1 / 5.3 / LuaJIT 会报错 —— 换发行版（如 OpenResty、LuaJIT 的 GC64 构建）结论可能不同。
  · 视频用的是本机 lupa 绑定的 LuaJIT，它没有 `jit.gcstep` / `jit.stat`，所以只实测了 `jit.on` / `jit.off` 这一对；用完整 LuaJIT 的读者可以自行补测。
- 第五章入口：在 `src/` 目录下 `lua test.lua`（对照 `vectors.lua` 里独立算出的标准答案，逐条断言 CRC32 / FNV / MD5 三套算法 + 补位边界 + 分块接力）。四个库本体 `bitop.lua`（233 行，位运算层，按 `_VERSION` 自动选后端）· `crc32.lua`（86 行）· `fnv.lua`（105 行）· `md5.lua`（122 行）都是零依赖、`require` 即用；`demo.lua` / `runtime_probe.lua` 是视频里逐行展示的算例，`smoke.lua` 是最小冒烟。
- 第五章的注意事项：
  · 别拿系统的 `cksum` 对拍 CRC32 —— 它是 POSIX 那套，多项式和初值都不一样（空串给 4294967295，而 zlib 给 0）。对拍请用 `md5sum` / `certutil -hashfile` / Python `zlib.crc32`。
  · 耗时读数跟机器走，只作同机对比（视频里逐位 vs 查表的 4.6 倍是五端各自交替多轮取最快跑出来的，换机器请重跑）。
- 第六章入口：在 `src/` 目录下 `lua json_test.lua`（200 棵随机树生成 → 序列化 → 再解析深度相等 + 与 Python `json` 对拍，double 精度边界样本单独标注不参与严格相等）。`jsonkit.lua` 是库本体（tokenizer + 递归下降 parser + 序列化器，`require` 即用），`probe_json.lua` 是视频里逐行展示的算例。
- 第七章入口：在 `src/` 目录下 `lua test.lua`（9 条断言，五个解释器各跑一遍）。`capture.lua`（捕获语义与「4 4 4」最小复现）· `fixes.lua`（五种修复写法对照）· `counter.lua`（计数器工厂）· `memory.lua`（闭包持有大表 + `collectgarbage` 实测）；字节码证据由 `string.dump` 导出后手工解析，解析脚本不入库（随视频工程）。
- 第八章入口：把 `src/` 加入 `package.path` 后 `lua require_cache.lua`（重复 `require` 只执行一次的计数证据）。`env_probe.lua`（各版本 `package` 表与 `LUA_PATH` 实测）· `path_search.lua`（`?` 占位与顺序短路）· `mem_searcher.lua`（内存 searcher，模块源码在 `mods/` 里由 searcher 从表内 load）· `module_legacy.lua`（`module()` 退场与 clean module 对照）；`modkit.lua` 是演示用工具集。
- 第九章源码在 5.1 / 5.2 / 5.3 / 5.4 / LuaJIT 2.1 上都能直接跑（`errkit.lua` 只用五家共有的语法；`assert(false, 表)`、协程穿 `pcall` 的 yield、双下划线元字段这些版本差异本身就是内容，以 `dual/` 里的实测输出为准）。
- 第九章入口：在 `src/` 目录下 `lua t0_selftest.lua`（16 条断言，五个解释器各跑一遍，末行 `SUMMARY pass=16 fail=0`）。`errkit.lua` 是调试助手本体（出错自动打印位置 + 每帧局部变量快照，`require` 即用，不需要 `pcall`）；`t1_levels.lua`（level 0~6 各钉在哪一行 + 尾调用折叠栈帧）· `t2_pcall.lua`（返回值结构与吞掉错误）· `t3_traceback.lua`（handler 里抓栈、`debug.traceback` 自己的 level）· `t4_nilchain.lua`（十一种取空值写法与四种守卫）· `t5_helper.lua`（errkit 现场调用）· `t6_gates.lua`（19 项能力门 × 5 家矩阵）是视频里逐行展示的探针。
- 第九章的 `dual/<脚本>.<版本>.txt`（35 份，版本是 `lua51` / `lua52` / `lua53` / `lua54` / `luajit21`）是五个真实解释器的原始输出，逐行对照用；报错文案跟构建走，发行版打过补丁的请重跑再比，别直接拿本仓库的字符串当你的线上日志。

## 许可证

见 [LICENSE](LICENSE)。
