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

async function browser(stored?: string, storageBlocked = false, local: Record<string, string> = {}) {
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
    localStorage: {
      getItem(key: string) { if (storageBlocked) throw new Error('Storage blocked'); return local[key] ?? null; },
      setItem(key: string, value: string) { if (storageBlocked) throw new Error('Storage blocked'); local[key] = value; }
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
  return { get, requests, context, timers, body, trail, local, saved: () => saved };
}

/** Answers the latest request and waits for the page to update. */
async function answerLatest(b: Awaited<ReturnType<typeof browser>>, body: unknown = reply()) {
  b.requests[b.requests.length - 1].complete(body); await flush();
}

test('a spark asks at once and opens its trail', async () => {
  const b = await browser();
  assert.equal(b.body.attributes['data-view'], 'home');
  assert.equal(b.get('home').hidden, false);
  assert.equal(b.get('resume').hidden, true, 'no trail to continue yet');
  b.requests[0].complete({ suggestions: sparks() }); await flush();
  const cards = b.get('spark-grid').children;
  assert.equal(cards.length, 4);
  assert.ok(cards[0].className.includes('spark-card cat-space'), 'unknown topics use the Space colours');
  cards[0].listeners.click();
  assert.equal(b.requests.length, 2, 'a spark asks immediately');
  assert.equal(JSON.parse(b.requests[1].options.body!).question, sparks()[0].question);
  assert.equal(b.body.attributes['data-view'], 'trail');
  assert.equal(b.get('trail-screen').hidden, false);
  assert.equal(b.get('home').hidden, true);
  assert.equal(b.get('trail-name').textContent, 'Topic 0', 'the trail is named after its spark');
  assert.equal(b.get('trail-detail').textContent, 'Thinking…');
  assert.equal(b.get('question').placeholder, 'Ask more about topic 0…');
  assert.ok(byClass(b.trail(), 'loading').length === 1);
  assert.ok(b.get('spark-grid').children.every(card => card.disabled), 'sparks wait for the answer');
  assert.equal(b.get('cancel').hidden, false);
  await answerLatest(b);
  assert.equal(b.get('trail-detail').textContent, 'Trail · Step 1');
  assert.equal(byClass(b.trail(), 'follow-up').length, 3, 'CSS shows two on phones, three when wide');
  assert.equal(byClass(b.trail(), 'illustration').length, 1);
  assert.equal(b.get('cancel').hidden, true);
  assert.doesNotMatch(text(b.trail()), /Answered in/, 'no timing metric');
});

test('Dive deeper adds a step, moves the previous one to the rail, and ignores double taps', async () => {
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
  const rail = byClass(b.trail(), 'rail-step');
  assert.equal(rail.length, 1, 'the earlier step joins the rail');
  assert.equal(rail[0].attributes['aria-label'], 'Step 1: What is gravity?');
  assert.equal(byClass(b.trail(), 'connector').length, 1);
  assert.equal(byClass(b.trail(), 'follow-up').length, 0, 'choices hide while the next answer loads');
  await answerLatest(b, reply('The Moon falls around Earth.'));
  assert.equal(b.get('trail-detail').textContent, 'Trail · Step 2');
  byClass(b.trail(), 'rail-step')[0].listeners.click();
  assert.equal(byClass(b.trail(), 'rail-step')[0].attributes['aria-expanded'], 'true');
  assert.match(text(b.trail()), /Gravity pulls objects together/, 'an earlier answer opens again');
});

test('a question typed on Home starts a trail, and Stop gives it back', async () => {
  const b = await browser();
  b.requests[0].complete({ suggestions: sparks() }); await flush();
  b.get('question').value = '  Why is the sky blue?  ';
  b.get('question').listeners.input();
  assert.equal(b.get('ask').disabled, false);
  b.get('question-form').listeners.submit({ preventDefault() {} });
  assert.equal(b.requests.length, 2);
  assert.equal(JSON.parse(b.requests[1].options.body!).question, 'Why is the sky blue?');
  assert.equal(b.get('question').value, '', 'the question moves into the trail');
  assert.equal(b.get('trail-name').textContent, 'Your question');
  b.get('cancel').listeners.click(); await flush();
  assert.equal(b.requests[1].options.signal?.aborted, true);
  assert.equal(b.get('question').value, 'Why is the sky blue?');
  assert.equal(b.body.attributes['data-view'], 'home', 'an empty trail returns Home');
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
  await answerLatest(b);
  assert.equal(byClass(b.trail(), 'error').length, 0);
});

test('Back keeps the trail, and Home offers to continue it', async () => {
  const b = await browser();
  b.requests[0].complete({ suggestions: sparks() }); await flush();
  b.get('spark-grid').children[0].listeners.click();
  await answerLatest(b);
  b.get('back').listeners.click();
  assert.equal(b.body.attributes['data-view'], 'home');
  assert.equal(b.get('resume').hidden, false);
  assert.equal(byClass(b.get('resume'), 'dot').length, 5, 'five steps in a trail');
  assert.equal(byClass(b.get('resume'), 'done').length, 1);
  assert.match(b.get('resume').attributes['aria-label'], /Step 1 of 5/);
  b.get('resume').listeners.click();
  assert.equal(b.body.attributes['data-view'], 'trail');
  assert.match(text(b.trail()), /Gravity pulls objects together/);
});

test('starting a new trail keeps the old one on Home, up to three', async () => {
  const b = await browser();
  b.requests[0].complete({ suggestions: sparks() }); await flush();
  for (const question of ['What is gravity?', 'Why is the sky blue?', 'How do fish breathe?', 'Why do cats purr?']) {
    const answering = vm.runInContext(`view = 'home'; ask(${JSON.stringify(question)})`, b.context);
    b.requests[b.requests.length - 1].complete(reply(`${question} Answer.`)); await answering; await flush();
  }
  b.get('back').listeners.click();
  assert.match(b.get('resume').attributes['aria-label'], /Why do cats purr\?/, 'newest is the big card');
  const rows = b.get('earlier-trails').children;
  assert.deepEqual(rows.map(row => row.attributes['aria-label']),
    ['Earlier trail: How do fish breathe?. Step 1 of 5.', 'Earlier trail: Why is the sky blue?. Step 1 of 5.'], 'two earlier ones; the oldest dropped');
  assert.equal(JSON.parse(b.local['curio.open-trails.v1']).length, 3);
  rows[1].listeners.click();
  assert.equal(b.body.attributes['data-view'], 'trail');
  assert.match(text(b.trail()), /Why is the sky blue\? Answer/);
  b.get('back').listeners.click();
  assert.match(b.get('resume').attributes['aria-label'], /Why is the sky blue\?/, 'the reopened trail is now the newest');
  assert.equal(b.get('earlier-trails').children.length, 2, 'the one it replaced waits as a row');
});

test('the fifth answer offers Finish, which earns one stamp and shows Trail complete', async () => {
  const b = await browser();
  b.requests[0].complete({ suggestions: sparks() }); await flush();
  b.get('spark-grid').children[0].listeners.click();
  await answerLatest(b, reply('Plants grow toward light. They bend.'));
  for (let step = 2; step <= 5; step++) {
    assert.equal(b.get('dock').hidden, false);
    byClass(b.trail(), 'follow-up')[0].listeners.click();
    await answerLatest(b, reply(`Answer ${step}. More detail.`));
  }
  assert.equal(byClass(b.trail(), 'follow-up').length, 0, 'no more choices on the last step');
  assert.equal(b.get('dock').hidden, true, 'Finish replaces the question box');
  byClass(b.trail(), 'finish')[0].listeners.click();
  assert.equal(b.body.attributes['data-view'], 'complete');
  assert.equal(b.get('complete').hidden, false);
  const facts = byClass(b.get('complete'), 'fact').map(text);
  assert.deepEqual(facts, ['Plants grow toward light.', 'Answer 3.', 'Answer 5.'], 'first, middle and last answers');
  const saved = JSON.parse(b.local['curio.stamps.v1']);
  assert.equal(saved.length, 1);
  assert.equal(saved[0].topic, 'Topic 0');
  assert.deepEqual(Object.keys(saved[0]).sort(), ['earned', 'id', 'topic'], 'a stamp keeps only its topic and date');
  const trails = JSON.parse(b.local['curio.trails.v1']);
  assert.equal(trails[0].question, sparks()[0].question);
  assert.equal(byClass(b.get('complete'), 'locked').length, 1, 'one dashed "next" stamp');
  const home = [...walk(b.get('complete'))].find(e => e.textContent === 'Start a new spark')!;
  home.listeners.click();
  assert.equal(b.body.attributes['data-view'], 'home');
  assert.equal(b.get('resume').hidden, true, 'a finished trail is not offered again');
});

test('Home greets the child by the saved first name', async () => {
  const b = await browser(undefined, false, { 'curio.name.v1': 'Ayaan' });
  assert.match(b.get('greeting').textContent, /^What are you curious about (today|tonight), Ayaan\?$/);
  b.get('child-name').value = '  Mira ';
  b.get('settings-done').listeners.click();
  assert.equal(b.local['curio.name.v1'], 'Mira');
  assert.match(b.get('greeting').textContent, /, Mira\?$/);
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
    b.get('new-sparks').listeners.click();
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
  const card = b.get('spark-grid').children[0];
  assert.equal(card.disabled, true);
  card.listeners.click(); b.get('new-sparks').listeners.click();
  assert.equal(b.requests.length, 2, 'no new trail or refresh while answering');
  b.requests[1].complete(reply('Blue light scatters.', ['One?', 'Two?', 'Three?']));
  await answering; await flush();
  assert.equal(b.get('spark-grid').children[0].disabled, false);
  assert.equal(b.get('new-sparks').disabled, false);
});

test('the tutor’s trail name, step label and facts are used when present', async () => {
  const b = await browser();
  b.requests[0].complete({ suggestions: sparks() }); await flush();
  b.get('spark-grid').children[0].listeners.click();
  await answerLatest(b, { ...reply('Comets are icy. They melt near the Sun.'), label: 'Comet tails', trailName: 'Comets', fact: 'Comets are dirty snowballs.' });
  assert.equal(b.get('trail-name').textContent, 'Comets');
  assert.equal(b.get('question').placeholder, 'Ask more about comets…');
  b.get('back').listeners.click();
  assert.match(text(b.get('resume')), /Step 1 · Comet tails/);
  const saved = JSON.parse(b.local['curio.open-trails.v1']);
  assert.equal(saved[0].steps[0].fact, 'Comets are dirty snowballs.', 'saved with the trail');
});

test('an unfinished trail comes back after a reload for 7 days, then is forgotten', async () => {
  const step = { question: 'What is a comet?', topic: 'Space', answer: 'An icy ball.', followUps: ['A?', 'B?', 'C?'], trailName: 'Comets', label: 'Comets' };
  const fresh = { 'curio.open-trails.v1': JSON.stringify([{ id: 'trail-1', savedAt: new Date(Date.now() - 6 * 864e5).toISOString(), steps: [step] }]) };
  const b = await browser(undefined, false, fresh);
  assert.equal(b.get('resume').hidden, false, 'six days old: offered again');
  b.get('resume').listeners.click();
  assert.equal(b.get('trail-name').textContent, 'Comets');
  assert.match(text(b.trail()), /An icy ball/);

  const stale = { 'curio.open-trails.v1': JSON.stringify([{ id: 'trail-2', savedAt: new Date(Date.now() - 8 * 864e5).toISOString(), steps: [step] }]) };
  const old = await browser(undefined, false, stale);
  assert.equal(old.get('resume').hidden, true, 'eight days old: forgotten');
  assert.equal(old.local['curio.open-trails.v1'], 'null');

  const single = { 'curio.trail.v1': JSON.stringify({ id: 'trail-3', savedAt: new Date().toISOString(), steps: [step] }) };
  const migrated = await browser(undefined, false, single);
  assert.equal(migrated.get('resume').hidden, false, 'a trail saved by the older one-trail version comes back');
  assert.equal(migrated.local['curio.trail.v1'], 'null');

  const corrupt = await browser(undefined, false, { 'curio.open-trails.v1': '[{"id":1}]' });
  assert.equal(corrupt.get('resume').hidden, true, 'bad data is ignored');
});

test('a tapped spark leaves the grid, and a finished trail is not offered again', async () => {
  const b = await browser();
  b.requests[0].complete({ suggestions: sparks() }); await flush();
  b.get('spark-grid').children[0].listeners.click();
  assert.equal(b.get('spark-grid').children.length, 3, 'the tapped spark is gone');
  await answerLatest(b, reply('One. More.'));
  assert.match(b.requests[b.requests.length - 1].url, /\/api\/suggestions\?.*count=4/, 'a fresh set loads after the answer');
  b.requests[b.requests.length - 1].complete({ suggestions: sparks(4) }); await flush();
  assert.equal(b.get('spark-grid').children.length, 4);
  for (let step = 2; step <= 5; step++) {
    byClass(b.trail(), 'follow-up')[0].listeners.click();
    await answerLatest(b, reply(`Answer ${step}.`));
  }
  byClass(b.trail(), 'finish')[0].listeners.click();
  assert.equal(b.local['curio.open-trails.v1'], 'null', 'a finished trail is not kept for resuming');
  [...walk(b.get('complete'))].find(e => e.textContent === 'Start a new spark')!.listeners.click();
  assert.equal(b.get('resume').hidden, true);
  b.get('spark-grid').children[0].listeners.click();
  assert.equal(b.get('earlier-trails').children.length, 0, 'the finished trail is not set aside');
});

test('Stamps shows every kind, earned or not, and the latest stamps', async () => {
  const earned = JSON.stringify([
    { id: 't1', topic: 'Space', earned: '2026-09-20T10:00:00.000Z' },
    { id: 't2', topic: 'Space', earned: '2026-09-21T10:00:00.000Z' },
    { id: 't3', topic: null, earned: '2026-09-22T10:00:00.000Z' },
    { id: 't4', topic: 'Topic 9', earned: '2026-09-23T10:00:00.000Z' }
  ]);
  const b = await browser(undefined, false, { 'curio.stamps.v1': earned });
  assert.equal(b.get('stamps-pill').hidden, false);
  b.get('stamps-pill').listeners.click();
  assert.equal(b.body.attributes['data-view'], 'stamps');
  assert.equal(b.get('dock').hidden, true, 'no question box on Stamps');
  assert.equal(b.get('stamps-summary').textContent, '4 stamps · 2 of 12 kinds');
  const kinds = b.get('stamp-kinds').children.map(kind => kind.attributes['aria-label']);
  assert.equal(kinds.length, 12);
  assert.equal(kinds[0], 'Space: 2 stamps');
  assert.equal(kinds[11], 'Curious Mind: 2 stamps', 'own questions and unknown topics count as Curious Mind');
  assert.equal(kinds[1], 'Animals: not earned yet');
  assert.equal(b.get('stamp-list').children.length, 4);
  assert.match(text(b.get('stamp-list').children[0]), /Topic 9 stamp/, 'newest first');
  b.get('stamps-back').listeners.click();
  assert.equal(b.body.attributes['data-view'], 'home');
});

test('sparks prefer uncollected topics and mark them "New stamp!" once a stamp exists', async () => {
  const none = await browser();
  assert.doesNotMatch(none.requests[0].url, /prefer=/, 'no stamps yet: no preference');
  const earned = JSON.stringify([{ id: 't1', topic: 'Topic 0', earned: '2026-09-20T10:00:00.000Z' }]);
  const b = await browser(undefined, false, { 'curio.stamps.v1': earned });
  const prefer = new URL(b.requests[0].url, 'http://localhost').searchParams.get('prefer')!.split(',');
  assert.equal(prefer.length, 11, 'all 11 bank topics are still uncollected');
  assert.ok(prefer.includes('Forces & motion'));
  b.requests[0].complete({ suggestions: [
    { id: 'space-1', topic: 'Space', icon: '🚀', question: 'Why do stars twinkle?' },
    { id: 'topic-0', topic: 'Topic 0', icon: '🌱', question: 'Why do plants grow?' },
    { id: 'body-1', topic: 'Body', icon: '🫀', question: 'Why do we yawn?' },
    { id: 'sound-1', topic: 'Sound', icon: '🎵', question: 'What is an echo?' }
  ] }); await flush();
  const labels = b.get('spark-grid').children.map(card => card.attributes['aria-label']);
  assert.deepEqual(labels, ['Space, new stamp: Why do stars twinkle?', 'Topic 0: Why do plants grow?',
    'Body, new stamp: Why do we yawn?', 'Sound, new stamp: What is an echo?']);
});
