# Curated starter questions

The “Need a spark?” section uses a curated question bank, not model-generated
suggestions. The follow-ups attached to an AI answer still come from Ollama.
No database or new production service is needed.

## Edit the bank

Edit `backend/data/questions.json`. Each object contains:

```json
{
  "id": "space-1",
  "topic": "Space",
  "icon": "🚀",
  "question": "Why do astronauts float in space?"
}
```

Use stable, unique lowercase IDs with digits/hyphens (at most 64 characters).
Keep questions short, self-contained, age-appropriate, and suitable for the
existing science tutor. Avoid instructions for hazardous experiments. Keep the
same topic label for all questions in a category so selection can distinguish
categories correctly. IDs should continue to identify the same question.

The initial collection is 10 topics with six questions each: Space, Animals,
Plants, Weather, Light, Sound, Electricity, Earth, Matter, and Forces & motion.
The bank tests explicitly check that initial inventory; when deliberately
expanding it, update those count expectations and preserve the diversity and
exclusion tests. No schema change is required for additional entries.

`include_str!` embeds the file into the Rust executable, and `OnceLock` parses
it once on first use. Editing the JSON requires a rebuild and service restart;
editing a deployed file alone does not update a running binary. Run the checks
in [VERIFICATION.md](VERIFICATION.md) and deploy per [INSTALL.md](INSTALL.md).

## API and selection

`GET /api/suggestions?exclude=space-1,light-2` returns:

```json
{
  "suggestions": [
    { "id": "plants-1", "topic": "Plants", "icon": "🌱", "question": "How do plants know which way to grow?" }
  ]
}
```

The example shows one entry for brevity; a real response contains four entries
from four different topics. Responses use `Cache-Control: no-store` and the
app's existing security headers. Other methods get `405` with `Allow: GET`.
The endpoint accepts at most 40 excluded IDs of up to 64 characters each and a
query string of at most 3,000 bytes; larger inputs get a friendly `400`.
Unknown IDs have no effect.

A newly seeded standard-library hash randomizes the ordering of the small bank.
This randomness is for variety, not security. Unseen entries are considered first,
then one question per topic is picked. With the current balanced 60-question bank
and the 40-ID limit, four unseen topics are always available. If the catalogue is
later reduced, the selector can reuse excluded entries to fill the result.

## Browser behavior

The page requests a batch on load and on “Surprise me.” It stores only the last
40 displayed catalogue IDs under `science-chatbot.recent-suggestions.v1` in
`sessionStorage`. This survives reloads in the same tab and does not create an
account, server-side profile, or saved conversation. If storage is unavailable,
the same page still keeps recent IDs in memory.

Refreshing does not overwrite a drafted question. Clicking a card fills and
focuses the input but does not call Ollama. During a chat request, starter cards
and Surprise me are disabled. Duplicate refreshes are ignored while one is active.

A suggestions request times out after eight seconds. Failed or malformed replies
leave any existing cards and the draft intact and show a retry message. The child
can always type a question manually. Browser code creates text nodes, not HTML,
from the bank's labels and questions.
