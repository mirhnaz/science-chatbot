// Runs before the stylesheet so a saved theme is applied before the first paint.
// Kept separate from chat behavior; failure to access storage never blocks the app.
(() => {
  type Theme = 'system' | 'light' | 'dark';
  const key = 'science-chatbot.theme.v1';
  const system = window.matchMedia('(prefers-color-scheme: dark)');
  const valid = (value: unknown): value is Theme => value === 'system' || value === 'light' || value === 'dark';
  let preference: Theme = 'system';
  try {
    const saved = localStorage.getItem(key);
    if (valid(saved)) preference = saved;
  } catch { /* Use the system theme when storage is unavailable. */ }

  function apply() {
    const theme = preference === 'system' ? (system.matches ? 'dark' : 'light') : preference;
    document.documentElement.dataset.theme = theme;
    document.querySelector('meta[name="theme-color"]')?.setAttribute('content', theme === 'dark' ? '#101522' : '#f4f6fb');
  }
  apply();
  system.addEventListener('change', () => { if (preference === 'system') apply(); });
  window.addEventListener('storage', event => {
    if (event.key !== key && event.key !== null) return;
    preference = valid(event.newValue) ? event.newValue : 'system';
    apply();
    const select = document.getElementById('theme') as HTMLSelectElement | null;
    if (select) select.value = preference;
  });
  document.addEventListener('DOMContentLoaded', () => {
    const select = document.getElementById('theme') as HTMLSelectElement | null;
    if (!select) return;
    select.value = preference;
    select.addEventListener('change', () => {
      if (!valid(select.value)) return;
      preference = select.value;
      apply();
      try { localStorage.setItem(key, preference); } catch { /* Selection still works in this page. */ }
    });
  }, { once: true });
})();
