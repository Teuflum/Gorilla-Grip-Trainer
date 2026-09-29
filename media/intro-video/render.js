// node render.js <worker> <workers> : renders a contiguous chunk of frames to seg<worker>.mp4
const { chromium } = require('playwright');
const { spawn } = require('child_process');
const FPS = 30;
const FF = process.env.FF || 'ffmpeg';
(async () => {
  const [wi, wn] = process.argv.slice(2).map(Number);
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM || undefined, args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const p = await b.newPage({ viewport: { width: 1000, height: 600 } });
  p.on('pageerror', e => { console.error('ERR', e.message); process.exit(1); });
  await p.goto('http://127.0.0.1:8123/index.html'); await p.waitForFunction(() => window.ready, null, { timeout: 180000 });
  const total = await p.evaluate(() => window.TOTAL);
  if (wi === 0) require('fs').writeFileSync('sfx.json', JSON.stringify(await p.evaluate(() => window.SFX)));
  const N = Math.ceil(total * FPS), per = Math.ceil(N / wn), f0 = wi * per, f1 = Math.min(N, f0 + per);
  const ff = spawn(FF, ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', '' + FPS, '-c:v', 'mjpeg', '-i', '-',
    '-c:v', 'libx264', '-preset', 'medium', '-crf', '18', '-pix_fmt', 'yuv420p', `seg${wi}.mp4`], { stdio: ['pipe', 'inherit', 'inherit'] });
  for (let f = f0; f < f1; f++) {
    const d = await p.evaluate(t => { renderAt(t); return document.getElementById('c').toDataURL('image/jpeg', 0.95); }, f / FPS);
    const buf = Buffer.from(d.slice(d.indexOf(',') + 1), 'base64');
    if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
    if ((f - f0) % 300 === 0) console.log(`w${wi}: ${f - f0}/${f1 - f0}`);
  }
  ff.stdin.end(); await new Promise(r => ff.on('close', r));
  await b.close(); console.log(`w${wi} done`);
})();
