"""用 edge-tts 生成中文配音；输出每段 mp3 与时长表。"""
import asyncio, json, pathlib, re, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "out" / "audio"
OUT.mkdir(parents=True, exist_ok=True)

VOICE = "zh-CN-YunxiNeural"
RATE = "+10%"
FFMPEG = None


def ffmpeg():
    global FFMPEG
    if FFMPEG is None:
        import imageio_ffmpeg
        FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()
    return FFMPEG


def duration(path):
    r = subprocess.run([ffmpeg(), "-hide_banner", "-i", str(path)],
                       capture_output=True, text=True, errors="ignore")
    m = re.search(r"Duration:\s*(\d+):(\d+):(\d+\.\d+)", r.stderr)
    if not m:
        raise SystemExit("读不出时长: " + str(path))
    h, m_, s = int(m.group(1)), int(m.group(2)), float(m.group(3))
    return h * 3600 + m_ * 60 + s


async def synth(item, path):
    import edge_tts
    last = None
    for attempt in range(5):          # edge-tts 偶发 NoAudioReceived，重试即可
        try:
            c = edge_tts.Communicate(item["text"], VOICE, rate=RATE)
            await c.save(str(path))
            if path.stat().st_size > 1000:
                return
            last = RuntimeError("音频过小")
        except Exception as e:
            last = e
        await asyncio.sleep(1.2 * (attempt + 1))
    raise SystemExit("配音失败 %s: %s" % (item["id"], last))


async def main():
    items = json.loads((ROOT / "tools" / "narration.json").read_text(encoding="utf-8"))
    res = []
    for i, it in enumerate(items, 1):
        p = OUT / ("%02d_%s.mp3" % (i, it["id"]))
        if not p.exists() or p.stat().st_size < 1000:
            await synth(it, p)
        d = duration(p)
        res.append({"id": it["id"], "file": str(p), "dur": round(d, 3)})
        print("%2d %-16s %6.2fs" % (i, it["id"], d))
    (ROOT / "out" / "durations.json").write_text(
        json.dumps(res, ensure_ascii=False, indent=1), encoding="utf-8")
    print("总时长 %.1f 秒" % sum(r["dur"] for r in res))


if __name__ == "__main__":
    asyncio.run(main())
