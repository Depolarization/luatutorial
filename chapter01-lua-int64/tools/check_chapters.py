"""校验视频章节是否符合 B 站限制：最多 10 个、名称 ≤16 字、时间递增且首条为 00:00。
用法：python tools/check_chapters.py out/简介.txt [视频总秒数]
"""
import re, sys

MAX_N, MAX_LEN = 10, 16
rx = re.compile(r"^(\d{1,2}):(\d{2})\s+(.+?)\s*$")

path = sys.argv[1] if len(sys.argv) > 1 else "out/简介.txt"
total = float(sys.argv[2]) if len(sys.argv) > 2 else None

rows, bad = [], 0
for line in open(path, encoding="utf-8"):
    m = rx.match(line.strip())
    if m:
        rows.append((int(m.group(1)) * 60 + int(m.group(2)), m.group(3)))

if not rows:
    print("没找到章节行（格式应为 'MM:SS 标题'）"); sys.exit(1)

print("章节数：%d（上限 %d）%s" % (len(rows), MAX_N, "OK" if len(rows) <= MAX_N else "超限!"))
if len(rows) > MAX_N: bad += 1
if rows[0][0] != 0: print("首条必须从 00:00 开始！"); bad += 1

for i, (t, title) in enumerate(rows):
    n = len(title)
    flag = "" if n <= MAX_LEN else "  <== 超 %d 字" % (n - MAX_LEN)
    if n > MAX_LEN: bad += 1
    print("  %02d:%02d  %-20s %2d 字%s" % (t // 60, t % 60, title, n, flag))
    if i and t <= rows[i - 1][0]:
        print("  时间戳未递增！"); bad += 1

if total and rows[-1][0] >= total:
    print("末条 %02d:%02d 超过视频总长 %.0f 秒！" % (rows[-1][0] // 60, rows[-1][0] % 60, total)); bad += 1

print("结论：" + ("全部合规" if bad == 0 else "有 %d 处需要修" % bad))
sys.exit(1 if bad else 0)
