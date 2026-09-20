import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';

test('follow-up buttons submit their question and clear while the next answer loads', async () => {
  class Element {
    hidden = false; disabled = false; value = ''; textContent = ''; children = []; listeners = {};
    addEventListener(type, handler) { this.listeners[type] = handler; }
    setAttribute() {} setCustomValidity() {} focus() {} scrollIntoView() {}
    replaceChildren() { this.children = []; }
    append(child) { this.children.push(child); }
  }
  const elements = new Map();
  const get = id => { if (!elements.has(id)) elements.set(id, new Element()); return elements.get(id); };
  const requests = [];
  const followUps = ['Why does the Moon orbit Earth?', 'What causes ocean tides?', 'How does gravity affect stars?'];
  const context = vm.createContext({
    document: {
      getElementById: get, createElement: () => new Element(),
      querySelectorAll: selector => selector.includes('.follow-up') ? get('follow-up-list').children : []
    },
    window: { addEventListener() {}, matchMedia: () => ({ matches: false }) },
    AbortController, setTimeout, clearTimeout,
    fetch: (url, options) => new Promise(resolve => requests.push({ url, options, resolve }))
  });
  vm.runInContext(await readFile(new URL('../dist/app.js', import.meta.url), 'utf8'), context);
  const complete = request => request.resolve({ ok: true, json: async () => ({ answer: 'Gravity pulls objects together.', followUps, elapsedMs: 10 }) });
  const first = vm.runInContext('ask("What is gravity?")', context);
  complete(requests[0]); await first;
  assert.equal(get('follow-ups').hidden, false);
  assert.equal(get('follow-up-list').children.length, 3);
  const button = get('follow-up-list').children[0];
  assert.equal(button.textContent, followUps[0]);
  assert.equal(button.disabled, false);
  button.listeners.click();
  assert.equal(requests.length, 2);
  assert.equal(JSON.parse(requests[1].options.body).question, followUps[0]);
  assert.equal(get('follow-ups').hidden, true);
  assert.equal(get('follow-up-list').children.length, 0);
  assert.equal(get('ask').disabled, true);
  button.listeners.click();
  assert.equal(requests.length, 2, 'double clicks must not start another request');
  complete(requests[1]);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(get('asked-question').textContent, followUps[0]);
  assert.equal(get('follow-up-list').children.length, 3);
  assert.equal(get('ask').disabled, false);
});
