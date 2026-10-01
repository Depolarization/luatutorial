"""从 src/*.lua 抽取代码片段 + 真实运行输出，生成 web/data.js。
保证网页上显示的代码与真正跑过的源码一致。"""
import io, json, pathlib, re

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "src"

# 每个片段 = 若干 (起始行正则, 结束行正则[不含]) 切片，之间用空行连接
SNIPPETS = {
    "ctor": [
        (r"^local function u32", r"^local function fdiv"),
        (r"^local function new", r"^local ZERO"),
        (r"^function int64\.fromNumber", r"^function int64\.fromString"),
    ],
    "fdiv": [(r"^local function fdiv", r"^local function new")],
    "add": [(r"^function int64\.add", r"^function int64\.sub")],
    "sub": [(r"^function int64\.sub", r"^-- 比较")],
    "cmp": [(r"^function int64\.eq", r"^-- 位运算")],
    "bitops": [(r"^local function bw", r"^function int64\.bit")],
    "shl": [(r"^function int64\.shl", r"^function int64\.shr")],
    "mul32": [(r"^local function mul32", r"^function int64\.mul")],
    "mul": [(r"^function int64\.mul", r"^-- 除法")],
    "divmod": [(r"^function int64\.divmod", r"^-- 转字符串")],
    "tostring": [(r"^function int64\.tostring", r"^local HEXDIGIT")],
}


def find(lines, pat, start=0):
    rx = re.compile(pat)
    for i in range(start, len(lines)):
        if rx.search(lines[i]):
            return i
    raise SystemExit("找不到片段锚点: " + pat)


def slice_between(lines, start_pat, stop_pat):
    i = find(lines, start_pat)
    j = find(lines, stop_pat, i + 1)
    return i, lines[i:j]


def build():
    src = (SRC / "int64.lua").read_text(encoding="utf-8").split("\n")
    out = {}
    for name, parts in SNIPPETS.items():
        chunks, first_line = [], None
        for a, b in parts:
            ln, body = slice_between(src, a, b)
            while body and body[-1].strip() == "":
                body.pop()
            while body and re.match(r"^-{3,}$", body[-1].strip()):
                body.pop()
            if first_line is None:
                first_line = ln + 1
            chunks.append("\n".join(body))
        out[name] = {"line": first_line, "text": "\n\n".join(chunks)}

    luaout = (ROOT / "out" / "lua_output.txt").read_text(encoding="utf-8").split("\n")
    while luaout and luaout[-1].strip() == "":
        luaout.pop()

    js = "window.SNIPPETS = %s;\nwindow.LUAOUT = %s;\n" % (
        json.dumps(out, ensure_ascii=False, indent=1),
        json.dumps(luaout, ensure_ascii=False, indent=1),
    )
    (ROOT / "web" / "data.js").write_text(js, encoding="utf-8")
    print("生成 web/data.js，片段：", ", ".join(out))
    for k, v in out.items():
        print("  %-9s 起始行 %3d，%d 行" % (k, v["line"], v["text"].count("\n") + 1))


if __name__ == "__main__":
    build()
