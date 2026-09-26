import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';

async function browser(saved: string | null = null, dark = false, blocked = false) {
  const dataset: { theme?: string } = {};
  const events: Record<string, (event?: { key: string | null; newValue: string | null }) => void> = {};
  const select = { value: '', addEventListener(name: string, fn: () => void) { events[name] = fn; } };
  const media = { matches: dark, addEventListener(_name: string, fn: () => void) { events.media = fn; } };
  const context = vm.createContext({
    window: { matchMedia: () => media, addEventListener(name: string, fn: () => void) { events[name] = fn; } },
    document: {
      documentElement: { dataset }, querySelector: () => null, getElementById: () => select,
      addEventListener(name: string, fn: () => void) { events[name] = fn; }
    },
    localStorage: {
      getItem() { if (blocked) throw Error('blocked'); return saved; },
      setItem(_key: string, value: string) { if (blocked) throw Error('blocked'); saved = value; }
    }
  });
  vm.runInContext(await readFile(new URL('../client/theme.js', import.meta.url), 'utf8'), context);
  return { dataset, events, select, media, saved: () => saved };
}

test('theme follows system on first paint and initializes the selector', async () => {
  const b = await browser(null, true);
  assert.equal(b.dataset.theme, 'dark');
  b.events.DOMContentLoaded();
  assert.equal(b.select.value, 'system');
  b.media.matches = false; b.events.media();
  assert.equal(b.dataset.theme, 'light');
});

test('explicit theme persists and ignores system changes until System is selected', async () => {
  const b = await browser('light', true);
  assert.equal(b.dataset.theme, 'light');
  b.events.DOMContentLoaded();
  b.select.value = 'dark'; b.events.change();
  assert.equal(b.saved(), 'dark');
  b.media.matches = false; b.events.media();
  assert.equal(b.dataset.theme, 'dark');
  b.select.value = 'system'; b.events.change();
  assert.equal(b.dataset.theme, 'light');
  assert.equal(b.saved(), 'system');
});

test('invalid preferences and blocked storage do not stop theme selection', async () => {
  for (const blocked of [false, true]) {
    const b = await browser('invalid', false, blocked);
    assert.equal(b.dataset.theme, 'light');
    b.events.DOMContentLoaded();
    b.select.value = 'dark'; b.events.change();
    assert.equal(b.dataset.theme, 'dark');
  }
});

test('theme synchronizes across tabs and resets when storage is cleared', async () => {
  const b = await browser('light');
  b.events.DOMContentLoaded();
  b.events.storage({ key: 'unrelated', newValue: 'dark' });
  assert.equal(b.dataset.theme, 'light');
  b.events.storage({ key: 'curio.theme.v1', newValue: 'dark' });
  assert.equal(b.dataset.theme, 'dark');
  assert.equal(b.select.value, 'dark');
  b.events.storage({ key: null, newValue: null });
  assert.equal(b.dataset.theme, 'light');
  assert.equal(b.select.value, 'system');
});
