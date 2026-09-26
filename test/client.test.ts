import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';

const flush = () => new Promise(resolve => setImmediate(resolve));
const starters = (offset = 0) => Array.from({ length: 4 }, (_, i) => ({
  id: `topic-${offset + i}`, topic: `Topic ${i}`, icon: '🌱', question: `Why does plant ${offset + i} grow?`
}));

async function browser(stored?: string, storageBlocked = false) {
  class Element {
    hidden = false; disabled = false; value = ''; textContent = ''; className = ''; focused = false;
    children: Element[] = []; listeners: Record<string, () => void> = {}; attributes: Record<string, string> = {};
    addEventListener(type: string, handler: () => void) { this.listeners[type] = handler; }
    setAttribute(key: string, value: string) { this.attributes[key] = value; }
    setCustomValidity() {} focus() { this.focused = true; } scrollIntoView() {}
    replaceChildren(...children: Element[]) { this.children = children; }
    append(...children: Element[]) { this.children.push(...children); }
  }
  const elements = new Map<string, Element>();
  const get = (id: string): Element => {
    let element = elements.get(id);
    if (!element) { element = new Element(); elements.set(id, element); }
    return element;
  };
  interface PendingRequest {
    url: string;
    options: { body?: string; signal?: AbortSignal };
    complete: (body: unknown, ok?: boolean) => void;
  }
  const requests: PendingRequest[] = [];
  const timers = new Map<number, { callback: () => void; ms: number }>();
  let timerId = 0;
  let saved = stored;
  const context = vm.createContext({
    document: {
      getElementById: get, createElement: () => new Element(),
      querySelectorAll: (selector: string) => [
        ...(selector.includes('.follow-up') ? get('follow-up-list').children : []),
        ...(selector.includes('.topic') ? get('topic-grid').children : [])
      ]
    },
    window: { addEventListener() {}, matchMedia: () => ({ matches: false }) },
    sessionStorage: {
      getItem() { if (storageBlocked) throw new Error('Storage blocked'); return saved ?? null; },
      setItem(_key: string, value: string) { if (storageBlocked) throw new Error('Storage blocked'); saved = value; }
    },
    AbortController,
    setTimeout(callback: () => void, ms: number) { const id = ++timerId; timers.set(id, { callback, ms }); return id; },
    clearTimeout(id: number) { timers.delete(id); },
    fetch: (url: string, options: PendingRequest['options']) => new Promise((resolve, reject) => {
      requests.push({ url, options, complete: (body, ok = true) => resolve({ ok, json: async () => body }) });
      options.signal?.addEventListener('abort', () => reject(new Error('Aborted')));
    })
  });
  vm.runInContext(await readFile(new URL('../client/app.js', import.meta.url), 'utf8'), context);
  return { get, requests, context, timers, saved: () => saved };
}

test('follow-up buttons submit their question and clear while the next answer loads', async () => {
  const { get, requests, context } = await browser();
  requests[0].complete({ suggestions: starters() }); await flush();
  const followUps = ['Why does the Moon orbit Earth?', 'What causes ocean tides?', 'How does gravity affect stars?'];
  const reply = { answer: 'Gravity pulls objects together.', followUps, elapsedMs: 10 };
  const first = vm.runInContext('ask("What is gravity?")', context);
  assert.equal(get('surprise').disabled, true);
  assert.ok(get('topic-grid').children.every(button => button.disabled));
  requests[1].complete(reply); await first;
  assert.equal(get('follow-ups').hidden, false);
  assert.equal(get('follow-up-list').children.length, 3);
  const button = get('follow-up-list').children[0];
  assert.equal(button.textContent, followUps[0]);
  assert.equal(button.disabled, false);
  button.listeners.click();
  assert.equal(requests.length, 3);
  assert.equal(JSON.parse(requests[2].options.body!).question, followUps[0]);
  assert.equal(get('follow-ups').hidden, true);
  assert.equal(get('follow-up-list').children.length, 0);
  assert.equal(get('ask').disabled, true);
  button.listeners.click();
  assert.equal(requests.length, 3, 'double clicks must not start another request');
  requests[2].complete(reply); await flush();
  assert.equal(get('asked-question').textContent, followUps[0]);
  assert.equal(get('follow-up-list').children.length, 3);
  assert.equal(get('ask').disabled, false);
});

test('starter cards fill without submitting, refresh once, and persist only recent IDs', async () => {
  const b = await browser(JSON.stringify(['older-1']));
  assert.match(b.requests[0].url, /exclude=older-1/);
  const items = starters();
  b.requests[0].complete({ suggestions: items }); await flush();
  assert.equal(b.get('topic-grid').children.length, 4);
  assert.equal(b.get('topic-grid').attributes['aria-busy'], 'false');
  const card = b.get('topic-grid').children[0];
  assert.equal(card.children[1].textContent, items[0].question);
  card.listeners.click();
  assert.equal(b.get('question').value, items[0].question);
  assert.equal(b.get('question').focused, true);
  assert.equal(b.requests.length, 1, 'a starter never auto-submits a model request');
  b.get('surprise').listeners.click(); b.get('surprise').listeners.click();
  assert.equal(b.requests.length, 2);
  assert.equal(b.get('surprise').disabled, true);
  const excluded = new URL(b.requests[1].url, 'http://localhost').searchParams.get('exclude')!.split(',');
  assert.deepEqual(excluded, ['older-1', ...items.map(i => i.id)]);
  b.requests[1].complete({ suggestions: starters(4) }); await flush();
  assert.equal(b.get('surprise').disabled, false);
  assert.equal(b.get('question').value, items[0].question, 'refresh does not overwrite a draft');
  assert.deepEqual(JSON.parse(b.saved()!), ['older-1', ...starters().map(i => i.id), ...starters(4).map(i => i.id)]);
  const nextPage = await browser(b.saved());
  assert.match(nextPage.requests[0].url, /topic-7/);
  nextPage.requests[0].complete({ suggestions: starters(8) }); await flush();
});

test('starter storage stays bounded and works when storage is blocked or corrupt', async () => {
  for (const [stored, blocked] of [['not JSON', false], ['[]', true], [JSON.stringify(Array.from({ length: 40 }, (_, i) => `old-${i}`)), false]] as const) {
    const b = await browser(stored, blocked);
    b.requests[0].complete({ suggestions: starters() }); await flush();
    assert.equal(b.get('topic-grid').children.length, 4);
    b.get('surprise').listeners.click();
    const excluded = new URL(b.requests[1].url, 'http://localhost').searchParams.get('exclude')!.split(',');
    assert.ok(excluded.length <= 40);
    assert.ok(excluded.includes('topic-0'));
    b.requests[1].complete({ suggestions: starters(4) }); await flush();
  }
});

test('suggestion failures preserve cards and typed text, allow retry, and time out', async () => {
  const b = await browser();
  b.get('question').value = 'My own question';
  b.requests[0].complete({}, false); await flush();
  assert.match(b.get('suggestions-status').textContent, /type your own question/);
  assert.equal(b.get('surprise').disabled, false);
  b.get('surprise').listeners.click();
  b.requests[1].complete({ suggestions: starters() }); await flush();
  const original = b.get('topic-grid').children;
  b.get('surprise').listeners.click();
  b.requests[2].complete({ suggestions: [starters()[0]] }); await flush();
  assert.equal(b.get('topic-grid').children, original);
  assert.equal(b.get('question').value, 'My own question');
  b.get('surprise').listeners.click();
  const timer = [...b.timers.values()].find(t => t.ms === 8000)!;
  timer.callback(); await flush();
  assert.equal(b.requests[3].options.signal?.aborted, true);
  assert.equal(b.get('surprise').disabled, false);
  assert.equal(b.get('topic-grid').children, original);
});

test('suggestions finishing during a chat remain disabled until the answer arrives', async () => {
  const b = await browser();
  const answering = vm.runInContext('ask("Why is the sky blue?")', b.context);
  b.requests[0].complete({ suggestions: starters() }); await flush();
  assert.equal(b.get('surprise').disabled, true);
  const card = b.get('topic-grid').children[0];
  assert.equal(card.disabled, true);
  card.listeners.click(); b.get('surprise').listeners.click();
  assert.equal(b.requests.length, 2);
  assert.equal(b.get('question').value, 'Why is the sky blue?');
  b.requests[1].complete({ answer: 'Blue light scatters.', followUps: ['One?', 'Two?', 'Three?'], elapsedMs: 1 });
  await answering;
  assert.equal(card.disabled, false);
  assert.equal(b.get('surprise').disabled, false);
});
