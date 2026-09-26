interface AppElements {
  question: HTMLTextAreaElement;
  'topic-grid': HTMLDivElement;
  'suggestions-status': HTMLParagraphElement;
  'surprise': HTMLButtonElement;
  'question-form': HTMLFormElement;
  ask: HTMLButtonElement;
  cancel: HTMLButtonElement;
  read: HTMLButtonElement;
  'answer-panel': HTMLElement;
  'answer-scroll': HTMLDivElement;
  'follow-ups': HTMLElement;
  'follow-up-list': HTMLDivElement;
  empty: HTMLDivElement;
  answer: HTMLElement;
  error: HTMLDivElement;
  loading: HTMLDivElement;
  status: HTMLParagraphElement;
  'speech-note': HTMLParagraphElement;
  'asked-question': HTMLParagraphElement;
  'answer-text': HTMLDivElement;
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

interface ChatResponse {
  answer?: unknown;
  error?: unknown;
  followUps?: unknown;
  elapsedMs?: unknown;
}

function $<K extends keyof AppElements>(id: K): AppElements[K] {
  const element = document.getElementById(id);
  if (!element) throw new Error(`Missing page element: ${id}`);
  return element as AppElements[K];
}
interface StarterSuggestion { id: string; topic: string; icon: string; question: string }
const recentSuggestionsKey = 'science-chatbot.recent-suggestions.v1';
const recentSuggestionsLimit = 40;
let recentSuggestions: string[] = [];
try {
  const stored: unknown = JSON.parse(sessionStorage.getItem(recentSuggestionsKey) || '[]');
  if (Array.isArray(stored)) recentSuggestions = stored.filter((id): id is string => typeof id === 'string' && /^[a-z0-9-]{1,64}$/.test(id)).slice(-recentSuggestionsLimit);
} catch { /* Browsers may disable storage; in-memory rotation still works. */ }
let suggestionsLoading = false;

function isStarter(value: unknown): value is StarterSuggestion {
  if (!value || typeof value !== 'object') return false;
  const item = value as Record<string, unknown>;
  return typeof item.id === 'string' && /^[a-z0-9-]{1,64}$/.test(item.id)
    && typeof item.topic === 'string' && !!item.topic.trim()
    && typeof item.icon === 'string' && !!item.icon.trim()
    && typeof item.question === 'string' && !!item.question.trim() && item.question.length <= 2000;
}

async function refreshSuggestions() {
  if (suggestionsLoading || controller) return;
  suggestionsLoading = true;
  $('surprise').disabled = true;
  $('topic-grid').setAttribute('aria-busy', 'true');
  $('suggestions-status').className = 'sr-only';
  $('suggestions-status').textContent = 'Finding new things to explore…';
  const request = new AbortController();
  const timer = setTimeout(() => request.abort(), 8000);
  try {
    const exclude = encodeURIComponent(recentSuggestions.join(','));
    const response = await fetch(`/api/suggestions?exclude=${exclude}`, { signal: request.signal });
    if (!response.ok) throw new Error('Suggestions unavailable');
    const data: unknown = await response.json();
    const items = data && typeof data === 'object' ? (data as Record<string, unknown>).suggestions : undefined;
    if (!Array.isArray(items) || items.length !== 4 || !items.every(isStarter)
      || new Set(items.map(item => item.id)).size !== 4 || new Set(items.map(item => item.topic)).size !== 4) throw new Error('Invalid suggestions');
    const buttons = items.map(item => {
      const button = document.createElement('button');
      button.type = 'button'; button.className = 'topic'; button.disabled = !!controller;
      const label = document.createElement('span'); label.className = 'topic-label';
      const icon = document.createElement('span'); icon.className = 'topic-icon'; icon.textContent = item.icon; icon.setAttribute('aria-hidden', 'true');
      const topic = document.createElement('span'); topic.textContent = item.topic;
      label.append(icon, topic);
      const question = document.createElement('span'); question.className = 'topic-question'; question.textContent = item.question;
      button.append(label, question);
      button.addEventListener('click', () => {
        if (controller) return;
        $('question').value = item.question;
        $('question').setCustomValidity(''); $('question').focus();
      });
      return button;
    });
    $('topic-grid').replaceChildren(...buttons);
    recentSuggestions = [...new Set([...recentSuggestions, ...items.map(item => item.id)])].slice(-recentSuggestionsLimit);
    try { sessionStorage.setItem(recentSuggestionsKey, JSON.stringify(recentSuggestions)); } catch { /* Optional storage. */ }
    $('suggestions-status').textContent = 'Pick a question, then press Ask. Or try four new ideas!';
  } catch {
    $('suggestions-status').className = 'suggestions-error';
    $('suggestions-status').textContent = 'Couldn’t load new ideas. Try Surprise me again, or type your own question.';
  } finally {
    clearTimeout(timer); suggestionsLoading = false;
    $('surprise').disabled = !!controller;
    $('topic-grid').setAttribute('aria-busy', 'false');
  }
}
let controller: AbortController | null = null;
let answerText = '', speaking = false;
const synthesis = window.speechSynthesis;
function localVoice() { return synthesis?.getVoices().find(v => v.localService && /^en(?:-|_)/i.test(v.lang)); }
function updateRead() { $('read').disabled = !answerText || !!controller || !localVoice(); }
function stopSpeech() { synthesis?.cancel(); speaking = false; $('read').innerHTML = '<span aria-hidden="true">◖))</span> Read aloud'; }
function setBusy(busy: boolean) {
  $('ask').disabled = busy;
  $('surprise').disabled = busy || suggestionsLoading;
  $('question').disabled = busy;
  document.querySelectorAll<HTMLButtonElement>('.topic, .follow-up').forEach(el => { el.disabled = busy; });
  $('cancel').hidden = !busy;
  $('answer-panel').setAttribute('aria-busy', String(busy));
  updateRead();
}
async function ask(question: unknown) {
  if (controller) throw new Error('A question is already being answered.');
  if (typeof question !== 'string' || !question.trim() || question.trim().length > 2000) throw new Error('Enter a question between 1 and 2,000 characters.');
  const normalizedQuestion = question.trim();
  $('question').value = normalizedQuestion;
  stopSpeech(); answerText = '';
  $('question').setCustomValidity('');
  $('follow-ups').hidden = true; $('follow-up-list').replaceChildren();
  controller = new AbortController();
  const timer = setTimeout(() => controller?.abort('timeout'), 125000);
  $('answer-scroll').scrollTop = 0;
  $('empty').hidden = true; $('answer').hidden = true; $('error').hidden = true; $('loading').hidden = false;
  $('status').textContent = 'Exploring your question…';
  $('speech-note').hidden = true;
  setBusy(true);
  try {
    const response = await fetch('/api/chat', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ question: normalizedQuestion }), signal: controller.signal });
    const data: ChatResponse = await response.json();
    if (!response.ok) throw new Error(typeof data.error === 'string' ? data.error : 'Something went wrong. Please try again.');
    if (typeof data.answer !== 'string' || !data.answer.trim()) throw new Error('No answer came back. Please try again.');
    answerText = data.answer;
    $('asked-question').textContent = normalizedQuestion;
    $('answer-text').textContent = answerText;
    $('answer').hidden = false;
    const followUps = Array.isArray(data.followUps) ? data.followUps.filter((q: unknown): q is string => typeof q === 'string' && !!q.trim()).slice(0, 3) : [];
    for (const suggestion of followUps) {
      const button = document.createElement('button');
      button.type = 'button'; button.className = 'follow-up secondary';
      button.textContent = suggestion; button.disabled = true;
      button.addEventListener('click', () => { if (!controller) void ask(suggestion); });
      $('follow-up-list').append(button);
    }
    $('follow-ups').hidden = followUps.length !== 3;
    $('status').textContent = `Answered in ${((typeof data.elapsedMs === 'number' ? data.elapsedMs : 0) / 1000).toFixed(1)} seconds.`;
    if (!localVoice()) { $('speech-note').textContent = 'Read aloud is unavailable in this browser. You can still read your answer above.'; $('speech-note').hidden = false; }
    $('answer-scroll').scrollTop = 0;
    $('answer').focus({ preventScroll: true });
    if (window.matchMedia('(max-width: 899px)').matches) $('answer-panel').scrollIntoView({ behavior: window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'instant' : 'smooth', block: 'start' });
    return { question: normalizedQuestion, answer: answerText, followUps };
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Something went wrong. Please try again.';
    if (controller.signal.aborted && controller.signal.reason !== 'timeout') {
      $('empty').hidden = false; $('status').textContent = 'Stopped. Try another question whenever you’re ready.';
    } else {
      $('error').textContent = controller.signal.aborted ? 'That answer took too long. Please try again.' : message === 'Failed to fetch' ? 'We couldn’t reach your science tutor. Please check the connection and try again.' : message;
      $('error').hidden = false; $('status').textContent = 'Ready to try again.';
    }
    return { error: $('error').hidden ? 'Question cancelled.' : $('error').textContent };
  } finally { clearTimeout(timer); controller = null; $('loading').hidden = true; setBusy(false); }
}
$('question-form').addEventListener('submit', (event) => { event.preventDefault(); if (!$('question').value.trim()) { $('question').setCustomValidity('Type a science question first.'); $('question').reportValidity(); return; } void ask($('question').value); });
$('question').addEventListener('input', () => $('question').setCustomValidity(''));
$('question').addEventListener('keydown', (event) => { if ((event.ctrlKey || event.metaKey) && event.key === 'Enter') $('question-form').requestSubmit(); });
$('surprise').addEventListener('click', () => { void refreshSuggestions(); });
void refreshSuggestions();
$('cancel').addEventListener('click', () => controller?.abort());
$('read').addEventListener('click', () => {
  if (speaking) return stopSpeech();
  const voice = localVoice();
  if (!answerText || !voice) return;
  const utterance = new SpeechSynthesisUtterance(answerText);
  utterance.voice = voice; utterance.lang = voice.lang; utterance.rate = .92;
  utterance.onend = stopSpeech;
  utterance.onerror = () => { stopSpeech(); $('speech-note').textContent = 'Read aloud could not start. Please try again.'; $('speech-note').hidden = false; };
  speaking = true; $('read').textContent = 'Stop reading'; synthesis.speak(utterance);
});
synthesis?.addEventListener('voiceschanged', updateRead);
window.addEventListener('pagehide', () => { controller?.abort(); stopSpeech(); });
const toolsLifecycle = new AbortController();
if (document.modelContext?.registerTool) {
  const scienceTools: ScienceTool[] = [
    { name: 'ask_science_question', title: 'Ask a science question', description: 'Send a science question to the private Qwen tutor and show the answer on this page. This transmits the question to the configured tutor computer.', inputSchema: { type: 'object', properties: { question: { type: 'string', minLength: 1, maxLength: 2000 } }, required: ['question'], additionalProperties: false }, annotations: { readOnlyHint: false, untrustedContentHint: true }, execute: async (input) => ask(input?.question) },
    { name: 'read_science_answer', title: 'Read the current science answer', description: 'Return the question and answer currently displayed, without making another model request.', inputSchema: { type: 'object', properties: {}, additionalProperties: false }, annotations: { readOnlyHint: true, untrustedContentHint: true }, execute: async () => ({ question: $('asked-question').textContent, answer: answerText, busy: !!controller }) }
  ];
  for (const tool of scienceTools) { try { Promise.resolve(document.modelContext.registerTool(tool, { signal: toolsLifecycle.signal })).catch(() => {}); } catch {} }
  window.addEventListener('pagehide', () => toolsLifecycle.abort());
}
