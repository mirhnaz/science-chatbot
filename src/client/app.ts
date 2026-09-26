// Curio's web page: the curiosity column (docs/DESIGN.md). A fresh session
// centres the question box with Sparks; after the first question the box moves
// to the glass dock and a trail of questions grows above it. Every question is
// still sent to /api/chat on its own; the trail is kept only in this page.

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
  /** Spark topic, for example "⚡ Electricity", when a trail began from one. */
  topic?: string;
  answer?: string;
  followUps?: string[];
  error?: string;
  /** The next question asked from this step (shown as ↳ when folded). */
  chosen?: string;
  /** Seconds from asking to the answer arriving, as the child waited. */
  seconds?: number;
}

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
  question: HTMLTextAreaElement;
  'question-form': HTMLFormElement;
  ask: HTMLButtonElement;
  cancel: HTMLButtonElement;
  fresh: HTMLElement;
  'fresh-compose': HTMLDivElement;
  'dock-compose': HTMLDivElement;
  trail: HTMLElement;
  'new-spark': HTMLDivElement;
  'spark-grid': HTMLDivElement;
  'spark-chips': HTMLDivElement;
  'sparks-status': HTMLParagraphElement;
  'new-sparks': HTMLButtonElement;
  dice: HTMLButtonElement;
  'ask-own': HTMLButtonElement;
  undo: HTMLDivElement;
  'undo-button': HTMLButtonElement;
  title: HTMLHeadingElement;
  subtitle: HTMLParagraphElement;
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

const reduceMotion = () => window.matchMedia('(prefers-reduced-motion: reduce)').matches;
/** Phones keep the question box in the dock even on the fresh screen. */
const phoneQuery = window.matchMedia('(max-width: 600px)');

// ---- State ---------------------------------------------------------------

let steps: Step[] = [];
let undoSteps: Step[] | null = null;
let undoTimer: ReturnType<typeof setTimeout> | undefined;
let expanded = new Set<number>();
let nextStepId = 1;
let controller: AbortController | null = null;
let composeIn: 'fresh' | 'dock' | null = null;

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

function renderSparks() {
  const cards = sparks.map(spark => {
    const card = element('button', 'spark-card');
    card.type = 'button';
    const label = element('span', 'spark-topic', `${spark.icon} ${spark.topic}`);
    const question = element('span', 'spark-question', spark.question);
    card.append(label, question);
    card.setAttribute('aria-label', spark.question);
    card.addEventListener('click', () => startTrail(spark));
    editFirst(card, spark.question);
    return card;
  });
  $('spark-grid').replaceChildren(...cards);
  const chips = sparks.slice(0, 3).map(spark => {
    const chip = element('button', 'pill glass spark-chip', `${spark.icon} ${spark.question}`);
    chip.type = 'button';
    chip.setAttribute('aria-label', spark.question);
    chip.addEventListener('click', () => startTrail(spark));
    editFirst(chip, spark.question);
    return chip;
  });
  $('spark-chips').replaceChildren(...chips);
  updateControls();
}

// ---- Asking --------------------------------------------------------------

function startTrail(spark: Spark) {
  if (controller) return;
  sparks = sparks.filter(item => item.id !== spark.id);
  void ask(spark.question, { newTrail: true, topic: `${spark.icon} ${spark.topic}` });
}

/** "Ask your own": a new, empty trail with the question box in the centre. */
function askOwn() {
  if (controller) return;
  replaceTrail();
  show(() => render());
  $('question').value = '';
  updateControls();
}

function replaceTrail() {
  stopSpeech();
  undoSteps = steps.some(step => step.answer) ? steps : null;
  steps = [];
  expanded = new Set();
  showUndo();
}

function showUndo() {
  clearTimeout(undoTimer);
  $('undo').hidden = !undoSteps;
  if (undoSteps) undoTimer = setTimeout(() => { undoSteps = null; $('undo').hidden = true; }, 6000);
}

function undo() {
  if (!undoSteps) return;
  controller?.abort('undo');
  steps = undoSteps;
  undoSteps = null;
  showUndo();
  show(() => render());
}

async function ask(question: unknown, options: { newTrail?: boolean; topic?: string } = {}) {
  if (controller) throw new Error('A question is already being answered.');
  if (typeof question !== 'string' || !question.trim() || question.trim().length > 2000) throw new Error('Enter a question between 1 and 2,000 characters.');
  const asked = question.trim();
  const wasFresh = steps.length === 0;
  if (options.newTrail) replaceTrail();
  if (steps.length) steps[steps.length - 1].chosen = asked;
  const step: Step = { id: nextStepId++, question: asked, topic: options.topic };
  steps.push(step);
  expanded = new Set();
  if ($('question').value.trim() === asked) $('question').value = '';
  stopSpeech();

  const current = new AbortController();
  controller = current;
  const started = Date.now();
  const timer = setTimeout(() => current.abort('timeout'), 125000);
  $('status').textContent = 'Exploring your question…';
  if (wasFresh || options.newTrail) show(() => render()); else render();
  scrollToLatest();
  try {
    const response = await fetch('/api/chat', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ question: asked }), signal: current.signal });
    const data: ChatResponse = await response.json();
    if (!response.ok) throw new Error(typeof data.error === 'string' ? data.error : 'Something went wrong. Please try again.');
    if (typeof data.answer !== 'string' || !data.answer.trim()) throw new Error('No answer came back. Please try again.');
    step.answer = data.answer;
    step.seconds = (Date.now() - started) / 1000;
    step.followUps = Array.isArray(data.followUps) ? data.followUps.filter((q: unknown): q is string => typeof q === 'string' && !!q.trim()).slice(0, 3) : [];
    $('status').textContent = `Answered in ${((typeof data.elapsedMs === 'number' ? data.elapsedMs : 0) / 1000).toFixed(1)} seconds.`;
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
    if (steps.length === 0) show(() => render()); else render();
  }
}

function retry() {
  const last = steps[steps.length - 1];
  if (!last?.error || controller) return;
  steps = steps.slice(0, -1);
  void ask(last.question, { topic: last.topic });
}

// ---- Rendering -----------------------------------------------------------

/** Runs a layout change as a View Transition, so the question box glides
 *  between the centre and the dock where the browser supports it. */
function show(update: () => void) {
  if (typeof document.startViewTransition === 'function' && !reduceMotion()) document.startViewTransition(update);
  else update();
}

function render() {
  const fresh = steps.length === 0;
  const centred = fresh && !phoneQuery.matches;
  document.body.setAttribute('data-view', fresh ? 'fresh' : 'trail');
  document.body.setAttribute('data-dock', centred ? 'off' : 'on');
  $('fresh').hidden = !fresh;
  $('trail').hidden = fresh;
  $('new-spark').hidden = fresh;
  const target = centred ? 'fresh' : 'dock';
  if (composeIn !== target) {
    $(centred ? 'fresh-compose' : 'dock-compose').append($('question-form'));
    composeIn = target;
  }
  $('question').placeholder = fresh ? 'Ask a science question…' : 'Ask more about this…';
  $('title').textContent = steps[0]?.question ?? 'Curio';
  $('subtitle').textContent = controller ? 'Thinking…' : steps.length > 1 ? `${steps.length} steps` : '';
  renderTrail();
  updateControls();
}

function renderTrail() {
  const latestId = steps[steps.length - 1]?.id;
  $('trail').replaceChildren(...steps.map((step, index) =>
    step.id === latestId || expanded.has(step.id)
      ? openStep(step, step.id === latestId, index === 0)
      : foldedStep(step)));
}

function foldedStep(step: Step) {
  const button = element('button', 'step-folded');
  button.type = 'button';
  button.setAttribute('aria-expanded', 'false');
  const head = element('span', 'folded-question', step.question);
  button.append(head);
  if (step.answer) button.append(element('span', 'folded-preview', step.answer));
  if (step.chosen) button.append(element('span', 'chosen', `↳ ${step.chosen}`));
  button.addEventListener('click', () => { expanded.add(step.id); renderTrail(); updateControls(); });
  return button;
}

function openStep(step: Step, latest: boolean, first: boolean) {
  const article = element('article', latest ? 'step latest' : 'step');
  article.id = `step-${step.id}`;
  if (first && step.topic) article.append(element('p', 'step-topic', step.topic));
  const head = element('div', 'step-head');
  head.append(element('h2', 'step-question', step.question));
  if (step.answer && localVoice()) {
    const speak = element('button', 'round glass speak');
    speak.type = 'button';
    const on = speakingStep === step.id;
    speak.setAttribute('aria-label', on ? 'Stop reading' : 'Read aloud');
    speak.setAttribute('aria-pressed', String(on));
    speak.innerHTML = on ? stopIcon : speakerIcon;
    speak.addEventListener('click', () => toggleSpeech(step));
    head.append(speak);
  }
  if (!latest) {
    const fold = element('button', 'round fold', '⌃');
    fold.type = 'button';
    fold.setAttribute('aria-label', 'Fold');
    fold.addEventListener('click', () => { expanded.delete(step.id); renderTrail(); updateControls(); });
    head.append(fold);
  }
  article.append(head);

  if (step.error) {
    const error = element('div', 'error');
    error.setAttribute('role', 'alert');
    error.append(element('p', undefined, step.error));
    if (latest) {
      const again = element('button', 'pill', 'Try again');
      again.type = 'button';
      again.addEventListener('click', retry);
      error.append(again);
    }
    article.append(error);
  } else if (step.answer === undefined) {
    const loading = element('div', 'loading');
    loading.append(element('span', 'spinner'), element('span', undefined, 'Working on your answer…'));
    article.append(loading);
  } else {
    article.append(element('div', 'answer', step.answer));
    // Shows unusual delays at a glance (network included).
    if (step.seconds !== undefined) article.append(element('p', 'answered-in', `Answered in ${step.seconds.toFixed(1)} seconds`));
    if (latest && step.followUps?.length) {
      const dive = element('section', 'dive');
      dive.append(element('h3', undefined, 'Dive deeper'));
      const rows = element('div', 'dive-rows');
      for (const followUp of step.followUps) {
        const row = element('button', 'follow-up');
        row.type = 'button';
        row.append(element('span', undefined, followUp), element('span', 'chevron', '›'));
        row.setAttribute('aria-label', followUp);
        row.addEventListener('click', () => { if (!controller) void ask(followUp); });
        editFirst(row, followUp);
        rows.append(row);
      }
      dive.append(rows);
      article.append(dive);
    } else if (step.chosen) {
      article.append(element('p', 'chosen', `↳ ${step.chosen}`));
    }
  }
  return article;
}

/** Puts the new step's question at the top, just under the toolbar. The latest
 *  step is at least a screen tall (CSS), so there is always room to get there. */
function scrollToLatest() {
  const latest = steps[steps.length - 1];
  if (!latest) return;
  const frame = window.requestAnimationFrame ?? ((callback: () => void) => setTimeout(callback, 16));
  frame(() => document.getElementById(`step-${latest.id}`)?.scrollIntoView({ block: 'start', behavior: reduceMotion() ? 'auto' : 'smooth' }));
}

function updateControls() {
  const busy = !!controller;
  $('ask').disabled = busy || !$('question').value.trim();
  $('ask').hidden = busy;
  $('cancel').hidden = !busy;
  $('new-sparks').disabled = busy || sparksLoading;
  $('dice').disabled = busy || sparksLoading;
  $('ask-own').disabled = busy;
  document.querySelectorAll<HTMLButtonElement>('.spark-card, .spark-chip, .follow-up').forEach(button => { button.disabled = busy; });
  $('subtitle').textContent = busy ? 'Thinking…' : steps.length > 1 ? `${steps.length} steps` : '';
  document.getElementById('main')?.setAttribute('aria-busy', String(busy));
}

// ---- Read aloud ----------------------------------------------------------

// Constant inline icons (no user text), styled with currentColor.
const speakerIcon = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M11 5 6 9H2v6h4l5 4V5z"/><path d="M15.5 8.5a5 5 0 0 1 0 7"/><path d="M19 5a10 10 0 0 1 0 14"/></svg>';
const stopIcon = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><rect x="6" y="6" width="12" height="12" rx="2"/></svg>';

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

// ---- Wiring --------------------------------------------------------------

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
$('dice').addEventListener('click', () => { void refreshSparks(); });
$('ask-own').addEventListener('click', askOwn);
$('undo-button').addEventListener('click', undo);
synthesis?.addEventListener('voiceschanged', renderTrail);
window.addEventListener('pagehide', () => { controller?.abort('cancel'); stopSpeech(); });
phoneQuery.addEventListener?.('change', () => render());

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
