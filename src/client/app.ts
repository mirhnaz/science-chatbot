// Curio's web page (docs/DESIGN.md; layouts in docs/design/redesign-2026-09/):
// Home → a Trail of up to five steps → Trail complete. Every question is still
// sent to /api/chat on its own; the trail is kept only in this page. Stamps and
// finished trails (topic, first question, date) stay in this browser.

interface ChatResponse {
  answer?: unknown;
  error?: unknown;
  followUps?: unknown;
  elapsedMs?: unknown;
}

interface Spark { id: string; topic: string; icon: string; question: string }

interface Step {
  id: number;
  question: string;
  /** Spark topic, for example "Electricity", when a trail began from one. */
  topic?: string;
  answer?: string;
  followUps?: string[];
  error?: string;
  /** The next question asked from this step. */
  chosen?: string;
}

/** One stamp per finished trail: only its topic and date. */
interface Stamp { id: string; topic: string | null; earned: string }
/** A finished trail, for "Trails you finished". */
interface FinishedTrail { id: string; topic: string | null; question: string; finished: string }

// Optional browser tool integration; unavailable browsers use the normal UI.
interface ScienceTool {
  name: string;
  title: string;
  description: string;
  inputSchema: {
    type: string;
    properties: Record<string, { type: string; minLength?: number; maxLength?: number }>;
    required?: string[];
    additionalProperties: boolean;
  };
  annotations: { readOnlyHint: boolean; untrustedContentHint: boolean };
  execute: (input: { question?: unknown }) => Promise<unknown>;
}

interface Document {
  modelContext?: {
    registerTool: (tool: ScienceTool, options: { signal: AbortSignal }) => void | Promise<void>;
  };
}

interface AppElements {
  main: HTMLElement;
  home: HTMLElement;
  'trail-screen': HTMLElement;
  complete: HTMLElement;
  greeting: HTMLHeadingElement;
  resume: HTMLButtonElement;
  'brand-mark': HTMLSpanElement;
  'made-with-love': HTMLParagraphElement;
  'settings-home': HTMLButtonElement;
  'settings-trail': HTMLButtonElement;
  back: HTMLButtonElement;
  'trail-name': HTMLHeadingElement;
  'trail-detail': HTMLParagraphElement;
  trail: HTMLElement;
  dock: HTMLDivElement;
  question: HTMLTextAreaElement;
  'question-form': HTMLFormElement;
  ask: HTMLButtonElement;
  cancel: HTMLButtonElement;
  'spark-grid': HTMLDivElement;
  'sparks-status': HTMLParagraphElement;
  'new-sparks': HTMLButtonElement;
  settings: HTMLDialogElement;
  'child-name': HTMLInputElement;
  'settings-done': HTMLButtonElement;
  undo: HTMLDivElement;
  'undo-button': HTMLButtonElement;
  status: HTMLParagraphElement;
}

function $<K extends keyof AppElements>(id: K): AppElements[K] {
  const element = document.getElementById(id);
  if (!element) throw new Error(`Missing page element: ${id}`);
  return element as AppElements[K];
}

function element<K extends keyof HTMLElementTagNameMap>(tag: K, className?: string, text?: string): HTMLElementTagNameMap[K] {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function button(className: string, label?: string): HTMLButtonElement {
  const node = element('button', className, label);
  node.type = 'button';
  return node;
}

/** Appends a constant icon (never user text), then an optional text label. */
function withIcon<T extends HTMLElement>(node: T, icon: string, label?: string): T {
  const glyph = element('span', 'icon');
  glyph.innerHTML = icon;
  node.append(glyph);
  if (label !== undefined) node.append(element('span', undefined, label));
  return node;
}

const reduceMotion = () => window.matchMedia('(prefers-reduced-motion: reduce)').matches;

// ---- Icons (2 px stroke, round caps; docs/DESIGN.md) -------------------------

const stroke = 'fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"';
const svg = (body: string) => `<svg viewBox="0 0 24 24" ${stroke} aria-hidden="true">${body}</svg>`;
const icons = {
  comet: svg('<circle cx="16" cy="8" r="4"/><path d="M13 11L3 21"/><path d="M11 8L4 15"/><path d="M16 13l-7 7"/>'),
  gear: svg('<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>'),
  back: svg('<path d="M15 18l-6-6 6-6"/>'),
  close: svg('<path d="M6 6l12 12"/><path d="M18 6L6 18"/>'),
  shuffle: svg('<path d="M16 3h5v5"/><path d="M4 20L21 3"/><path d="M21 16v5h-5"/><path d="M15 15l6 6"/><path d="M4 4l5 5"/>'),
  send: svg('<path d="M12 19V5"/><path d="M5 12l7-7 7 7"/>'),
  stop: '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><rect x="6" y="6" width="12" height="12" rx="2"/></svg>',
  speaker: svg('<path d="M11 5L6 9H3v6h3l5 4z"/><path d="M15.5 8.5a5 5 0 0 1 0 7"/><path d="M18.5 5.5a9 9 0 0 1 0 13"/>'),
  chevronRight: svg('<path d="M9 6l6 6-6 6"/>'),
  chevronDown: svg('<path d="M6 9l6 6 6-6"/>'),
  chevronUp: svg('<path d="M18 15l-6-6-6 6"/>'),
  check: svg('<path d="M5 12l5 5L20 7"/>'),
  share: svg('<path d="M4 12v7a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-7"/><path d="M12 3v12"/><path d="M8 7l4-4 4 4"/>'),
  flag: svg('<path d="M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z"/><path d="M4 22v-7"/>'),
  heart: '<svg viewBox="0 0 24 24" class="heart" aria-hidden="true"><path d="M12 21s-7-4.6-9-9.2C1.6 8.4 4 5 7.5 5c2 0 3.4 1.1 4.5 2.6C13.1 6.1 14.5 5 16.5 5 20 5 22.4 8.4 21 11.8 19 16.4 12 21 12 21z"/></svg>'
};

/** Category styles: CSS class (tokens) and icon paths. Unknown topics, and the
 *  child's own questions, use Space. */
const categories: Record<string, { key: string; paths: string }> = {
  Weather: { key: 'weather', paths: '<circle cx="9" cy="8" r="3.5"/><path d="M9 1.5V3"/><path d="M2.5 8H4"/><path d="M4.4 3.4l1 1"/><path d="M8 20.5h9a3.5 3.5 0 0 0 .5-7 5 5 0 0 0-9.6 1.5A3 3 0 0 0 8 20.5z"/>' },
  Animals: { key: 'animals', paths: '<path d="M2.5 12s3.5-6 9.5-6 8.5 6 8.5 6-2.5 6-8.5 6-9.5-6-9.5-6z"/><path d="M20.5 12l1.5-3.5v7z" fill="currentColor"/><circle cx="8" cy="11" r="1.2" fill="currentColor"/>' },
  Space: { key: 'space', paths: '<circle cx="16" cy="8" r="4"/><path d="M13 11L3 21"/><path d="M11 8L4 15"/><path d="M16 13l-7 7"/>' },
  Sound: { key: 'sound', paths: '<path d="M9 18V5l10-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="16" cy="16" r="3"/>' },
  Light: { key: 'light', paths: '<path d="M9 18h6"/><path d="M10 22h4"/><path d="M12 2a7 7 0 0 0-4 12.7V17h8v-2.3A7 7 0 0 0 12 2z"/>' },
  Body: { key: 'body', paths: '<path d="M12 21s-7-4.6-9-9.2C1.6 8.4 4 5 7.5 5c2 0 3.4 1.1 4.5 2.6C13.1 6.1 14.5 5 16.5 5 20 5 22.4 8.4 21 11.8 19 16.4 12 21 12 21z"/>' },
  Earth: { key: 'earth', paths: '<path d="M8 3l4 8 5-5 5 15H2L8 3z"/>' },
  Electricity: { key: 'electricity', paths: '<path d="M13 2L3 14h9l-1 8 10-12h-9l1-8z"/>' },
  'Forces & motion': { key: 'forces', paths: '<path d="M5 9l-3 3 3 3"/><path d="M9 5l3-3 3 3"/><path d="M15 19l-3 3-3-3"/><path d="M19 9l3 3-3 3"/><path d="M2 12h20"/><path d="M12 2v20"/>' },
  Matter: { key: 'matter', paths: '<circle cx="12" cy="12" r="1"/><path d="M20.2 20.2c2-2 0-7.4-4.5-11.9S6.3 1.8 4.3 3.8s0 7.4 4.5 11.9 9.4 6.5 11.4 4.5z"/><path d="M15.7 15.7c4.5-4.5 6.5-9.9 4.5-11.9s-7.4 0-11.9 4.5-6.5 9.9-4.5 11.9 7.4 0 11.9-4.5z"/>' },
  Plants: { key: 'plants', paths: '<path d="M11 20A7 7 0 0 1 9.8 6.1C15.5 5 17 4.5 19 2c1 2 2 4.2 2 8 0 5.5-4.8 10-10 10z"/><path d="M2 21c0-3 1.9-5.4 5.1-6C9.5 14.5 12 13 13 12"/>' }
};
const category = (topic?: string | null) => {
  const style = categories[topic ?? ''] ?? categories.Space;
  return { key: style.key, icon: svg(style.paths), paths: style.paths };
};

// ---- Local storage (optional; blocked storage just forgets) ---------------

function load<T>(key: string, valid: (value: unknown) => value is T, fallback: T): T {
  try {
    const value: unknown = JSON.parse(localStorage.getItem(key) ?? 'null');
    return valid(value) ? value : fallback;
  } catch { return fallback; }
}
function save(key: string, value: unknown) {
  try { localStorage.setItem(key, typeof value === 'string' ? value : JSON.stringify(value)); } catch { /* Optional storage. */ }
}
const nameKey = 'curio.name.v1';
const stampsKey = 'curio.stamps.v1';
const trailsKey = 'curio.trails.v1';
const record = (item: unknown): item is Record<string, unknown> => !!item && typeof item === 'object';
const isStamps = (value: unknown): value is Stamp[] => Array.isArray(value) && value.every(item =>
  record(item) && typeof item.id === 'string' && (item.topic === null || typeof item.topic === 'string') && typeof item.earned === 'string');
const isTrails = (value: unknown): value is FinishedTrail[] => Array.isArray(value) && value.every(item =>
  record(item) && typeof item.id === 'string' && (item.topic === null || typeof item.topic === 'string')
  && typeof item.question === 'string' && typeof item.finished === 'string');
function childName(): string {
  try { return (localStorage.getItem(nameKey) ?? '').trim().slice(0, 40); } catch { return ''; }
}

// ---- State ---------------------------------------------------------------

/** Steps in a full trail; after the last answer the trail can be finished. */
const trailLength = 5;
type View = 'home' | 'trail' | 'complete';
let view: View = 'home';
let steps: Step[] = [];
let trailId = newTrailId();
/** The child tapped Finish; until then Home offers to continue the trail. */
let finished = false;
let undoState: { steps: Step[]; trailId: string; finished: boolean } | null = null;
let undoTimer: ReturnType<typeof setTimeout> | undefined;
let expanded = new Set<number>();
let nextStepId = 1;
let controller: AbortController | null = null;
let stamps = load(stampsKey, isStamps, []);
let finishedTrails = load(trailsKey, isTrails, []);

function newTrailId() {
  return `trail-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
}
const answered = () => steps.filter(step => step.answer !== undefined).length;
const isComplete = () => answered() >= trailLength;
const hasUnfinishedTrail = () => steps.length > 0 && !finished;
const trailTopic = () => steps[0]?.topic;

// ---- Sparks (starter questions from /api/suggestions) --------------------

const recentSparksKey = 'curio.recent-suggestions.v1';
const recentSparksLimit = 40;
let recentSparks: string[] = [];
try {
  const stored: unknown = JSON.parse(sessionStorage.getItem(recentSparksKey) || '[]');
  if (Array.isArray(stored)) recentSparks = stored.filter((id): id is string => typeof id === 'string' && /^[a-z0-9-]{1,64}$/.test(id)).slice(-recentSparksLimit);
} catch { /* Browsers may disable storage; in-memory rotation still works. */ }
let sparks: Spark[] = [];
let sparksLoading = false;

function isSpark(value: unknown): value is Spark {
  if (!value || typeof value !== 'object') return false;
  const item = value as Record<string, unknown>;
  return typeof item.id === 'string' && /^[a-z0-9-]{1,64}$/.test(item.id)
    && typeof item.topic === 'string' && !!item.topic.trim()
    && typeof item.icon === 'string' && !!item.icon.trim()
    && typeof item.question === 'string' && !!item.question.trim() && item.question.length <= 2000;
}

async function refreshSparks() {
  if (sparksLoading || controller) return;
  sparksLoading = true;
  updateControls();
  $('spark-grid').setAttribute('aria-busy', 'true');
  $('sparks-status').className = 'sr-only';
  $('sparks-status').textContent = 'Finding new sparks…';
  const request = new AbortController();
  const timer = setTimeout(() => request.abort(), 8000);
  try {
    const exclude = encodeURIComponent(recentSparks.join(','));
    const response = await fetch(`/api/suggestions?exclude=${exclude}`, { signal: request.signal });
    if (!response.ok) throw new Error('Sparks unavailable');
    const data: unknown = await response.json();
    const items = data && typeof data === 'object' ? (data as Record<string, unknown>).suggestions : undefined;
    if (!Array.isArray(items) || items.length !== 4 || !items.every(isSpark)
      || new Set(items.map(item => item.id)).size !== 4 || new Set(items.map(item => item.topic)).size !== 4) throw new Error('Invalid sparks');
    sparks = items;
    recentSparks = [...new Set([...recentSparks, ...items.map(item => item.id)])].slice(-recentSparksLimit);
    try { sessionStorage.setItem(recentSparksKey, JSON.stringify(recentSparks)); } catch { /* Optional storage. */ }
    $('sparks-status').textContent = 'Pick a spark to ask it, or type your own question.';
  } catch {
    $('sparks-status').className = 'sparks-error';
    $('sparks-status').textContent = 'Couldn’t load new sparks. Try again, or type your own question.';
  } finally {
    clearTimeout(timer);
    sparksLoading = false;
    $('spark-grid').setAttribute('aria-busy', 'false');
    renderSparks();
  }
}

/** Fills the question box instead of asking (right-click or long-press). */
function editFirst(target: HTMLElement, text: string) {
  target.addEventListener('contextmenu', event => {
    event.preventDefault();
    if (controller) return;
    $('question').value = text;
    updateControls();
    $('question').focus();
  });
}

/** A tinted card: icon disc, topic label, and the question. */
function renderSparks() {
  const cards = sparks.map(spark => {
    const style = category(spark.topic);
    const card = button(`spark-card cat-${style.key}`);
    const disc = element('span', 'icon-disc');
    disc.innerHTML = style.icon;
    const words = element('span', 'spark-words');
    words.append(element('span', 'spark-topic', spark.topic), element('span', 'spark-question', spark.question));
    card.append(disc, words);
    card.setAttribute('aria-label', `${spark.topic}: ${spark.question}`);
    card.addEventListener('click', () => startTrail(spark));
    editFirst(card, spark.question);
    return card;
  });
  $('spark-grid').replaceChildren(...cards);
  updateControls();
}

// ---- Asking --------------------------------------------------------------

function startTrail(spark: Spark) {
  if (controller) return;
  sparks = sparks.filter(item => item.id !== spark.id);
  void ask(spark.question, { newTrail: true, topic: spark.topic });
}

function replaceTrail() {
  stopSpeech();
  undoState = steps.some(step => step.answer) ? { steps, trailId, finished } : null;
  steps = [];
  trailId = newTrailId();
  finished = false;
  expanded = new Set();
  showUndo();
}

function showUndo() {
  clearTimeout(undoTimer);
  $('undo').hidden = !undoState;
  if (undoState) undoTimer = setTimeout(() => { undoState = null; $('undo').hidden = true; }, 6000);
}

function undo() {
  if (!undoState) return;
  controller?.abort('undo');
  ({ steps, trailId, finished } = undoState);
  undoState = null;
  showUndo();
  go(finished ? 'home' : 'trail');
}

async function ask(question: unknown, options: { newTrail?: boolean; topic?: string } = {}) {
  if (controller) throw new Error('A question is already being answered.');
  if (typeof question !== 'string' || !question.trim() || question.trim().length > 2000) throw new Error('Enter a question between 1 and 2,000 characters.');
  const asked = question.trim();
  // A question typed on Home, or after a finished trail, starts a new trail.
  if (options.newTrail || view !== 'trail' || isComplete()) replaceTrail();
  if (steps.length) steps[steps.length - 1].chosen = asked;
  const step: Step = { id: nextStepId++, question: asked, topic: options.topic ?? trailTopic() };
  steps.push(step);
  expanded = new Set();
  if ($('question').value.trim() === asked) $('question').value = '';
  stopSpeech();

  const current = new AbortController();
  controller = current;
  const timer = setTimeout(() => current.abort('timeout'), 125000);
  $('status').textContent = 'Exploring your question…';
  go('trail');
  scrollToTop();
  try {
    const response = await fetch('/api/chat', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ question: asked }), signal: current.signal });
    const data: ChatResponse = await response.json();
    if (!response.ok) throw new Error(typeof data.error === 'string' ? data.error : 'Something went wrong. Please try again.');
    if (typeof data.answer !== 'string' || !data.answer.trim()) throw new Error('No answer came back. Please try again.');
    step.answer = data.answer;
    step.followUps = Array.isArray(data.followUps) ? data.followUps.filter((q: unknown): q is string => typeof q === 'string' && !!q.trim()).slice(0, 3) : [];
    $('status').textContent = isComplete() ? 'Your answer is ready, and your trail is ready to finish.' : 'Your answer is ready.';
    return { question: asked, answer: step.answer, followUps: step.followUps };
  } catch (error) {
    const reason: unknown = current.signal.reason;
    if (current.signal.aborted && (reason === 'undo' || reason === 'replace')) {
      return { error: 'Question cancelled.' };
    }
    if (current.signal.aborted && reason !== 'timeout') {
      // Stop: remove the unanswered step and give the question back.
      steps = steps.filter(item => item !== step);
      if (steps.length) steps[steps.length - 1].chosen = undefined;
      $('question').value = asked;
      $('status').textContent = 'Stopped. Try another question whenever you’re ready.';
      return { error: 'Question cancelled.' };
    }
    const message = error instanceof Error ? error.message : 'Something went wrong. Please try again.';
    step.error = current.signal.aborted ? 'That answer took too long. Please try again.'
      : message === 'Failed to fetch' ? 'We couldn’t reach your science tutor. Please check the connection and try again.' : message;
    $('status').textContent = 'Ready to try again.';
    return { error: step.error };
  } finally {
    clearTimeout(timer);
    if (controller === current) controller = null;
    if (steps.length === 0) go('home'); else render();
  }
}

function retry() {
  const last = steps[steps.length - 1];
  if (!last?.error || controller) return;
  steps = steps.slice(0, -1);
  void ask(last.question, { topic: last.topic });
}

/** The last step's Finish: one stamp and one "finished trail" per trail. */
function finishTrail() {
  if (!isComplete() || controller) return;
  stopSpeech();
  const now = new Date().toISOString();
  if (!stamps.some(stamp => stamp.id === trailId)) {
    stamps = [...stamps, { id: trailId, topic: trailTopic() ?? null, earned: now }];
    save(stampsKey, stamps);
  }
  if (!finishedTrails.some(trail => trail.id === trailId)) {
    finishedTrails = [...finishedTrails, { id: trailId, topic: trailTopic() ?? null, question: steps[0].question, finished: now }].slice(-100);
    save(trailsKey, finishedTrails);
  }
  finished = true;
  go('complete');
  scrollToTop();
}

// ---- Rendering -----------------------------------------------------------

/** Switches screens, as a View Transition where the browser supports it. */
function go(next: View) {
  const update = () => { view = next; render(); };
  if (next !== view && typeof document.startViewTransition === 'function' && !reduceMotion()) document.startViewTransition(update);
  else update();
}

function render() {
  document.body.setAttribute('data-view', view);
  $('home').hidden = view !== 'home';
  $('trail-screen').hidden = view !== 'trail';
  $('complete').hidden = view !== 'complete';
  // The last step offers Finish instead of the question box.
  $('dock').hidden = view === 'complete' || (view === 'trail' && isComplete() && !controller);
  const topic = trailTopic();
  $('question').placeholder = view === 'trail' ? `Ask more about ${topic ? topic.toLowerCase() : 'this'}…` : 'Ask anything…';
  renderHome();
  renderTrail();
  if (view === 'complete') renderComplete();
  updateControls();
}

function renderHome() {
  const name = childName();
  const hour = new Date().getHours();
  const when = hour >= 18 || hour < 5 ? 'tonight' : 'today';
  $('greeting').textContent = name ? `What are you curious about ${when}, ${name}?` : `What are you curious about ${when}?`;
  const resume = $('resume');
  resume.hidden = !hasUnfinishedTrail();
  if (resume.hidden) return;
  const dots = element('span', 'dots');
  for (let i = 0; i < trailLength; i++) dots.append(element('span', i < answered() ? 'dot done' : 'dot'));
  // The design's short step label needs the tutor to name each step; until
  // then, the step's question.
  const row = element('span', 'resume-row');
  row.append(dots, element('span', 'resume-step', `Step ${steps.length} · ${steps[steps.length - 1].question}`),
    withIcon(element('span', 'resume-go', 'Keep going'), icons.chevronRight));
  resume.replaceChildren(element('span', 'resume-label', 'Continue your trail'), element('span', 'resume-question', steps[0].question), row);
  resume.setAttribute('aria-label', `Continue your trail: ${steps[0].question}. Step ${steps.length} of ${trailLength}.`);
}

function renderTrail() {
  $('trail-name').textContent = trailTopic() ?? 'Your question';
  $('trail-detail').textContent = controller ? 'Thinking…' : `Trail · Step ${steps.length}`;
  const latestId = steps[steps.length - 1]?.id;
  const nodes: HTMLElement[] = [];
  steps.forEach((step, index) => {
    if (step.id === latestId) nodes.push(currentStep(step, index + 1));
    else nodes.push(railStep(step, index + 1), element('div', 'connector'));
  });
  $('trail').replaceChildren(...nodes);
  $('trail').className = `trail cat-${category(trailTopic()).key}`;
}

function stepDisc(number: number, current: boolean) {
  const disc = element('span', current ? 'step-disc current' : 'step-disc', String(number));
  disc.setAttribute('aria-hidden', 'true');
  return disc;
}

/** An earlier step: number, one-line question, chevron; opens its answer. */
function railStep(step: Step, number: number) {
  const wrap = element('div', 'rail-item');
  const open = expanded.has(step.id);
  const row = button('rail-step');
  row.setAttribute('aria-expanded', String(open));
  row.setAttribute('aria-label', `Step ${number}: ${step.question}`);
  row.append(stepDisc(number, false), element('span', 'rail-question', step.question));
  withIcon(row, open ? icons.chevronUp : icons.chevronDown);
  row.addEventListener('click', () => {
    if (open) expanded.delete(step.id); else expanded.add(step.id);
    renderTrail(); updateControls();
  });
  wrap.append(row);
  if (open && step.answer) {
    const answer = element('div', 'rail-answer');
    answer.append(element('p', 'answer', step.answer));
    const speak = speakButton(step);
    if (speak) answer.append(speak);
    wrap.append(answer);
  }
  return wrap;
}

function speakButton(step: Step) {
  if (!step.answer || !localVoice()) return null;
  const on = speakingStep === step.id;
  const speak = button('icon-button accent speak');
  speak.setAttribute('aria-label', on ? 'Stop reading' : 'Read this aloud');
  speak.setAttribute('aria-pressed', String(on));
  speak.innerHTML = on ? icons.stop : icons.speaker;
  speak.addEventListener('click', () => toggleSpeech(step));
  return speak;
}

/** The current step: heading, illustration, answer, and what comes next. */
function currentStep(step: Step, number: number) {
  const article = element('article', 'current-step');
  article.id = `step-${step.id}`;
  const head = element('div', 'current-head');
  head.append(stepDisc(number, true), element('h2', 'current-question', step.question));
  const speak = speakButton(step);
  if (speak) head.append(speak);
  article.append(head);

  if (step.error) {
    const error = element('div', 'error');
    error.setAttribute('role', 'alert');
    error.append(element('p', undefined, step.error));
    const again = button('pill', 'Try again');
    again.addEventListener('click', retry);
    error.append(again);
    article.append(error);
  } else if (step.answer === undefined) {
    const loading = element('div', 'loading');
    loading.append(element('span', 'spinner'), element('span', undefined, 'Working on your answer…'));
    article.append(loading);
  } else {
    const body = element('div', 'step-body');
    body.append(illustration(step.topic), element('p', 'answer', step.answer));
    article.append(body);
    if (isComplete()) {
      const finish = withIcon(button('primary finish'), icons.flag, 'Finish your trail');
      finish.addEventListener('click', finishTrail);
      article.append(finish);
    } else if (step.followUps?.length) {
      const dive = element('section', 'dive');
      dive.setAttribute('aria-label', 'Dive deeper');
      dive.append(element('h3', 'dive-label', 'Dive deeper'));
      const chips = element('div', 'dive-chips');
      for (const followUp of step.followUps) {
        const chip = button('chip follow-up');
        chip.append(element('span', 'chip-text', followUp));
        withIcon(chip, icons.chevronRight);
        chip.setAttribute('aria-label', followUp);
        chip.addEventListener('click', () => { if (!controller) void ask(followUp); });
        editFirst(chip, followUp);
        chips.append(chip);
      }
      dive.append(chips);
      article.append(dive);
    }
  }
  return article;
}

/** The illustration slot. Per-step pictures need generating; until then each
 *  category has one scene: sparkles and its icon on a disc. */
function illustration(topic?: string) {
  const figure = element('div', 'illustration');
  figure.setAttribute('aria-hidden', 'true');
  const dots = [[24, 22, 1.6], [80, 100, 1.6], [150, 18, 2], [210, 106, 1.6], [120, 60, 1.3], [272, 26, 1.8], [318, 86, 1.4], [48, 66, 1.2]]
    .map(([x, y, r]) => `<circle class="sparkle" cx="${x}" cy="${y}" r="${r}"/>`).join('');
  figure.innerHTML = `<svg viewBox="0 0 350 124" preserveAspectRatio="xMidYMid slice">${dots}<circle class="halo" cx="175" cy="62" r="46"/><circle class="disc" cx="175" cy="62" r="32"/><svg class="glyph" x="155" y="42" width="40" height="40" viewBox="0 0 24 24" ${stroke}>${category(topic).paths}</svg></svg>`;
  return figure;
}

// ---- Trail complete ------------------------------------------------------

/** Three things from the trail. The design asks for generated facts; until
 *  then, the first sentence of three answers spread across the trail. */
function recapFacts(): string[] {
  const answers = steps.map(step => step.answer).filter((answer): answer is string => !!answer);
  const picks = answers.length <= 3 ? answers.map((_, i) => i) : [0, Math.floor(answers.length / 2), answers.length - 1];
  return picks.map(i => firstSentence(answers[i]));
}
function firstSentence(text: string) {
  const match = /^[\s\S]+?[.!?](?=\s|$)/.exec(text.trim());
  return (match ? match[0] : text).trim();
}

function renderComplete() {
  const topic = trailTopic() ?? null;
  const style = category(topic);
  const stampName = topic ? `${topic} stamp` : 'Curious Mind stamp';

  const header = element('header', 'app-header');
  const close = button('icon-button');
  close.setAttribute('aria-label', 'Close');
  close.innerHTML = icons.close;
  close.addEventListener('click', () => go('home'));
  header.append(close, element('p', 'caption', `${topic ?? 'Your question'} · ${steps.length} steps`), element('span', 'header-spacer'));

  const hero = element('div', `stamp-hero cat-${style.key}`);
  hero.innerHTML = style.icon;
  hero.setAttribute('role', 'img');
  hero.setAttribute('aria-label', stampName);
  const heading = element('h1', undefined, 'Trail complete!');
  heading.id = 'complete-heading';
  const sub = element('p', 'complete-sub', `You earned the ${stampName}. Here’s what you figured out:`);

  const recap = element('div', 'recap');
  for (const fact of recapFacts()) recap.append(withIcon(element('p', 'fact'), icons.check, fact));

  const head = element('div', 'stamps-head');
  head.append(element('h2', undefined, 'Your stamps'), element('span', 'stamps-count', stamps.length === 1 ? '1 stamp' : `${stamps.length} stamps`));
  const row = element('div', 'stamps');
  for (const stamp of stamps.slice(-4)) {
    const own = category(stamp.topic);
    const disc = element('span', `stamp cat-${own.key}${stamp.id === trailId ? ' new' : ''}`);
    disc.innerHTML = own.icon;
    disc.setAttribute('role', 'img');
    disc.setAttribute('aria-label', `${stamp.topic ?? 'Curious Mind'} stamp, ${stamp.id === trailId ? 'just earned' : 'earned'}`);
    row.append(disc);
  }
  const next = element('span', 'stamp locked');
  next.setAttribute('role', 'img');
  next.setAttribute('aria-label', 'Next stamp, not earned yet');
  row.append(next);

  const actions = element('div', 'complete-actions');
  const newSpark = button('primary', 'Start a new spark');
  newSpark.addEventListener('click', () => go('home'));
  const grownUp = withIcon(button('secondary'), icons.share, 'Show a grown-up');
  grownUp.addEventListener('click', () => { void showGrownUp(); });
  actions.append(newSpark, grownUp);

  $('complete').replaceChildren(header, hero, heading, sub, recap, head, row, actions);
}

/** "Show a grown-up": the recap card as a picture, plus the trail's
 *  questions as text. Shares where the browser can; otherwise saves the
 *  picture and copies the questions. */
async function showGrownUp() {
  const topic = trailTopic() ?? 'Your question';
  const questions = steps.map((step, i) => `${i + 1}. ${step.question}`).join('\n');
  const text = `What I explored on Curio (${topic}):\n${questions}`;
  const blob = await recapImage(topic, recapFacts());
  const file = blob ? new File([blob], 'curio-trail.png', { type: 'image/png' }) : null;
  try {
    if (file && navigator.canShare?.({ files: [file], text })) {
      await navigator.share({ files: [file], text, title: `Curio: ${topic}` });
      return;
    }
  } catch (error) {
    if (error instanceof DOMException && error.name === 'AbortError') return;  // closed the share sheet
  }
  if (blob) {
    const link = element('a');
    link.href = URL.createObjectURL(blob);
    link.download = 'curio-trail.png';
    link.click();
    setTimeout(() => URL.revokeObjectURL(link.href), 1000);
  }
  try {
    await navigator.clipboard.writeText(text);
    $('status').textContent = 'Saved the picture and copied the questions.';
  } catch {
    $('status').textContent = 'Saved the picture.';
  }
}

/** Draws the recap card on a canvas, in the light colours (docs/DESIGN.md). */
async function recapImage(topic: string, facts: string[]): Promise<Blob | null> {
  const canvas = element('canvas');
  const context = canvas.getContext('2d');
  if (!context) return null;
  const scale = 2, width = 390, pad = 20, lineHeight = 21;
  const titleFont = '700 20px Fredoka, Nunito, sans-serif';
  const factFont = '700 15px Nunito, sans-serif';
  const wrap = (text: string, max: number) => {
    context.font = factFont;
    const lines: string[] = [];
    let line = '';
    for (const word of text.split(/\s+/)) {
      const next = line ? `${line} ${word}` : word;
      if (context.measureText(next).width > max && line) { lines.push(line); line = word; } else line = next;
    }
    if (line) lines.push(line);
    return lines;
  };
  const factLines = facts.map(fact => wrap(fact, width - pad * 2 - 62));
  const cardTop = pad + 44;
  const height = cardTop + 16 + factLines.reduce((sum, lines) => sum + lines.length * lineHeight + 10, 0) + 6 + pad;
  canvas.width = width * scale;
  canvas.height = height * scale;
  context.scale(scale, scale);
  context.fillStyle = '#FFF9F0';  // ground
  context.fillRect(0, 0, width, height);
  context.fillStyle = '#211E3B';  // ink
  context.font = titleFont;
  context.fillText(`${topic}: what I found out`, pad, pad + 20);
  context.fillStyle = '#FFFFFF';  // surface
  context.strokeStyle = '#EDE6DA';  // border
  context.lineWidth = 1.5;
  context.beginPath();
  context.roundRect(pad, cardTop, width - pad * 2, height - cardTop - pad, 18);
  context.fill();
  context.stroke();
  let y = cardTop + 16;
  for (const lines of factLines) {
    context.strokeStyle = '#1F7A45';  // success
    context.lineWidth = 2.6;
    context.lineCap = 'round';
    context.beginPath();
    context.moveTo(pad + 18, y + 9); context.lineTo(pad + 23, y + 14); context.lineTo(pad + 32, y + 4);
    context.stroke();
    context.fillStyle = '#211E3B';
    context.font = factFont;
    lines.forEach((line, i) => context.fillText(line, pad + 46, y + 15 + i * lineHeight));
    y += lines.length * lineHeight + 10;
  }
  return new Promise(resolve => canvas.toBlob(resolve, 'image/png'));
}

function scrollToTop() {
  if (typeof window.scrollTo !== 'function') return;
  const frame = window.requestAnimationFrame ?? ((callback: () => void) => setTimeout(callback, 16));
  frame(() => window.scrollTo({ top: 0, behavior: reduceMotion() ? 'auto' : 'smooth' }));
}

function updateControls() {
  const busy = !!controller;
  $('ask').disabled = busy || !$('question').value.trim();
  $('ask').hidden = busy;
  $('cancel').hidden = !busy;
  $('new-sparks').disabled = busy || sparksLoading;
  $('resume').disabled = busy;
  document.querySelectorAll<HTMLButtonElement>('.spark-card, .follow-up').forEach(item => { item.disabled = busy; });
  $('trail-detail').textContent = busy ? 'Thinking…' : `Trail · Step ${steps.length}`;
  $('main').setAttribute('aria-busy', String(busy));
}

// ---- Read aloud ----------------------------------------------------------

const synthesis = window.speechSynthesis;
let speakingStep: number | null = null;
function localVoice() { return synthesis?.getVoices().find(v => v.localService && /^en(?:-|_)/i.test(v.lang)); }
function stopSpeech() {
  if (speakingStep === null) return;
  synthesis?.cancel();
  speakingStep = null;
  renderTrail();
}
function toggleSpeech(step: Step) {
  const voice = localVoice();
  if (speakingStep === step.id || !step.answer || !voice) return stopSpeech();
  synthesis.cancel();
  const utterance = new SpeechSynthesisUtterance(step.answer);
  utterance.voice = voice; utterance.lang = voice.lang; utterance.rate = .92;
  utterance.onend = () => { if (speakingStep === step.id) stopSpeech(); };
  utterance.onerror = () => { if (speakingStep === step.id) stopSpeech(); };
  speakingStep = step.id;
  renderTrail();
  synthesis.speak(utterance);
}

// ---- Settings (name here; theme.ts saves the theme) ----------------------

function openSettings() {
  $('child-name').value = childName();
  const dialog = $('settings');
  if (typeof dialog.showModal === 'function') dialog.showModal();
}

// ---- Wiring --------------------------------------------------------------

$('brand-mark').innerHTML = icons.comet;
const heart = element('span', 'icon');
heart.innerHTML = icons.heart;
$('made-with-love').replaceChildren(heart, element('span', undefined, 'Made with love by Ayaan and Naz'));
$('settings-home').innerHTML = icons.gear;
$('settings-trail').innerHTML = icons.gear;
$('back').innerHTML = icons.back;
$('ask').innerHTML = icons.send;
$('cancel').innerHTML = icons.stop;
withIcon($('new-sparks'), icons.shuffle, 'Shuffle');

function submit() {
  if (controller || !$('question').value.trim()) return;
  void ask($('question').value);
}
$('question-form').addEventListener('submit', event => { event.preventDefault(); submit(); });
$('question').addEventListener('keydown', event => {
  // Enter asks, like Messages; Shift+Enter adds a line.
  if (event.key === 'Enter' && !event.shiftKey && !event.isComposing) { event.preventDefault(); submit(); }
});
$('question').addEventListener('input', () => {
  const box = $('question');
  if (box.style) { box.style.height = 'auto'; box.style.height = `${Math.min(box.scrollHeight, 160)}px`; }
  updateControls();
});
$('cancel').addEventListener('click', () => controller?.abort('cancel'));
$('new-sparks').addEventListener('click', () => { void refreshSparks(); });
$('resume').addEventListener('click', () => { go('trail'); scrollToTop(); });
$('back').addEventListener('click', () => { stopSpeech(); go('home'); });
$('settings-home').addEventListener('click', openSettings);
$('settings-trail').addEventListener('click', openSettings);
$('settings-done').addEventListener('click', () => {
  save(nameKey, $('child-name').value.trim().slice(0, 40));
  renderHome();
});
$('undo-button').addEventListener('click', undo);
synthesis?.addEventListener('voiceschanged', renderTrail);
window.addEventListener('pagehide', () => { controller?.abort('cancel'); stopSpeech(); });

render();
void refreshSparks();

const toolsLifecycle = new AbortController();
if (document.modelContext?.registerTool) {
  const scienceTools: ScienceTool[] = [
    { name: 'ask_science_question', title: 'Ask a science question', description: 'Send a science question to the private Qwen tutor and show the answer on this page. This transmits the question to the configured tutor computer.', inputSchema: { type: 'object', properties: { question: { type: 'string', minLength: 1, maxLength: 2000 } }, required: ['question'], additionalProperties: false }, annotations: { readOnlyHint: false, untrustedContentHint: true }, execute: async (input) => ask(input?.question) },
    { name: 'read_science_answer', title: 'Read the current science answer', description: 'Return the question and answer currently displayed, without making another model request.', inputSchema: { type: 'object', properties: {}, additionalProperties: false }, annotations: { readOnlyHint: true, untrustedContentHint: true }, execute: async () => { const last = steps[steps.length - 1]; return { question: last?.question ?? '', answer: last?.answer ?? '', busy: !!controller }; } }
  ];
  for (const tool of scienceTools) { try { Promise.resolve(document.modelContext.registerTool(tool, { signal: toolsLifecycle.signal })).catch(() => {}); } catch {} }
  window.addEventListener('pagehide', () => toolsLifecycle.abort());
}
