import { test, type TestContext } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { setTimeout as delay } from 'node:timers/promises';
import { readFile } from 'node:fs/promises';
interface AppOptions {
  upstream?: string;
  model?: string;
  publicOrigin?: string;
  timeoutMs?: number;
  root?: string;
}

async function readObject(response: Response): Promise<Record<string, unknown>> {
  const value: unknown = await response.json();
  assert.ok(value && typeof value === 'object' && !Array.isArray(value));
  return value as Record<string, unknown>;
}

async function listen(server: http.Server) {
  await new Promise<void>(resolve => server.listen(0, '127.0.0.1', resolve));
  const address = server.address();
  assert.ok(address && typeof address !== 'string');
  return `http://127.0.0.1:${address.port}`;
}
async function close(server: http.Server) { server.closeAllConnections(); await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve())); }
async function fixture(t: TestContext, handler: http.RequestListener, options: AppOptions = {}) {
  const upstream = http.createServer(handler);
  const base = await listen(upstream);
  t.after(() => close(upstream));
  const child = spawn(process.env.RUST_SERVER_BIN || 'backend/target/debug/curio-server', [], {
    env: { ...process.env, HOST: '127.0.0.1', PORT: '0', ASSET_ROOT: options.root || process.cwd(),
      OLLAMA_BASE_URL: options.upstream || base, OLLAMA_MODEL: options.model || 'qwen3:8b',
      PUBLIC_ORIGIN: options.publicOrigin || '', OLLAMA_TIMEOUT_MS: String(options.timeoutMs ?? 120000) },
    stdio: ['ignore', 'pipe', 'pipe']
  });
  const exited = once(child, 'exit');
  const stop = async () => {
    if (child.exitCode !== null || child.signalCode !== null) return;
    child.kill('SIGTERM');
    const timer = setTimeout(() => child.kill('SIGKILL'), 3000);
    try { await exited; } finally { clearTimeout(timer); }
    assert.equal(child.exitCode, 0, 'Rust exits gracefully');
  };
  t.after(stop);
  const url = await new Promise<string>((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Rust server did not start')), 5000);
    let output = '';
    let errors = '';
    child.stderr.on('data', data => { errors += String(data); });
    child.on('error', error => { clearTimeout(timer); reject(error); });
    child.on('exit', () => { clearTimeout(timer); reject(new Error(`Rust exited: ${errors}`)); });
    child.stdout.on('data', data => {
      output += String(data);
      const match = output.match(/ready at (http:\/\/[^\s]+)/);
      if (match) { clearTimeout(timer); resolve(match[1]); }
    });
  });
  return { url, stop, post: (body: unknown, headers: Record<string, string> = {}) => fetch(`${url}/api/chat`, { method: 'POST', headers: { 'Content-Type': 'application/json', ...headers }, body: JSON.stringify(body) }) };
}

test('compiled server serves browser assets from the deployment layout', async t => {
  const f = await fixture(t, (_, res) => { res.end('{}'); });
  const page = await fetch(f.url);
  assert.equal(page.status, 200);
  assert.match(page.headers.get('content-type') || '', /text\/html/);
  assert.match(await page.text(), /src="\/app.js"/);
  const script = await fetch(`${f.url}/app.js`);
  assert.equal(script.status, 200);
  assert.match(script.headers.get('content-type') || '', /text\/javascript/);
  assert.match(await script.text(), /async function ask\(/);
  assert.equal((await fetch(`${f.url}/styles.css`)).status, 200);
  assert.equal((await fetch(`${f.url}/science-banner.png`)).status, 200);
  const health = await fetch(`${f.url}/healthz`);
  assert.equal(health.status, 200);
  assert.deepEqual(await health.json(), { status: 'ok' });
});

test('question becomes a bounded Qwen request and only final content returns', async t => {
  let payload: {
    format: { properties: { followUps: { minItems: number; maxItems: number } } };
    model: string;
    stream: boolean;
    think: boolean;
    messages: { role: string; content: string }[];
  } | undefined;
  const f = await fixture(t, async (req, res) => {
    let body = ''; for await (const c of req) body += c;
    payload = JSON.parse(body);
    assert.equal(req.url, '/api/chat');
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ message: { content: JSON.stringify({ answer: 'Gravity attracts objects with mass.', followUps: ['Why does the Moon orbit Earth?', 'How does gravity affect ocean tides?', 'Why do astronauts float in orbit?'] }), thinking: 'Not for the response panel.' } }));
  });
  const reply = await f.post({ question: '  What is gravity?  ', model: 'unrequested-model', messages: [] });
  assert.equal(reply.status, 200);
  const data = await readObject(reply);
  assert.equal(data.answer, 'Gravity attracts objects with mass.');
  assert.equal(data.thinking, undefined);
  assert.ok(Array.isArray(data.followUps));
  assert.equal(data.followUps.length, 3);
  assert.equal(data.followUps[0], 'Why does the Moon orbit Earth?');
  assert.ok(payload);
  assert.equal(payload.format.properties.followUps.minItems, 3);
  assert.equal(payload.format.properties.followUps.maxItems, 3);
  assert.equal(payload.model, 'qwen3:8b');
  assert.equal(payload.stream, false); assert.equal(payload.think, false);
  assert.equal(payload.messages[0].role, 'system');
  const prompt = await readFile('backend/src/tutor.txt', 'utf8');
  assert.equal(payload.messages[0].content, prompt);
  assert.deepEqual(payload.format, JSON.parse(await readFile('backend/src/reply-schema.json', 'utf8')));
  assert.equal(payload.messages[1].content, 'What is gravity?');
});
test('blank, oversized, malformed and cross-origin requests do not reach Ollama', async t => {
  let calls = 0;
  const f = await fixture(t, (_, res) => { calls++; res.end('{}'); });
  assert.equal((await f.post({ question: ' ' })).status, 400);
  assert.equal((await f.post({ question: 'x'.repeat(2001) })).status, 400);
  assert.equal((await f.post({ question: 'x'.repeat(9000) })).status, 413);
  assert.equal((await f.post({ question: 'Gravity?' }, { Origin: 'https://another-site.example' })).status, 403);
  const malformed = await fetch(`${f.url}/api/chat`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{' });
  assert.equal(malformed.status, 400); assert.equal(calls, 0);
  for (const path of ['/backend/src/main.rs', '/src/client/app.ts', '/test/server.test.ts', '/deploy/Caddyfile']) {
    assert.equal((await fetch(`${f.url}${path}`)).status, 404);
  }
});
test('upstream errors and timeouts give retryable messages', async t => {
  const unavailable = await fixture(t, (_, res) => { res.writeHead(500); res.end('private diagnostic'); });
  const error = await unavailable.post({ question: 'Gravity?' });
  assert.equal(error.status, 502); assert.doesNotMatch(await error.text(), /private diagnostic/);
  const slow = await fixture(t, () => {}, { timeoutMs: 25 });
  assert.equal((await slow.post({ question: 'Gravity?' })).status, 504);
});
test('empty model content does not appear as success', async t => {
  const f = await fixture(t, (_, res) => { res.end(JSON.stringify({ message: { content: '' } })); });
  assert.equal((await f.post({ question: 'Gravity?' })).status, 502);
});

test('malformed answers and invalid suggestions return a retryable error', async t => {
  for (const content of [
    'not JSON',
    JSON.stringify({ answer: 'Hello', followUps: ['One?', 'Two?'] }),
    JSON.stringify({ answer: 'Hello', followUps: ['One?', 'one?', 'Three?'] }),
    JSON.stringify({ answer: 'Hello', followUps: ['One?', 42, 'Three?'] }),
    JSON.stringify({ answer: 'Hello', followUps: ['One?', 'Two?', 'x'.repeat(181)] }),
    JSON.stringify({ answer: ' ', followUps: ['One?', 'Two?', 'Three?'] })
  ]) {
    const f = await fixture(t, (_, res) => res.end(JSON.stringify({ message: { content } })));
    const reply = await f.post({ question: 'What is gravity?' });
    assert.equal(reply.status, 502);
    const data = await readObject(reply);
    assert.equal(typeof data.error, 'string');
    assert.match(data.error as string, /try your question again/);
  }
});

const validReply = { answer: '  Gravity attracts mass.  ', followUps: [' One? ', 'Two?', 'Three?'] };
function answer(res: http.ServerResponse) {
  res.end(JSON.stringify({ message: { content: JSON.stringify(validReply) } }));
}
async function until(predicate: () => boolean) {
  const deadline = Date.now() + 3000;
  while (!predicate()) {
    assert.ok(Date.now() < deadline, 'condition reached before deadline');
    await delay(10);
  }
}

test('asset allowlist preserves bytes, MIME types, query handling and security headers', async t => {
  const f = await fixture(t, (_, res) => answer(res));
  const files = [
    ['/', 'public/index.html', 'text/html; charset=utf-8'],
    ['/theme.js', 'build/client/theme.js', 'text/javascript; charset=utf-8'],
    ['/app.js', 'build/client/app.js', 'text/javascript; charset=utf-8'],
    ['/styles.css', 'public/styles.css', 'text/css; charset=utf-8'],
    ['/science-banner.png', 'public/science-banner.png', 'image/png'],
    ['/favicon.ico', 'public/favicon.ico', 'image/vnd.microsoft.icon'],
    ['/favicon-32.png', 'public/favicon-32.png', 'image/png'],
    ['/apple-touch-icon.png', 'public/apple-touch-icon.png', 'image/png'],
    ['/icon-192.png', 'public/icon-192.png', 'image/png'],
    ['/icon-512.png', 'public/icon-512.png', 'image/png'],
    ['/site.webmanifest', 'public/site.webmanifest', 'application/manifest+json']
  ];
  for (const [route, file, mime] of files) {
    const res = await fetch(f.url + route + '?v=1');
    assert.equal(res.status, 200);
    assert.equal(res.headers.get('content-type'), mime);
    assert.equal(res.headers.get('cache-control'), 'no-cache');
    assert.deepEqual(Buffer.from(await res.arrayBuffer()), await readFile(file));
  }
  for (const [path, method, status] of [['/healthz', 'GET', 200], ['/api/chat', 'GET', 405], ['/no', 'GET', 404], ['/', 'HEAD', 404], ['/healthz', 'POST', 404]] as const) {
    const res = await fetch(f.url + path, { method });
    assert.equal(res.status, status);
    assert.equal(res.headers.get('cache-control'), 'no-store');
    assert.equal(res.headers.get('x-content-type-options'), 'nosniff');
    assert.equal(res.headers.get('referrer-policy'), 'no-referrer');
    assert.equal(res.headers.get('content-security-policy'), "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'");
    if (status === 405) {
      assert.equal(res.headers.get('allow'), 'POST');
      assert.deepEqual(await res.json(), { error: 'Use POST.' });
    }
  }
  for (const path of ['/backend/src/http.rs', '/%2e%2e/package.json', '/public/index.html', '/app.js/extra']) {
    assert.equal((await fetch(f.url + path)).status, 404);
  }
});

test('JSON boundary preserves UTF-16 lengths, trimming and content types', async t => {
  const questions: string[] = [];
  const f = await fixture(t, async (req, res) => {
    let body = ''; for await (const chunk of req) body += chunk;
    questions.push(JSON.parse(body).messages[1].content);
    answer(res);
  });
  for (const body of [null, [], 42, 'question', {}, { question: false }, { question: [] }]) {
    const res = await f.post(body);
    assert.equal(res.status, 400);
    assert.deepEqual(await res.json(), { error: 'Enter a question between 1 and 2,000 characters.' });
  }
  assert.equal((await f.post({ question: '🚀'.repeat(1000) })).status, 200);
  assert.equal((await f.post({ question: '🚀'.repeat(1001) })).status, 400);
  const res = await f.post({ question: '\uFEFF Why? \uFEFF' }, { 'Content-Type': 'Application/JSON;charset=utf-8' });
  assert.equal(res.status, 200);
  assert.equal(questions.at(-1), 'Why?');
  const data = await readObject(res);
  assert.equal(data.answer, validReply.answer.trim());
  assert.deepEqual(data.followUps, ['One?', 'Two?', 'Three?']);
  assert.equal(typeof data.elapsedMs, 'number');
  assert.ok((data.elapsedMs as number) >= 0);
  for (const type of ['text/plain', 'application/jsonx', 'application/json ;charset=utf-8', '']) {
    const res = await f.post({ question: 'Why?' }, { 'Content-Type': type });
    assert.equal(res.status, 415);
    assert.deepEqual(await res.json(), { error: 'Send a JSON question.' });
  }
});

test('configured public origin and request-host fallback preserve browser checks', async t => {
  const f = await fixture(t, (_, res) => answer(res));
  assert.equal((await f.post({ question: 'Why?' }, { Origin: f.url })).status, 200);
  assert.equal((await f.post({ question: 'Why?' }, { Origin: 'null' })).status, 403);
  const publicApp = await fixture(t, (_, res) => answer(res), { publicOrigin: 'https://science.example' });
  assert.equal((await publicApp.post({ question: 'Why?' }, { Origin: 'https://science.example' })).status, 200);
  assert.equal((await publicApp.post({ question: 'Why?' }, { Origin: publicApp.url })).status, 403);
  assert.equal((await publicApp.post({ question: 'Why?' })).status, 200);
});

test('8 KiB body limit applies to streamed bodies and counts bytes', async t => {
  let calls = 0;
  const f = await fixture(t, (_, res) => { calls++; answer(res); });
  for (const size of [8192, 8193]) {
    const prefix = '{"question":"Why?","extra":"';
    const suffix = '"}';
    const body = prefix + 'x'.repeat(size - prefix.length - suffix.length) + suffix;
    const response = await new Promise<{ status: number; body: string }>((resolve, reject) => {
      const req = http.request(f.url + '/api/chat', { method: 'POST', headers: { 'Content-Type': 'application/json' } }, res => {
        let text = ''; res.on('data', c => { text += c; });
        res.on('end', () => resolve({ status: res.statusCode!, body: text }));
      });
      req.on('error', reject);
      req.write(body.slice(0, 4000)); req.end(body.slice(4000));
    });
    assert.equal(response.status, size === 8192 ? 200 : 413);
    if (size > 8192) assert.deepEqual(JSON.parse(response.body), { error: 'Please ask a shorter question.' });
  }
  assert.equal(calls, 1);
});

test('two active requests reject a third immediately and release slots after success', async t => {
  const pending: http.ServerResponse[] = [];
  const f = await fixture(t, (_, res) => { pending.push(res); });
  const first = f.post({ question: 'One?' });
  const second = f.post({ question: 'Two?' });
  await until(() => pending.length === 2);
  const third = await f.post({ question: 'Three?' });
  assert.equal(third.status, 429);
  assert.deepEqual(await third.json(), { error: 'The science tutor is busy. Try again in a moment.' });
  assert.equal(pending.length, 2);
  pending.forEach(answer);
  assert.equal((await first).status, 200);
  assert.equal((await second).status, 200);
  const fourth = f.post({ question: 'Four?' });
  await until(() => pending.length === 3);
  answer(pending[2]);
  assert.equal((await fourth).status, 200);
});

test('client disconnect closes upstream sockets and returns both permits', async t => {
  let calls = 0;
  let closed = 0;
  const f = await fixture(t, (req, res) => {
    calls++;
    if (calls > 2) { answer(res); return; }
    req.resume();
    res.on('close', () => { closed++; });
  });
  const requests = [1, 2].map(() => {
    const req = http.request(f.url + '/api/chat', { method: 'POST', headers: { 'Content-Type': 'application/json' } });
    req.on('error', () => {});
    req.end(JSON.stringify({ question: 'Wait?' }));
    t.after(() => req.destroy());
    return req;
  });
  await until(() => calls === 2);
  assert.equal((await f.post({ question: 'Busy?' })).status, 429);
  requests.forEach(req => req.destroy());
  await until(() => closed === 2);
  assert.equal((await f.post({ question: 'Available?' })).status, 200);
});

test('deadline covers response body reads and frees capacity on timeout and error', async t => {
  let calls = 0;
  let closed = 0;
  const f = await fixture(t, (req, res) => {
    calls++;
    req.resume();
    if (calls <= 2) {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.write('{"message":');
      res.on('close', () => { closed++; });
    } else if (calls === 3) { res.writeHead(404); res.end('secret'); }
    else if (calls === 4) { res.end('invalid JSON'); }
    else answer(res);
  }, { timeoutMs: 100 });
  const responses = await Promise.all([f.post({ question: 'One?' }), f.post({ question: 'Two?' })]);
  for (const res of responses) {
    assert.equal(res.status, 504);
    assert.deepEqual(await res.json(), { error: 'That answer took too long. Try a shorter question.' });
  }
  await until(() => closed === 2);
  const missing = await f.post({ question: 'Three?' });
  assert.equal(missing.status, 502);
  assert.deepEqual(await missing.json(), { error: 'The science model is not available. Ask an adult to check the tutor computer.' });
  assert.equal((await f.post({ question: 'Four?' })).status, 502);
  assert.equal((await f.post({ question: 'Five?' })).status, 200);
});

test('Rust shutdown cancels in-flight model calls and exits promptly', async t => {
  let calls = 0;
  let closed = 0;
  const f = await fixture(t, (req, res) => {
    calls++; req.resume(); res.on('close', () => { closed++; });
  });
  const response = f.post({ question: 'Wait?' });
  await until(() => calls === 1);
  await f.stop();
  assert.equal((await response).status, 503);
  await until(() => closed === 1);
});

test('upstream connection failure returns the friendly offline error and releases capacity', async t => {
  const f = await fixture(t, req => req.socket.destroy());
  for (let attempt = 0; attempt < 3; attempt++) {
    const res = await f.post({ question: 'Why?' });
    assert.equal(res.status, 502);
    assert.deepEqual(await res.json(), { error: 'The science tutor is offline. Ask an adult to check the tutor computer and connection.' });
  }
});

test('Rust rejects ill-formed Unicode JSON explicitly and handles missing assets', async t => {
  let calls = 0;
  const f = await fixture(t, (_, res) => { calls++; answer(res); }, { root: '/nonexistent/curio-test-assets' });
  const missing = await fetch(f.url);
  assert.equal(missing.status, 500);
  assert.deepEqual(await missing.json(), { error: 'The page could not be loaded.' });
  const invalid = await fetch(f.url + '/api/chat', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{"question":"\\ud800"}' });
  assert.equal(invalid.status, 400);
  assert.deepEqual(await invalid.json(), { error: 'The question could not be read. Please try again.' });
  assert.equal(calls, 0);
});

test('Rust shutdown also closes an unfinished request body', async t => {
  const f = await fixture(t, (_, res) => answer(res));
  const req = http.request(f.url + '/api/chat', { method: 'POST', headers: { 'Content-Type': 'application/json' } });
  req.on('error', () => {});
  t.after(() => req.destroy());
  req.write('{');
  await delay(30);
  await f.stop();
});

test('starter suggestions rotate across four topics without calling Ollama', async t => {
  let calls = 0;
  const f = await fixture(t, (_, res) => { calls++; answer(res); });
  const bank: { id: string; topic: string; icon: string; question: string }[] = JSON.parse(await readFile('backend/data/questions.json', 'utf8'));
  let recent: string[] = [];
  for (let batch = 0; batch < 20; batch++) {
    const res = await fetch(`${f.url}/api/suggestions?exclude=${encodeURIComponent(recent.join(','))}`);
    assert.equal(res.status, 200);
    assert.equal(res.headers.get('cache-control'), 'no-store');
    assert.equal(res.headers.get('x-content-type-options'), 'nosniff');
    const data = await res.json() as { suggestions: typeof bank };
    assert.equal(data.suggestions.length, 4);
    assert.equal(new Set(data.suggestions.map(q => q.topic)).size, 4);
    for (const q of data.suggestions) {
      assert.deepEqual(q, bank.find(item => item.id === q.id));
      assert.ok(!recent.includes(q.id));
    }
    recent = [...recent, ...data.suggestions.map(q => q.id)].slice(-40);
  }
  assert.equal(calls, 0);
  const wrongMethod = await fetch(f.url + '/api/suggestions', { method: 'POST' });
  assert.equal(wrongMethod.status, 405);
  assert.equal(wrongMethod.headers.get('allow'), 'GET');
  assert.equal((await fetch(f.url + '/api/suggestions?exclude=' + Array(41).fill('space-1').join(','))).status, 400);
  assert.equal((await fetch(f.url + '/api/suggestions?exclude=' + 'x'.repeat(65))).status, 400);
  assert.equal((await fetch(f.url + '/api/suggestions?exclude=' + 'x'.repeat(3001))).status, 400);
});
