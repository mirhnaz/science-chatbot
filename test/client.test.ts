import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';

const flush = () => new Promise(resolve => setImmediate(resolve));
const sparks = (offset = 0) => Array.from({ length: 4 }, (_, i) => ({
  id: `topic-${offset + i}`, topic: `Topic ${i}`, icon: '🌱', question: `Why does plant ${offset + i} grow?`
}));
const reply = (answer = 'Gravity pulls objects together.', followUps = ['Why does the Moon orbit Earth?', 'What causes ocean tides?', 'How does gravity affect stars?']) =>
  ({ answer, followUps, elapsedMs: 10 });

// A small stand-in for the page: just the DOM features app.js uses.
class Element {
  id = ''; type = ''; hidden = false; disabled = false; value = ''; textContent = ''; className = ''; placeholder = ''; innerHTML = '';
  focused = false; children: Element[] = []; listeners: Record<string, (event?: unknown) => void> = {}; attributes: Record<string, string> = {};
  parent: Element | null = null;
  addEventListener(type: string, handler: (event?: unknown) => void) { this.listeners[type] = handler; }
  setAttribute(key: string, value: string) { this.attributes[key] = value; }
  focus() { this.focused = true; } scrollIntoView() {}
  // Like the real DOM, adding a child moves it out of its previous parent.
  private adopt(children: Element[]) {
    for (const child of children) {
      if (child.parent) child.parent.children = child.parent.children.filter(c => c !== child);
      child.parent = this;
    }
  }
  replaceChildren(...children: Element[]) { for (const old of this.children) old.parent = null; this.children = []; this.adopt(children); this.children = children; }
  append(...children: Element[]) { this.adopt(children); this.children.push(...children); }
}

/** Every element below `root` (depth first). */
function* walk(root: Element): Generator<Element> {
  for (const child of root.children) { yield child; yield* walk(child); }
}
const byClass = (root: Element, name: string) => [...walk(root)].filter(e => e.className.split(' ').includes(name));
const text = (root: Element): string => root.textContent + root.children.map(text).join('');

async function browser(stored?: string, storageBlocked = false) {
  const elements = new Map<string, Element>();
  const get = (id: string): Element => {
    let element = elements.get(id);
    if (!element) { element = new Element(); element.id = id; elements.set(id, element); }
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
  const body = new Element();
  const context = vm.createContext({
    document: {
      body,
      getElementById: (id: string) => get(id),
      createElement: () => new Element(),
      querySelectorAll: (selector: string) => {
        const names = selector.split(',').map(s => s.trim().replace(/^\./, ''));
        return [...elements.values()].flatMap(root => [...walk(root)]).filter(e => names.some(n => e.className.split(' ').includes(n)));
      }
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
  const trail = () => get('trail');
  return { get, requests, context, timers, body, trail, saved: () => saved };
}

test('a spark asks at once and starts a trail; the box moves to the dock', async () => {
  const b = await browser();
  assert.equal(b.body.attributes['data-view'], 'fresh');
  assert.equal(b.get('fresh').hidden, false);
  b.requests[0].complete({ suggestions: sparks() }); await flush();
  const cards = b.get('spark-grid').children;
  assert.equal(cards.length, 4);
  assert.equal(b.get('spark-chips').children.length, 3);
  cards[0].listeners.click();
  assert.equal(b.requests.length, 2, 'a spark asks immediately');
  assert.equal(JSON.parse(b.requests[1].options.body!).question, sparks()[0].question);
  assert.equal(b.body.attributes['data-view'], 'trail');
  assert.equal(b.get('trail').hidden, false);
  assert.equal(b.get('new-spark').hidden, false);
  assert.deepEqual(b.get('dock-compose').children, [b.get('question-form')], 'the question box moved to the dock');
  assert.equal(b.get('title').textContent, sparks()[0].question);
  assert.equal(b.get('subtitle').textContent, 'Thinking…');
  assert.ok(byClass(b.trail(), 'loading').length === 1);
  assert.ok(b.get('spark-chips').children.every(chip => chip.disabled), 'sparks wait for the answer');
  assert.equal(b.get('cancel').hidden, false);
  assert.match(text(b.trail()), /🌱 Topic 0/, 'the trail shows its spark topic');
  b.requests[1].complete(reply()); await flush();
  assert.equal(byClass(b.trail(), 'follow-up').length, 3);
  assert.equal(b.get('cancel').hidden, true);
  assert.match(byClass(b.trail(), 'answered-in')[0].textContent, /^Answered in \d+\.\d seconds$/);
});

test('Dive deeper adds a step, folds the previous one, and ignores double taps', async () => {
  const b = await browser();
  b.requests[0].complete({ suggestions: sparks() }); await flush();
  const first = vm.runInContext('ask("What is gravity?")', b.context);
  b.requests[1].complete(reply()); await first;
  const followUp = byClass(b.trail(), 'follow-up')[0];
  assert.equal(followUp.disabled, false);
  followUp.listeners.click();
  assert.equal(b.requests.length, 3);
  assert.equal(JSON.parse(b.requests[2].options.body!).question, 'Why does the Moon orbit Earth?');
  followUp.listeners.click();
  assert.equal(b.requests.length, 3, 'double taps must not start another request');
  const folded = byClass(b.trail(), 'step-folded');
  assert.equal(folded.length, 1, 'the earlier step folds');
  assert.match(text(folded[0]), /↳ Why does the Moon orbit Earth\?/, 'and shows the chosen follow-up');
  assert.equal(byClass(b.trail(), 'follow-up').length, 0, 'follow-ups hide while the next answer loads');
  b.requests[2].complete(reply('The Moon falls around Earth.')); await flush();
  assert.equal(b.get('subtitle').textContent, '2 steps');
  assert.equal(byClass(b.trail(), 'follow-up').length, 3);
  folded[0].listeners.click();
  assert.equal(byClass(b.trail(), 'step-folded').length, 0, 'a folded step opens again');
});

test('the question box asks, clears, and Stop gives the question back', async () => {
  const b = await browser();
  b.requests[0].complete({ suggestions: sparks() }); await flush();
  b.get('question').value = '  Why is the sky blue?  ';
  b.get('question').listeners.input();
  assert.equal(b.get('ask').disabled, false);
  b.get('question-form').listeners.submit({ preventDefault() {} });
  assert.equal(b.requests.length, 2);
  assert.equal(JSON.parse(b.requests[1].options.body!).question, 'Why is the sky blue?');
  assert.equal(b.get('question').value, '', 'the question moves into the trail');
  b.get('cancel').listeners.click(); await flush();
  assert.equal(b.requests[1].options.signal?.aborted, true);
  assert.equal(b.get('question').value, 'Why is the sky blue?');
  assert.equal(b.body.attributes['data-view'], 'fresh', 'an empty trail returns to the fresh screen');
  b.get('question').listeners.keydown({ key: 'Enter', shiftKey: false, isComposing: false, preventDefault() {} });
  assert.equal(b.requests.length, 3, 'Enter asks');
});

test('errors offer Try again, which asks the same question', async () => {
  const b = await browser();
  b.requests[0].complete({ suggestions: sparks() }); await flush();
  const answering = vm.runInContext('ask("Why do cats purr?")', b.context);
  b.requests[1].complete({ error: 'The science tutor is busy. Try again in a moment.' }, false);
  assert.equal((await answering).error, 'The science tutor is busy. Try again in a moment.');
  assert.match(text(b.trail()), /busy/);
  const again = [...walk(b.trail())].find(e => e.textContent === 'Try again')!;
  again.listeners.click();
  assert.equal(JSON.parse(b.requests[2].options.body!).question, 'Why do cats purr?');
  b.requests[2].complete(reply()); await flush();
  assert.equal(byClass(b.trail(), 'error').length, 0);
});

test('Ask your own starts an empty trail, and Undo brings the old one back', async () => {
  const b = await browser();
  b.requests[0].complete({ suggestions: sparks() }); await flush();
  const first = vm.runInContext('ask("What is gravity?")', b.context);
  b.requests[1].complete(reply()); await first;
  b.get('ask-own').listeners.click();
  assert.equal(b.body.attributes['data-view'], 'fresh');
  assert.deepEqual(b.get('fresh-compose').children, [b.get('question-form')]);
  assert.equal(b.get('undo').hidden, false);
  assert.equal(b.get('question').focused, false, 'no keyboard: the sparks stay visible');
  b.get('undo-button').listeners.click();
  assert.equal(b.body.attributes['data-view'], 'trail');
  assert.match(text(b.trail()), /Gravity pulls objects together/);
  assert.equal(b.get('undo').hidden, true);
});

test('right-click or long-press on a spark fills the box without asking', async () => {
  const b = await browser();
  b.requests[0].complete({ suggestions: sparks() }); await flush();
  let prevented = false;
  b.get('spark-grid').children[1].listeners.contextmenu({ preventDefault() { prevented = true; } });
  assert.equal(prevented, true);
  assert.equal(b.get('question').value, sparks()[1].question);
  assert.equal(b.get('question').focused, true);
  assert.equal(b.requests.length, 1, 'editing first never asks');
});

test('new sparks refresh once and persist only recent IDs', async () => {
  const b = await browser(JSON.stringify(['older-1']));
  assert.match(b.requests[0].url, /exclude=older-1/);
  b.requests[0].complete({ suggestions: sparks() }); await flush();
  assert.equal(b.get('spark-grid').attributes['aria-busy'], 'false');
  b.get('new-sparks').listeners.click(); b.get('new-sparks').listeners.click();
  assert.equal(b.requests.length, 2);
  assert.equal(b.get('new-sparks').disabled, true);
  const excluded = new URL(b.requests[1].url, 'http://localhost').searchParams.get('exclude')!.split(',');
  assert.deepEqual(excluded, ['older-1', ...sparks().map(i => i.id)]);
  b.requests[1].complete({ suggestions: sparks(4) }); await flush();
  assert.equal(b.get('new-sparks').disabled, false);
  assert.deepEqual(JSON.parse(b.saved()!), ['older-1', ...sparks().map(i => i.id), ...sparks(4).map(i => i.id)]);
  const nextPage = await browser(b.saved());
  assert.match(nextPage.requests[0].url, /topic-7/);
});

test('spark storage stays bounded and works when storage is blocked or corrupt', async () => {
  for (const [stored, blocked] of [['not JSON', false], ['[]', true], [JSON.stringify(Array.from({ length: 40 }, (_, i) => `old-${i}`)), false]] as const) {
    const b = await browser(stored, blocked);
    b.requests[0].complete({ suggestions: sparks() }); await flush();
    assert.equal(b.get('spark-grid').children.length, 4);
    b.get('dice').listeners.click();
    const excluded = new URL(b.requests[1].url, 'http://localhost').searchParams.get('exclude')!.split(',');
    assert.ok(excluded.length <= 40);
    assert.ok(excluded.includes('topic-0'));
  }
});

test('spark failures keep cards and typed text, allow retry, and time out', async () => {
  const b = await browser();
  b.get('question').value = 'My own question';
  b.requests[0].complete({}, false); await flush();
  assert.match(b.get('sparks-status').textContent, /type your own question/);
  assert.equal(b.get('new-sparks').disabled, false);
  b.get('new-sparks').listeners.click();
  b.requests[1].complete({ suggestions: sparks() }); await flush();
  const original = b.get('spark-grid').children;
  b.get('new-sparks').listeners.click();
  b.requests[2].complete({ suggestions: [sparks()[0]] }); await flush();
  assert.deepEqual(b.get('spark-grid').children.map(c => c.attributes['aria-label']), original.map(c => c.attributes['aria-label']));
  assert.equal(b.get('question').value, 'My own question');
  b.get('new-sparks').listeners.click();
  const timer = [...b.timers.values()].find(t => t.ms === 8000)!;
  timer.callback(); await flush();
  assert.equal(b.requests[3].options.signal?.aborted, true);
  assert.equal(b.get('new-sparks').disabled, false);
});

test('sparks arriving during an answer stay disabled until it finishes', async () => {
  const b = await browser();
  const answering = vm.runInContext('ask("Why is the sky blue?")', b.context);
  b.requests[0].complete({ suggestions: sparks() }); await flush();
  const chip = b.get('spark-chips').children[0];
  assert.equal(chip.disabled, true);
  chip.listeners.click(); b.get('dice').listeners.click();
  assert.equal(b.requests.length, 2, 'no new trail or refresh while answering');
  b.requests[1].complete(reply('Blue light scatters.', ['One?', 'Two?', 'Three?']));
  await answering; await flush();
  assert.equal(b.get('spark-chips').children[0].disabled, false);
  assert.equal(b.get('dice').disabled, false);
});
