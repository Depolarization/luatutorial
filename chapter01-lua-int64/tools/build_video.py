"""把逐帧截图 + 分段配音合成最终 mp4。"""
import json, pathlib, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
GAP = 0.30          # 场景间静音（秒），须与 record.js 的 GAP 一致


def ffmpeg():
    import imageio_ffmpeg
    return imageio_ffmpeg.get_ffmpeg_exe()


def run(args):
    r = subprocess.run([ffmpeg(), "-y", "-hide_banner", "-loglevel", "error", *args],
                       cwd=str(ROOT), capture_output=True, text=True, errors="ignore")
    if r.returncode != 0:
        print("FFMPEG 失败:\n", r.stderr[-2000:])
        sys.exit(1)


def build_audio():
    segs = json.loads((ROOT / "out" / "durations.json").read_text(encoding="utf-8"))
    tmp = ROOT / "out" / "audiotmp"
    tmp.mkdir(parents=True, exist_ok=True)

    sil = tmp / "sil.wav"
    if not sil.exists():
        run(["-f", "lavfi", "-i", "anullsrc=channel_layout=mono:sample_rate=44100",
             "-t", str(GAP), "-c:a", "pcm_s16le", str(sil.relative_to(ROOT))])

    items, total = [], 0.0
    for i, s in enumerate(segs):
        w = tmp / ("s%02d.wav" % i)
        run(["-i", str(pathlib.Path(s["file"]).as_posix()), "-ar", "44100", "-ac", "1",
             "-c:a", "pcm_s16le", str(w.relative_to(ROOT))])
        items.append(w.as_posix())
        total += s["dur"]
        if i != len(segs) - 1:
            items.append(sil.as_posix())
            total += GAP

    lst = ROOT / "out" / "audio.txt"
    lst.write_text("ffconcat version 1.0\n" +
                   "".join("file '%s'\n" % p for p in items), encoding="utf-8")
    run(["-f", "concat", "-safe", "0", "-i", "out/audio.txt",
         "-c:a", "pcm_s16le", "out/narration.wav"])
    print("配音音轨：out/narration.wav  %.1f 秒" % total)
    return total


def build_video():
    frames = json.loads((ROOT / "out" / "frames.json").read_text(encoding="utf-8"))
    lines = ["ffconcat version 1.0\n"]
    for f in frames:
        lines.append("file '%s'\n" % (ROOT / "out" / "frames" / f["file"]).as_posix())
        lines.append("duration %.3f\n" % f["dur"])
    lines.append("file '%s'\n" % (ROOT / "out" / "frames" / frames[-1]["file"]).as_posix())
    (ROOT / "out" / "frames.txt").write_text("".join(lines), encoding="utf-8")
    print("共 %d 帧" % len(frames))

    run(["-f", "concat", "-safe", "0", "-i", "out/frames.txt",
         "-i", "out/narration.wav",
         "-c:v", "libx264", "-preset", "medium", "-crf", "18",
         "-pix_fmt", "yuv420p", "-r", "20",
         "-af", "loudnorm=I=-16:TP=-1.5:LRA=11",
         "-c:a", "aac", "-b:a", "192k", "-shortest",
         "-movflags", "+faststart", "out/lua_int64.mp4"])
    print("完成：out/lua_int64.mp4")


if __name__ == "__main__":
    build_audio()
    build_video()
