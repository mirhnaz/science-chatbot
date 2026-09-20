import { test } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { createApp } from '../server.mjs';

async function listen(server) { await new Promise(r => server.listen(0, '127.0.0.1', r)); return `http://127.0.0.1:${server.address().port}`; }
async function close(server) { server.closeAllConnections(); await new Promise(r => server.close(r)); }
async function fixture(t, handler, options = {}) {
  const upstream = http.createServer(handler);
  const base = await listen(upstream);
  const app = createApp({ upstream: base, ...options });
  const url = await listen(app);
  t.after(async () => { await close(app); await close(upstream); });
  return { url, post: (body, headers = {}) => fetch(`${url}/api/chat`, { method: 'POST', headers: { 'Content-Type': 'application/json', ...headers }, body: JSON.stringify(body) }) };
}

test('question becomes a bounded Qwen request and only final content returns', async t => {
  let payload;
  const f = await fixture(t, async (req, res) => {
    let body = ''; for await (const c of req) body += c;
    payload = JSON.parse(body);
    assert.equal(req.url, '/api/chat');
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ message: { content: JSON.stringify({ answer: 'Gravity attracts objects with mass.', followUps: ['Why does the Moon orbit Earth?', 'How does gravity affect ocean tides?', 'Why do astronauts float in orbit?'] }), thinking: 'Not for the response panel.' } }));
  });
  const reply = await f.post({ question: '  What is gravity?  ', model: 'unrequested-model', messages: [] });
  assert.equal(reply.status, 200);
  const data = await reply.json();
  assert.equal(data.answer, 'Gravity attracts objects with mass.');
  assert.equal(data.thinking, undefined);
  assert.equal(data.followUps.length, 3);
  assert.equal(data.followUps[0], 'Why does the Moon orbit Earth?');
  assert.equal(payload.format.properties.followUps.minItems, 3);
  assert.equal(payload.format.properties.followUps.maxItems, 3);
  assert.equal(payload.model, 'qwen3:8b');
  assert.equal(payload.stream, false); assert.equal(payload.think, false);
  assert.equal(payload.messages[0].role, 'system');
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
  assert.equal((await fetch(`${f.url}/server.mjs`)).status, 404);
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
    assert.match((await reply.json()).error, /try your question again/);
  }
});
