# Lua 用两个 32 位整数模拟 64 位整数（讲解视频工程）

> **luatutorial 系列 · 第一章**。返回 [系列总目录](../README.md)。
> 本目录自包含：源码、可复现的构建脚本、讲解视频成品（`out/lua_int64.mp4`）与封面（`out/cover.png`）都在这里。

**标题**：用两个 32 位整数，拼出 64 位整数
**封面**：`out/cover.png`（1920×1080，网页渲染，改 `web/cover.html` 后 `node tools/make_cover.js` 重出）
**配音**：edge-tts / `zh-CN-YunxiNeural` / rate +10%

成片：`out/lua_int64.mp4`（1920×1080 / 20fps / 4 分 59 秒 / 中文配音 / H.264+AAC）

## 目录

| 路径 | 说明 |
| --- | --- |
| `src/int64.lua` | 核心库：hi/lo 表示的 64 位整数（加、减、乘、除、位运算、移位、转字符串） |
| `src/bit32_pure.lua` | 纯算术实现的 bit32 兼容层（Lua 5.1 没有 bit32 时可用） |
| `src/demo.lua` | 演示脚本，输出会被搬到视频的「运行结果」面板 |
| `src/test.lua` + `src/vectors.lua` | 与 Python 大整数对照的自检（330 组随机算例） |
| `web/index.html` | 演示网页（确定性时间轴，可逐帧录制） |
| `tools/narration.json` | 20 段解说词 |
| `out/lua_int64.mp4` | 最终成片 |

## 核心约定

```
V = hi * 2^32 + lo        hi, lo ∈ [0, 2^32)
无符号范围 0 … 2^64-1；按二补码解释，负数 = hi 最高位为 1
```

三个必须记住的坑：

1. **整除要修正**：double 相除可能因舍入跨过整数边界，整除后用乘法反向校验一次（`fdiv`）。
2. **中间值必须 < 2^53**：所以乘法把 32 位再拆成两个 16 位半字，16×16=32 位，double 精确。
3. **全程保持浮点**：`math.floor(x/q) + 0.0`，避免被 Lua 5.3 的整数运算截断（fengari 的整数乘法甚至会 32 位溢出）。

## 复现流程

```bash
# 1) 跑 Lua（fengari，纯 JS 的 Lua VM）+ 自检
python tools/gen_vectors.py                 # 生成随机算例（Python 大整数给答案）
node tools/run_lua.js > out/lua_output.txt

# 2) 生成网页数据（代码片段 + 真实输出）
python tools/build_page.py

# 3) 配音（edge-tts，zh-CN-YunxiNeural）
python tools/tts.py

# 4) 逐帧录制网页 + 合成视频
node tools/check_layout.js                  # 可选：布局体检，应输出「全部场景布局正常」
node tools/record.js
python tools/build_video.py
```

依赖：`pip install imageio-ffmpeg edge-tts`、`npm i playwright-core fengari`（录制用本机已装的 Chrome）。

## 成片与后期

`out/lua_int64.mp4` 是已渲染好的讲解视频（4 分 59 秒，含中文配音），可直接上传 B 站；
`out/cover.png` 是配套封面；`out/简介.txt` 含视频简介与已校验的 B 站章节（≤10 章、单章名 ≤16 字）。

仓库只提交了成品，未包含 `narration.wav` 与分段 mp3 等大体积中间产物。若想重新配音或加 BGM，
按上面的「复现流程」跑 `tools/tts.py` 等脚本即可本地重新生成。
