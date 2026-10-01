// 把 web/cover.html 渲染成 1920x1080 封面图
const path = require("path");
const { chromium } = require("playwright-core");
const ROOT = path.resolve(__dirname, "..");
const PAGE = "file:///" + path.join(ROOT, "web", "cover.html").split(path.sep).join("/");
const CHROME = "C:/Program Files/Google/Chrome/Application/chrome.exe";
(async () => {
  const b = await chromium.launch({ executablePath: CHROME, headless: true,
    args: ["--hide-scrollbars", "--force-device-scale-factor=1"] });
  const p = await b.newPage({ viewport: { width: 1920, height: 1080 } });
  await p.goto(PAGE, { waitUntil: "load" });
  await p.screenshot({ path: path.join(ROOT, "out", "cover.png") });
  const over = await p.evaluate(() => document.body.scrollHeight > 1080 || document.body.scrollWidth > 1920);
  console.log("封面已生成 out/cover.png，溢出:", over);
  await b.close();
})();
