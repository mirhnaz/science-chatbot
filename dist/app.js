const $ = (id) => document.getElementById(id);
const topics = {
  electricity: 'How does electricity make a light bulb glow?',
  light: 'Why is the sky blue?',
  gravity: 'What is gravity? Answer for a 10 year old.',
  sound: 'How does sound travel from a drum to my ears?'
};
let controller = null, answerText = '', speaking = false;
const synthesis = window.speechSynthesis;
function localVoice() { return synthesis?.getVoices().find(v => v.localService && /^en(?:-|_)/i.test(v.lang)); }
function updateRead() { $('read').disabled = !answerText || !!controller || !localVoice(); }
function stopSpeech() { synthesis?.cancel(); speaking = false; $('read').innerHTML = '<span aria-hidden="true">◖))</span> Read aloud'; }
function setBusy(busy) {
  $('ask').disabled = busy;
  $('question').disabled = busy;
  document.querySelectorAll('.topic, .follow-up').forEach(el => { el.disabled = busy; });
  $('cancel').hidden = !busy;
  $('answer-panel').setAttribute('aria-busy', String(busy));
  updateRead();
}
async function ask(question) {
  if (controller) throw new Error('A question is already being answered.');
  if (typeof question !== 'string' || !question.trim() || question.trim().length > 2000) throw new Error('Enter a question between 1 and 2,000 characters.');
  question = question.trim();
  $('question').value = question;
  stopSpeech(); answerText = '';
  $('question').setCustomValidity('');
  $('follow-ups').hidden = true; $('follow-up-list').replaceChildren();
  controller = new AbortController();
  const timer = setTimeout(() => controller?.abort('timeout'), 125000);
  $('empty').hidden = true; $('answer').hidden = true; $('error').hidden = true; $('loading').hidden = false;
  $('status').textContent = 'Exploring your question…';
  $('speech-note').hidden = true;
  setBusy(true);
  try {
    const response = await fetch('/api/chat', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ question }), signal: controller.signal });
    const data = await response.json();
    if (!response.ok) throw new Error(data.error || 'Something went wrong. Please try again.');
    if (typeof data.answer !== 'string' || !data.answer.trim()) throw new Error('No answer came back. Please try again.');
    answerText = data.answer;
    $('asked-question').textContent = question;
    $('answer-text').textContent = answerText;
    $('answer').hidden = false;
    const followUps = Array.isArray(data.followUps) ? data.followUps.filter(q => typeof q === 'string' && q.trim()).slice(0, 3) : [];
    for (const suggestion of followUps) {
      const button = document.createElement('button');
      button.type = 'button'; button.className = 'follow-up secondary';
      button.textContent = suggestion; button.disabled = true;
      button.addEventListener('click', () => { if (!controller) void ask(suggestion); });
      $('follow-up-list').append(button);
    }
    $('follow-ups').hidden = followUps.length !== 3;
    $('status').textContent = `Answered in ${(data.elapsedMs / 1000).toFixed(1)} seconds.`;
    if (!localVoice()) { $('speech-note').textContent = 'Read aloud is unavailable in this browser. You can still read your answer above.'; $('speech-note').hidden = false; }
    $('answer').focus({ preventScroll: true });
    if (window.matchMedia('(max-width: 780px)').matches) $('answer-panel').scrollIntoView({ behavior: window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'instant' : 'smooth', block: 'start' });
    return { question, answer: answerText, followUps };
  } catch (error) {
    if (controller.signal.aborted && controller.signal.reason !== 'timeout') {
      $('empty').hidden = false; $('status').textContent = 'Stopped. Try another question whenever you’re ready.';
    } else {
      $('error').textContent = controller.signal.aborted ? 'That answer took too long. Please try again.' : error.message === 'Failed to fetch' ? 'We couldn’t reach your science tutor. Please check the connection and try again.' : error.message;
      $('error').hidden = false; $('status').textContent = 'Ready to try again.';
    }
    return { error: $('error').hidden ? 'Question cancelled.' : $('error').textContent };
  } finally { clearTimeout(timer); controller = null; $('loading').hidden = true; setBusy(false); }
}
$('question-form').addEventListener('submit', (event) => { event.preventDefault(); if (!$('question').value.trim()) { $('question').setCustomValidity('Type a science question first.'); $('question').reportValidity(); return; } void ask($('question').value); });
$('question').addEventListener('input', () => $('question').setCustomValidity(''));
$('question').addEventListener('keydown', (event) => { if ((event.ctrlKey || event.metaKey) && event.key === 'Enter') $('question-form').requestSubmit(); });
document.querySelectorAll('[data-topic]').forEach(button => button.addEventListener('click', () => { $('question').value = topics[button.dataset.topic]; $('question').setCustomValidity(''); $('question').focus(); }));
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
  for (const tool of [
    { name: 'ask_science_question', title: 'Ask a science question', description: 'Send a science question to the private Qwen tutor and show the answer on this page. This transmits the question to the configured tutor computer.', inputSchema: { type: 'object', properties: { question: { type: 'string', minLength: 1, maxLength: 2000 } }, required: ['question'], additionalProperties: false }, annotations: { readOnlyHint: false, untrustedContentHint: true }, execute: async (input) => ask(input?.question) },
    { name: 'read_science_answer', title: 'Read the current science answer', description: 'Return the question and answer currently displayed, without making another model request.', inputSchema: { type: 'object', properties: {}, additionalProperties: false }, annotations: { readOnlyHint: true, untrustedContentHint: true }, execute: async () => ({ question: $('asked-question').textContent, answer: answerText, busy: !!controller }) }
  ]) { try { Promise.resolve(document.modelContext.registerTool(tool, { signal: toolsLifecycle.signal })).catch(() => {}); } catch {} }
  window.addEventListener('pagehide', () => toolsLifecycle.abort());
}
