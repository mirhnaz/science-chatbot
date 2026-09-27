# Frontend: Home, Trail, Trail complete

The web page follows [DESIGN.md](DESIGN.md) (tokens) and the 2026-09 redesign
artboards in `docs/design/redesign-2026-09/`, the same as the iOS app. It
stays plain TypeScript, HTML, and CSS: three screens with modest state need
no React, and plain files keep the Rust asset allowlist and CSP simple.
React + TypeScript + Vite remains the agreed direction when account/history
screens make shared state and reusable components useful.

- `public/index.html`: Home, Trail and Trail complete sections, the bottom
  bar (question box), the Settings dialog (first name, theme), and Undo.
- `public/styles.css`: tokens (see DESIGN.md), self-hosted Fredoka/Nunito
  (`public/fonts/`), and the screen styles.
- `src/client/app.ts`: sparks, the trail (rail, current step, Dive deeper,
  Finish), Trail complete (recap, stamps, Show a grown-up), asking,
  Stop/Try again/Undo, and read aloud. Icons are constant inline SVG.
- `src/client/theme.ts`: Light/Dark/System, applied before the first paint.

## Behaviour

- **Home**: greeting ("today" or "tonight", with the first name from
  Settings), "Continue your trail" while a trail is unfinished (five dots,
  step, Keep going), four tinted Sparks with Shuffle, and the credit line. A
  spark asks at once and starts a new trail; right-click or long-press fills
  the box instead. A question typed on Home also starts a new trail.
- **Trail**: header (Back, topic, "Trail · Step N", Settings); earlier steps
  as a numbered rail that re-opens an answer; the current question, a
  category illustration, the answer, and Dive deeper (two choices on phones,
  all three when wide). Typing continues the trail. Back keeps the trail.
- **Five steps** make a trail: after the fifth answer Finish replaces the
  question box and opens **Trail complete**: the stamp, three recap facts
  (first sentences of the first, middle, and last answers), the latest four
  stamps and a total, Start a new spark, and Show a grown-up.
- **Show a grown-up** shares the recap card as a PNG plus the trail's
  questions as text (Web Share with files); otherwise it downloads the
  picture and copies the questions.
- **Wide layouts**: at ≥1100 px Home becomes two columns (with "Trails you
  finished" and a stamps count) and the Trail gets a side rail showing every
  step, the steps still to come, and "So far you know"; at ≥1400 px a nav
  (Home, My trails, profile chip) is added. See DESIGN.md → Screens.
- **Undo**: a new trail shows "Started a new trail · Undo" for six seconds.
- **Stop** removes the unanswered step and puts the question back in the
  box. Errors show in the step with **Try again**.
- **Read aloud** is a button on each answer when the browser has a local
  English voice.

Every question is still sent to `/api/chat` on its own. Browser storage: recent spark IDs in sessionStorage
(`curio.recent-suggestions.v1`); in localStorage the theme
(`curio.theme.v1`), first name (`curio.name.v1`), stamps (`curio.stamps.v1`:
trail ID, topic, date) and finished trails (`curio.trails.v1`: trail ID,
topic, first question, date; last 100), and the unfinished trail
(`curio.trail.v1`: its answered steps with questions, answers and the
tutor's extras; forgotten after 7 days or when finished). Wide windows ask
for six sparks (`count=6`). The page uses the reply's optional `label`,
`trailName`, and `fact` when present. There is no microphone on the web.

## Checks

Run `npm run build:frontend` after TypeScript changes. Keep visible keyboard
focus, labelled controls, reduced-motion and reduced-transparency/contrast
fallbacks, and theme contrast. Change shared colour tokens rather than
scattering literal colours. Check both themes at phone (390 px), iPad (1180 px) and
web (1440 px) widths with long answers, several steps, loading and errors. A
headless Chrome script driving the page over the DevTools protocol (with a
mock tutor on the dev server) was used for the 2026-09-27 screenshots.
