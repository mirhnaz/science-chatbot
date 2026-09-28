// Renders launch-video.html to launch-frames/ at 30 fps with headless Chrome
// (each frame drawn by render(t)), then joins frames and music.wav with
// ffmpeg into curio-launch.mp4. Run from this folder: node render-video.mjs
// (add --vertical for the 1080×1920 cut, curio-launch-vertical.mp4).
import { spawn, execFileSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const here = path.dirname(fileURLToPath(import.meta.url));
const frames = path.join(here, 'launch-frames');
const FPS = 30;
const vertical = process.argv.includes('--vertical');
const [W, H] = vertical ? [1080, 1920] : [1920, 1080];
const page = vertical ? 'launch-video-vertical.html' : 'launch-video.html';
const output = vertical ? 'curio-launch-vertical.mp4' : 'curio-launch.mp4';
rmSync(frames, { recursive: true, force: true });
mkdirSync(frames);
const chrome = spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', ['--headless=new', '--hide-scrollbars', '--allow-file-access-from-files', '--remote-debugging-port=9334', `--user-data-dir=${mkdtempSync(tmpdir() + '/curio-video-')}`, 'about:blank'], { stdio: 'ignore' });
const sleep = ms => new Promise(r => setTimeout(r, ms));
let version;
for (let i = 0; i < 50 && !version; i++) { await sleep(200); try { version = await (await fetch('http://127.0.0.1:9334/json/version')).json(); } catch {} }
const ws = new WebSocket(version.webSocketDebuggerUrl);
await new Promise(r => ws.addEventListener('open', r));
let id = 0; const pending = new Map();
ws.addEventListener('message', e => { const m = JSON.parse(e.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); } });
const send = (method, params = {}, sessionId) => new Promise(r => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params, sessionId })); });
try {
  const { result: { targetId } } = await send('Target.createTarget', { url: 'about:blank' });
  const { result: { sessionId } } = await send('Target.attachToTarget', { targetId, flatten: true });
  const s = (m, p) => send(m, p, sessionId);
  await s('Page.enable');
  await s('Emulation.setDeviceMetricsOverride', { width: W, height: H, deviceScaleFactor: 1, mobile: false });
  await s('Page.navigate', { url: 'file://' + path.join(here, page) + '?frames' });
  await sleep(1500);
  await s('Runtime.evaluate', { expression: 'document.fonts.ready.then(() => Promise.all([...document.images].map(i => i.decode())))', awaitPromise: true });
  const { result: { result: { value: duration } } } = await s('Runtime.evaluate', { expression: 'DURATION', returnByValue: true });
  const total = Math.round(duration * FPS);
  for (let f = 0; f < total; f++) {
    await s('Runtime.evaluate', { expression: `render(${f / FPS}); new Promise(r => requestAnimationFrame(() => r()))`, awaitPromise: true });
    const shot = await s('Page.captureScreenshot', { format: 'jpeg', quality: 92 });
    writeFileSync(path.join(frames, `${String(f).padStart(5, '0')}.jpg`), Buffer.from(shot.result.data, 'base64'));
    if (f % 150 === 0) console.log(`frame ${f}/${total}`);
  }
} finally { ws.close(); chrome.kill(); }
execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-framerate', String(FPS), '-i', path.join(frames, '%05d.jpg'), '-i', path.join(here, 'music.wav'),
  '-c:v', 'libx264', '-preset', 'slow', '-crf', '20', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '160k', '-shortest', '-movflags', '+faststart', path.join(here, output)], { stdio: 'inherit' });
rmSync(frames, { recursive: true, force: true });
console.log(`wrote ${output}`);
