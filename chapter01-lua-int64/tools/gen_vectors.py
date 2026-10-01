"""生成随机 64 位算例（用 Python 的大整数当标准答案），供 Lua 自检对照。"""
import random, pathlib

M = 1 << 64
random.seed(20261001)
rows = []

def add_case(op, a, b, exp):
    rows.append((op, a, b, exp))

for _ in range(40):
    a, b = random.randrange(M), random.randrange(M)
    add_case("add", a, b, (a + b) % M)
    add_case("sub", a, b, (a - b) % M)
    add_case("mul", a, b, (a * b) % M)

for _ in range(30):
    a, b = random.randrange(M), random.randrange(1, M)
    add_case("div", a, b, a // b)
    add_case("mod", a, b, a % b)

for _ in range(30):
    a, b = random.randrange(M), random.randrange(M)
    add_case("band", a, b, a & b)
    add_case("bor", a, b, a | b)
    add_case("bxor", a, b, a ^ b)

for _ in range(30):
    a, n = random.randrange(M), random.randrange(0, 64)
    add_case("shl", a, n, (a << n) % M)
    add_case("shr", a, n, a >> n)

out = pathlib.Path(__file__).resolve().parent.parent / "src" / "vectors.lua"
with out.open("w", encoding="utf-8") as f:
    f.write("-- 由 tools/gen_vectors.py 生成：Python 大整数给出的标准答案\nreturn {\n")
    for op, a, b, e in rows:
        f.write('  {"%s", "%d", "%d", "%d"},\n' % (op, a, b, e))
    f.write("}\n")
print("生成用例:", len(rows), "->", out)
