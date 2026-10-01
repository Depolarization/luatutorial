// 用本机 Chrome 打开演示页，按「确定性时间轴」逐帧截图，
// 保证画面与配音严格同步（每场景只在开头 1.4s 有动画，其余时间静止）
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright-core");

const ROOT = path.resolve(__dirname, "..");
const FRAMES = path.join(ROOT, "out", "frames");
const PAGE = "file:///" + path.join(ROOT, "web", "index.html").replace(/\\/g, "/");
const CHROME = "C:/Program Files/Google/Chrome/Application/chrome.exe";

const GAP = 300;        // 场景之间的停顿（ms），与音频拼接的静音一致
const MOTION = 1400;    // 每个场景的动画窗口（ms）
const STEP = 50;        // 20fps

(async () => {
  const durs = JSON.parse(fs.readFileSync(path.join(ROOT, "out", "durations.json"), "utf8"))
    .map(d => Math.round(d.dur * 1000) + GAP);

  fs.rmSync(FRAMES, { recursive: true, force: true });
  fs.mkdirSync(FRAMES, { recursive: true });

  const browser = await chromium.launch({
    executablePath: CHROME,
    headless: true,
    args: ["--hide-scrollbars", "--force-device-scale-factor=1", "--font-render-hinting=none"],
  });
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
  await page.goto(PAGE, { waitUntil: "load" });
  await page.evaluate(d => window.__setDurations(d), durs);

  // 采样点：每场景开头 1.4s 逐帧，最后一帧定格到本场景结束
  const shots = [];          // {t, dur} 单位 ms
  let acc = 0;
  for (const D of durs) {
    const m = Math.min(MOTION, D - 50);
    const ts = [];
    for (let t = 0; t <= m; t += STEP) ts.push(acc + t);
    if (ts[ts.length - 1] !== acc + m) ts.push(acc + m);
    for (let k = 0; k < ts.length; k++) {
      const dur = (k + 1 < ts.length) ? (ts[k + 1] - ts[k]) : (acc + D - ts[k]);
      shots.push({ t: ts[k], dur });
    }
    acc += D;
  }

  const list = [];
  let n = 0;
  for (const s of shots) {
    await page.evaluate(tt => window.__render(tt), s.t);
    const file = path.join(FRAMES, "f" + String(n++).padStart(5, "0") + ".png");
    await page.screenshot({ path: file });
    list.push({ file: path.basename(file), dur: +(s.dur / 1000).toFixed(3) });
  }

  fs.writeFileSync(path.join(ROOT, "out", "frames.json"), JSON.stringify(list, null, 1));
  console.log("帧数:", list.length, "总时长:", (acc / 1000).toFixed(1), "秒");
  await browser.close();
})();
