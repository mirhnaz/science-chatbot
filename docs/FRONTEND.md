# Frontend: the curiosity column

The web page follows the shared design in [DESIGN.md](DESIGN.md), the same as
the iPad app. It stays plain TypeScript, HTML, and CSS: one screen with modest
state needs no React, and plain files keep the Rust asset allowlist and CSP
unchanged. React + TypeScript + Vite remains the agreed direction when
account/history screens make shared state and reusable components useful.

- `public/index.html`: toolbar, fresh screen (hero, Sparks), trail, glass
  dock (New spark chips), the one question box, and the Undo banner.
- `public/styles.css`: colour tokens (light/dark, purple accent), glass, and
  responsive rules.
- `src/client/app.ts`: sparks, the trail (steps, folding, Dive deeper), asking,
  Stop/Try again/Undo, scrolling, and read aloud.
- `src/client/theme.ts`: Light/Dark/System, applied before the first paint.

## Behaviour

- **Fresh screen**: the question box and four Sparks sit in the centre. A spark
  asks at once and starts a trail; right-click or long-press fills the box
  instead. On the first question the box moves to the dock; browsers with View
  Transitions animate the move.
- **Trail**: steps stack in order. Only the latest is open; earlier steps fold
  to their question, a two-line preview, and the chosen follow-up (↳), and can
  be reopened. The latest step is at least a screen tall and is scrolled to just
  below the toolbar, so its answer fills in in view.
- **Dock**: "New spark" chips (✎ Ask your own, 🎲, three sparks) start a new
  trail; typing in the box continues the current one. Enter asks; Shift+Enter
  adds a line. The dock and toolbar blur content scrolling beneath them.
- **Undo**: a new trail shows "Started a new trail · Undo" for six seconds.
- **Stop** removes the unanswered step and puts the question back in the box.
  Errors show in the step with **Try again**.
- **Read aloud** is a button on each answer when the browser has a local English
  voice.

The trail exists only in the page; every question is still sent to `/api/chat`
on its own, so the API is unchanged. Recent spark IDs are kept in tab-scoped
sessionStorage under `curio.recent-suggestions.v1`. The theme persists in
localStorage under `curio.theme.v1` (the pre-rename key is read once).

## Checks

Run `npm run build:frontend` after TypeScript changes. Keep visible keyboard
focus, labelled controls, reduced-motion and reduced-transparency/contrast
fallbacks, and theme contrast. Change shared colour tokens rather than
scattering literal colours. Check both themes at laptop (1280×800) and phone
(390px) widths with long answers, several steps, loading and errors. A headless
Chrome script driving the page over the DevTools protocol was used for the
2026-09-26 screenshots (fresh, loading, answer, two-step trail, Ask your own,
Undo); the new step landed exactly below the toolbar at both widths.
