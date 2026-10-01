// 布局体检：逐场景检查是否溢出、代码行是否超宽
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright-core");
const ROOT = path.resolve(__dirname, "..");
const PAGE = "file:///" + path.join(ROOT, "web", "index.html").replace(/\\/g, "/");
const CHROME = "C:/Program Files/Google/Chrome/Application/chrome.exe";

(async () => {
  const durs = JSON.parse(fs.readFileSync(path.join(ROOT, "out", "durations.json"), "utf8"))
    .map(d => Math.round(d.dur * 1000) + 300);
  const browser = await chromium.launch({ executablePath: CHROME, headless: true,
    args: ["--hide-scrollbars", "--force-device-scale-factor=1"] });
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
  await page.goto(PAGE, { waitUntil: "load" });
  await page.evaluate(d => window.__setDurations(d), durs);

  let acc = 0, bad = 0;
  for (let i = 0; i < durs.length; i++) {
    await page.evaluate(t => window.__render(t), acc + 1500);
    acc += durs[i];
    const r = await page.evaluate(() => {
      const sc = document.querySelector('.scene.on');
      const grid = document.getElementById('grid');
      const out = { id: null, h: 0, over: [], wide: [] };
      out.h = grid.scrollHeight;
      sc.querySelectorAll('.left, .right, .code, .term, .notes, .dgwrap').forEach(n => {
        const pr = n.parentElement;
        if (n.scrollHeight > pr.clientHeight + 2) out.over.push(n.className + ' h=' + n.scrollHeight + '>' + pr.clientHeight);
      });
      sc.querySelectorAll('.cl').forEach(n => {
        const w = n.querySelector('.src') ? n.querySelector('.src').scrollWidth : 0;
        const box = n.clientWidth;
        if (w > box - 70) out.wide.push(w + '/' + (box - 70) + ' :: ' + n.textContent.trim().slice(0, 46));
      });
      sc.querySelectorAll('.ol').forEach(n => {
        if (n.scrollWidth > n.clientWidth + 2) out.wide.push('OUT ' + n.scrollWidth + '/' + n.clientWidth + ' :: ' + n.textContent.slice(0, 40));
      });
      if (document.body.scrollHeight > 1080) out.over.push('body h=' + document.body.scrollHeight);
      return out;
    });
    const tag = (r.over.length || r.wide.length) ? 'BAD ' : 'ok  ';
    if (tag === 'BAD ') bad++;
    console.log(tag + 'scene ' + i + ' gridH=' + r.h + ' ' + JSON.stringify(r.over.concat(r.wide)).slice(0, 400));
  }
  console.log(bad ? ('有 ' + bad + ' 个场景需要调整') : '全部场景布局正常');
  await browser.close();
})();
