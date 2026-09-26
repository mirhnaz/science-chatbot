# Frontend layout and themes

The frontend remains plain TypeScript, HTML, and CSS. This single-screen change
needs no React dependency. React + TypeScript + Vite remains the agreed direction
when account/history screens make shared state and reusable components useful.

- `public/index.html` contains the semantic page structure and controls.
- `public/styles.css` contains color tokens, component styles, and responsive rules.
- `src/client/app.ts` handles chat, suggestions, cancellation, and speech.
- `src/client/theme.ts` handles Light/Dark/System selection independently.

Run `npm run build:frontend` after TypeScript changes. Both compiled scripts are
served through the Rust asset allowlist. The theme script runs before CSS so a
saved preference is applied before painting; no inline scripts or relaxed CSP
are needed. The default follows the OS. Explicit choices persist in localStorage
under `science-chatbot.theme.v1`; blocked storage still permits in-page selection.

At desktop widths of at least 900 CSS pixels and heights of at least 600, the
workspace fills the available viewport. The question and answer sit side by side;
long answers scroll within a keyboard-focusable region. Follow-ups and answer
actions sit outside that region. Very long follow-ups or unusually cramped windows
can require panel scrolling. Do not hide overflow globally: all content must stay
reachable. On smaller screens/high zoom, panels stack and the page scrolls normally.

Keep answer text at 16px and retain visible keyboard focus, labeled controls,
reduced-motion support, and theme contrast. Change shared color tokens rather
than scattering literal colors through component styles. Check both themes at
1280×720 and 1024×650, plus 390px/320px narrow screens, with long answers, follow-ups,
loading/errors, and long starter text. Browser viewport dimensions exclude browser
chrome; physical screen resolution is not the available page height.

Deployment of this milestone needs a service restart for the new `/theme.js`
route. The live checkout supplies assets directly; rebuilding the binary alone
does not replace the running process. Do not modify Funnel or the systemd unit.
