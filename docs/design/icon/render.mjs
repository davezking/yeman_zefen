// Renders icon.html into every app icon PNG.
// Run from the repo root: node docs/design/icon/render.mjs
// Needs Playwright with Chromium (npm i -D playwright, or a global install).
import { chromium } from "playwright";
import { mkdirSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "../../..");
const src = pathToFileURL(join(here, "icon.html")).href;

const ios = join(root, "app/ios/Runner/Assets.xcassets/AppIcon.appiconset");
const res = join(root, "app/android/app/src/main/res");
const densities = { mdpi: 1, hdpi: 1.5, xhdpi: 2, xxhdpi: 3, xxxhdpi: 4 };

const jobs = [
  { out: join(here, "icon-1024.png"), size: 1024, layer: "full" },
  { out: join(here, "play-store-512.png"), size: 512, layer: "full" },
];
// iOS: every file named in the asset catalog, full bleed and opaque.
const contents = JSON.parse(readFileSync(join(ios, "Contents.json"), "utf8"));
for (const img of contents.images) {
  const size = Math.round(parseFloat(img.size) * parseInt(img.scale));
  jobs.push({ out: join(ios, img.filename), size, layer: "full", opaque: true });
}
// Android: 48dp legacy icon, plus 108dp adaptive layers.
for (const [d, k] of Object.entries(densities)) {
  const dir = join(res, `mipmap-${d}`);
  jobs.push({ out: join(dir, "ic_launcher.png"), size: 48 * k, layer: "round" });
  for (const layer of ["fg", "bg", "mono"]) {
    const name = { fg: "foreground", bg: "background", mono: "monochrome" }[layer];
    jobs.push({ out: join(dir, `ic_launcher_${name}.png`), size: 108 * k, layer });
  }
}

const browser = await chromium.launch();
const seen = new Set();
for (const job of jobs) {
  if (seen.has(job.out)) continue;
  seen.add(job.out);
  const page = await browser.newPage({ viewport: { width: job.size, height: job.size }, deviceScaleFactor: 1 });
  await page.goto(`${src}?layer=${job.layer}`);
  await page.evaluate(() => document.fonts.ready);
  mkdirSync(dirname(job.out), { recursive: true });
  await page.screenshot({ path: job.out, omitBackground: !job.opaque, scale: "css" });
  await page.close();
}
await browser.close();
console.log(`wrote ${seen.size} files`);
