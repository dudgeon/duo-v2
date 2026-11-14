import { chromium } from '/Users/geoff/repos/thinking-about-risk/node_modules/playwright-core/index.mjs';
const [,, html, png, w, h] = process.argv;
const b = await chromium.launch();
const p = await b.newPage({ viewport: { width: +w, height: +h }, deviceScaleFactor: 1 });
await p.goto('file://' + html);
const size = await p.evaluate(() => { const r = document.body.firstElementChild; return [r.scrollHeight, r.clientHeight, r.scrollWidth]; });
console.log('root scroll/client/width', size);
await p.screenshot({ path: png, fullPage: true });
await b.close();
