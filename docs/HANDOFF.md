# Project handoff

Updated: 2026-10-02. Read [../AGENTS.md](../AGENTS.md) for working rules.
This is a checkpoint, not a live service-status report. Check the current Git
state and relevant files after obtaining command authorization before changing
anything. Do not assume another agent has the preceding conversation.

## Current state

Curio (formerly Science Chatbot) is a self-hosted science tutor for children aged 10–12, created
by Ayaan and Naz Mir. It calls local Ollama with `qwen3:8b`. Questions are
independent; replies contain an answer and three clickable follow-up questions.
There is no login, database, persisted history, or response streaming yet.

- Rust/Axum backend is deployed. Tokio drives async work, reqwest calls Ollama,
  and serde_json handles JSON. The user confirmed the deployed app works.
- The frontend is plain TypeScript with HTML/CSS; React is not installed.
- The compact desktop workspace fits typical laptop viewports. Long answers
  scroll within their panel; small screens and high zoom reflow vertically.
  Light/Dark/System themes persist locally. See [FRONTEND.md](FRONTEND.md).
- The old TypeScript/Node backend, compiled Node server, fallback npm scripts,
  local Node unit copy, and one-time migration script have been removed.
- TypeScript tests run under Node and exercise the Rust binary through real
  sockets with a mock Ollama server. `node_modules/` is still needed for frontend
  compilation and tests; its presence does not mean a Node backend is running.
- Work is on `main`. Dynamic starter suggestions are implemented; check Git for
  the current commit/push state. Pushes remain explicit user requests.
- “Need a spark?” now loads four curated questions from different topics, with
  a “Surprise me” refresh button. Selecting a starter fills the input; Ask submits.
  The bank has 60 questions across 10 topics. No AI call generates these starters.
  The last 40 displayed catalogue IDs are kept in tab-scoped sessionStorage;
  blocked storage falls back to in-memory history. This is not saved chat history.


## Code map

| File | Responsibility |
| --- | --- |
| `backend/src/chat.rs` | Pure question/reply validation and error types |
| `backend/src/suggestions.rs` | Starter selection, recent exclusions, and bank tests |
| `backend/data/questions.json` | Editable curated question bank, embedded at build time |
| `backend/src/main.rs` | Environment settings, listener, runtime, shutdown signals |
| `backend/src/http.rs` | Routes, asset allowlist, shared client, concurrency, Ollama, responses |
| `backend/src/tutor.txt` | Embedded tutor system message |
| `backend/src/reply-schema.json` | Embedded structured response schema |
| `backend/tests/validation.rs` | Rust validation tests |
| `src/client/theme.ts` | Early theme selection, local preference, system changes |
| `test/theme.test.ts` | Theme persistence, system changes, storage failure tests |
| `src/client/app.ts` | Browser interactions, follow-ups, cancellation, read aloud |
| `test/server.test.ts` | Rust HTTP integration tests and mock Ollama server |
| `test/client.test.ts` | Browser interaction test |
| `tsconfig.client.json` | Frontend build to `build/client/app.js` |
| `tsconfig.test.json` | Test build to `build/test/`; replaces old `tsconfig.json` |

Start with `chat.rs`, then `main.rs`, then `http.rs` for a Rust walkthrough.
The user has discussed derive traits, Display implementations, and the roles of
these files. Explain each new concept plainly; do not assume mastery of earlier
topics or advanced concepts from other languages.

## Deployment and behavior to preserve

- System service: `science-chatbot-web.service`, running
  `backend/target/release/science-chatbot-server` from this repository.
- Public Tailscale Funnel forwards directly to `127.0.0.1:11436`. Although Caddy
  templates exist in the repository, Caddy is not in that verified public path.
- Development binary default: `127.0.0.1:11437`; Ollama: `127.0.0.1:11434`.
- `ASSET_ROOT` defaults to the working directory. The runtime needs `public/`
  and both `build/client/app.js` and `build/client/theme.js`. The service's `PUBLIC_ORIGIN` is configured locally;
  do not copy its personal hostname into tracked files.
- POST `/api/chat` accepts `question`; replies contain `answer`, `followUps`, and
  `elapsedMs`, plus optional `fact` (≤160), `label` (≤40), and `trailName`
  (≤30) when the model gave usable ones (never a reason to fail a reply).
  GET `/api/suggestions` takes `exclude` and `count` (4 or 6). Existing
  friendly errors, headers, and asset allowlist matter.
- Request limit: 8 KiB. Question/follow-up limits: 2,000/180 UTF-16 code units.
  Two simultaneous model requests are allowed; a third immediately gets 429.
  The complete upstream deadline is 120 seconds by default.
- Disconnects/timeouts release permits and close upstream HTTP work; shutdown
  cancels pending handlers. These are tested over sockets.
- Rust JSON parsing is deliberately stricter than JavaScript for unpaired
  surrogates, excessive nesting, and out-of-range numbers. See
  [RUST_MIGRATION.md](RUST_MIGRATION.md) for the precise compatibility decisions.

The installed service and Funnel were verified on 2026-09-24, including public
asset comparisons and a real question. The later source cleanup did not restart
or reconfigure them. Service modification may require the user to authenticate
locally; do not ask for a password in chat. See [INSTALL.md](INSTALL.md).

## Verification checkpoint

For dynamic suggestions, `npm test` passed 21 Rust checks and 23 HTTP/frontend
checks. TypeScript type checking, rustfmt, Clippy, and the release build passed.
Desktop and narrow viewport renders were visually checked. See
[VERIFICATION.md](VERIFICATION.md) and [QUESTION_BANK.md](QUESTION_BANK.md).
The user restarted the live service on 2026-09-26. Local/public suggestions
rotation, frontend assets, health, and a real starter-question answer passed.
Funnel remains unchanged on port 11436; the temporary 11437 server was stopped.
Future changes should run relevant checks after command authorization.


## Compact UI checkpoint (2026-09-26)

The UI now has a compact header, two desktop panels, and Light/Dark/System
selection. No new frontend dependencies or framework were needed. All 21 Rust
checks and 27 HTTP/frontend checks, type checking, rustfmt, Clippy, and the release
build passed. Chromium measurements covered laptop, mobile, and small/zoom-sized
viewports, including long answers; see [VERIFICATION.md](VERIFICATION.md).
The release binary includes the new `/theme.js` asset route. The live service
was restarted at 15:36 after that build; `/theme.js` returned 200 publicly. Static assets are
already updated because the live server reads this checkout. No Funnel or unit
configuration changed. Commit locally; push only when requested.

## iPad/iOS app checkpoint (2026-09-26)

`ios/` adds a native SwiftUI app for personal sideloading (not App Store). Ollama
cannot run inside an iOS app, so the offline mode embeds llama.cpp (pinned
xcframework `b11200`) with `Qwen3-4B-Instruct-2507-Q4_K_M.gguf`; a GBNF grammar
replaces Ollama's `format` schema. A second mode calls this Rust server's
`/api/chat` over HTTPS. The app bundles `tutor.txt` and `questions.json` by
reference and ports the `chat.rs` reply rules to Swift. The UI uses the web
palette and layout with native iOS controls. No backend, frontend, or
deployment changes were made. See [../ios/README.md](../ios/README.md).

Verified on the user's Mac (Xcode 27, over SSH, in a scratch copy):
`swift test` passed 9 ScienceCore tests; the app compiled for generic iOS
without signing; a macOS harness running the unmodified `LocalEngine.swift`
against Ollama's local `qwen3:8b` blob produced valid, schema-shaped answers
(English and Spanish/emoji) in about 6–7 s each. **Not yet verified:** running on
the iPad, the 4B model's memory use and speed there, model download/import,
remote mode, and visual appearance (the Mac's Xcode simulator/device
components reported as out of date). llama.cpp aborts on process *exit* unless
the model is unloaded first; iOS apps do not exit that way, but keep it in mind.

### Xcode project and first device install (2026-09-26)

XcodeGen was retired at the user's request (sole developer). The generated
`ios/Curio.xcodeproj` and `ios/Curio/Info.plist` are now
committed and edited in Xcode; `ios/project.yml` was deleted. Signing uses
`ios/App.xcconfig`, which optionally includes the ignored
`ios/Local.xcconfig` holding the personal `DEVELOPMENT_TEAM` and
`SCIENCE_SERVER_HOST`, so neither the team ID nor the hostname is in Git. Choosing a Team in Xcode's UI would write it into
`project.pbxproj` instead; avoid committing that.

Verified: a signed Debug build (free Personal Team, automatic provisioning)
succeeded and was installed on the user's iPad Air 11-inch (M2, 8 GB) with
`xcrun devicectl`; the 4B GGUF was copied into the app's Documents over the
cable. The first launch showed a broken layout: `layoutPriority` gave the
answer panel almost all the width, and iPadOS 26 squeezed toolbar items into
glass bubbles. Fixed with a measured 0.9 : 1.2 split (`GeometryReader`), a
plain header row, and in-panel scrolling; the landscape dark-mode layout was
checked with `xcrun devicectl device capture screenshot`. **Still
unverified:** portrait/light layouts, model load time, memory, answer speed,
follow-ups, Stop, Read aloud, and remote mode. The free-profile install expires after 7 days.

### Automatic mode and voices (2026-09-26)

User-verified on the iPad: portrait and light layouts, and local answers
averaging about 10 s. The app now defaults to **Automatic**: AI PC first via
the build-time `SCIENCE_SERVER_HOST` (Info.plist `ScienceServerHost`), falling
back to the on-device model when offline (`NWPathMonitor`), when a 4 s
`/healthz` preflight fails, or on 429/502/503. The stored setting key changed
from `engine` to `engineMode` so existing installs start in Automatic. Read
aloud picks the best installed Premium/Enhanced voice for the answer's language
(NaturalLanguage detection) with an optional Settings choice; Siri voices are
not available to apps. Built, installed, and launched on the iPad; the header
showed "Automatic · My AI PC" and the PC's `/healthz` returned 200 from the Mac.
Settings was then simplified for 10–13 year olds: Tutor and Appearance on
the main page; model, AI PC check, and voice on an "Advanced (for grown-ups)"
page with a warning. The typed AI PC address override was removed; the
address comes only from `SCIENCE_SERVER_HOST` at build time (kept out of Git
per the rules above, rather than hard-coded in Swift), and starter taps no
longer open the keyboard. The remote mode is labelled "mir-ai-pc".
The user then reported the simplified Settings and Automatic mode working on
the iPad. Apple's Premium voices were not good enough for the user; a custom
text-to-speech approach is under discussion (not started). **Still
unverified:** PC-off fallback and follow-ups/Stop were not reported separately.

### Rocket-and-atom icon (2026-09-26)

The user designed a new icon in Xcode (flat 1024 px PNG, `RocketAtomAppIcon.png`;
design history in `ios/DesignConcepts/`). The web favicon, touch icon, manifest
icons, and header logo were regenerated from it with `sips` (`?v=3` cache
query); see [../assets/README.md](../assets/README.md). Pushed to `main` and
fast-forwarded on mir-omarchy-pc; no restart was needed because the server
reads `public/` from disk. All public icon files, the manifest, and `/` matched
the repository byte-for-byte afterwards.

### Natural voice with Kokoro (2026-09-26)

Apple's Premium voices sounded robotic with abrupt pauses to the user. On the
Mac (M5 Max), sherpa-onnx 1.13.8 rendered Kokoro v1.0 samples; the user chose
`am_michael` (speaker 16). The full model ran about 5× faster than real time
and the int8 one about 2×, with similar sound, so the full model was chosen.
(Kokoro v1.1 in sherpa-onnx is mostly Chinese voices; v1.0 has the English
set.) Implemented: `ios/KokoroFramework` (prebuilt sherpa-onnx and ONNX Runtime
pinned by checksum, plus a small C-API wrapper), in-app download of the English
files from a pinned Hugging Face revision with SHA-256 checks, and sentence-by-
sentence gapless playback with Apple-voice fallback, all behind Settings →
Advanced → Read aloud. It builds cleanly and was installed on the iPad. The user
reported the in-app download and Read aloud with the natural voice working
on the iPad. **Not measured:** first-sentence delay, generation speed on the
M2, memory alongside Qwen, and Stop were not reported separately.

### Native iPad redesign (2026-09-26)

A HIG review found the iPad app copied the web page (custom header, bordered
cards, web palette, no Liquid Glass). Phases 1–2 are implemented: minimum iOS
26; `NavigationSplitView` with an Ideas sidebar and an answer detail column;
system toolbar (Read aloud, Settings) and a glass compose bar at the bottom;
system colours with the purple accent only; follow-ups as grouped rows; no
technical text on the main screen; readable width. `Theme.swift` and the web
colour sets were removed; Settings uses a menu picker, a Done checkmark, and an
About section. [DESIGN.md](DESIGN.md) records the design and how the web
should adopt it later (web unchanged for now). Verified: clean build and an
iPad screenshot of the empty state; the user then confirmed it worked.

The user then chose the **curiosity column** (mock-up in `docs/design/`),
which replaces that sidebar layout: a single column, a centred question box and
starters for fresh sessions, a trail of folded steps with the latest open,
"Dive deeper" under the latest answer, "Try something new" chips and "Ask your
own" above the question box (each starts a new trail, with Undo), per-answer
Read aloud, and Reduce Motion support. `ChatModel` now holds trail steps.
The first build hung on the iPad (watchdog `0x8BADF00D`, main thread in
SwiftUI layout): the dock's measured height fed back into the trail's bottom
margin through a shared `ZStack`. Fixed by putting the dock in
`safeAreaInset(edge: .bottom)` and giving the fresh session its own centred
layout, with `matchedGeometryEffect` moving the question box between them.
Verified on the iPad via `-autoAsk` screenshots: fresh → loading → folded
first step with ↳ → latest answer with Dive deeper and the chip row.
**Still to check by hand:** taps, rotation, Undo, Read aloud per answer, dark
mode, iPhone.

Later the same day: starters were renamed **Sparks** / **New spark**, the
dock became a `safeAreaBar` with a soft scroll edge (text had clashed with
it), and the speaker animates while reading. A **Nord** palette was tried
(`54d7a6f`) and reverted at the user's request; the app uses system colours
with the purple accent. The theme now sets `overrideUserInterfaceStyle` on
the windows, because `.preferredColorScheme(nil)` does not reliably return to
System. The app icon shows at the top left of the trail toolbar and in a
Settings header card; "❤️ Made with love by Ayaan and Naz" is on the landing
screen and in Settings. Still unchecked: theme switching and Settings by hand,
Dynamic Type, VoiceOver, Reduce Transparency/Increase Contrast, iPhone.

Trail scrolling (verified on the iPad with scroll-geometry logs): SwiftUI
silently drops programmatic scrolls requested while a layout animation (the
fold) is running, and the dock's safe-area inset adds no scroll room. The
trail therefore folds (0.3 s), then scrolls to the new step's measured top
with `ScrollPosition.scrollTo(y:)`, and the latest step reserves the scroll
view's full height. `ScrollViewReader`/`scrollTo(id:)` landed short here.

Debugging notes: launch arguments such as `-theme dark` override saved
settings for one launch. Debug builds accept `-autoAsk` (`xcrun devicectl device
process launch --device <id> local.curio.app -- -autoAsk`), which
asks the first spark and then a follow-up. Hang/crash reports are listed with
`xcrun devicectl device info files --domain-type systemCrashLogs` and copied
with `device copy from`. The iOS Simulator cannot build the app because the
pinned llama.cpp framework has no simulator slice.

### Renamed to Curio (2026-09-26)

The app is now **Curio** everywhere: web title and manifest, iOS display name,
Xcode project/target/scheme (`ios/Curio.xcodeproj`, `ios/Curio/`), iOS bundle
ID `local.curio.app` (a new app on the iPad: the old one must be deleted and
the Qwen model re-copied; the Michael voice re-downloaded), the Rust crate and
binary `curio-server`, the npm package, the unit templates
`deploy/curio-web.service` and `deploy/curio-caddy.service`, docs, diagrams,
and the tutor prompt ("You are speaking as the Curio app"). Browser storage
keys moved to `curio.*`; the theme falls back to the old key once. The GitHub
repository and checkout folder are still named `science-chatbot`.

Verified on the iPad: Curio (`local.curio.app`) built with a new profile
after the user signed in to Xcode and approved keychain access, the old
Science Chatbot app was removed, the Qwen GGUF was copied into Curio's
Documents over the cable, and the user re-downloaded the Michael voice.

**Live state (verified 2026-09-26 20:49 IST):** mir-omarchy-pc runs
`curio-web.service` (enabled) with `backend/target/release/curio-server` on
127.0.0.1:11436; `science-chatbot-web.service` is stopped and disabled but its
unit file and old binary remain for rollback (see [INSTALL.md](INSTALL.md)).
Funnel is unchanged. Publicly: `/healthz` 200, the Curio page and its
`app.js`, `theme.js`, and `styles.css` matched the repository, the retired
banner returned 404, and a real question was answered in 3.1 s with three
follow-ups. The user created the unit and switched services with sudo.

### Answer timing and latency (2026-09-26)

Answers now show "Answered in N seconds" (device-measured; "· on this iPad"
for offline answers) on the iPad and web, and the iPad remembers a
successful AI PC check or answer for 60 s instead of checking `/healthz`
before every question. Measured the same evening: Qwen on the RTX 5080 answers
in 0.8–1.0 s; over the tailnet the whole request takes about 0.8 s, but
through the public Funnel relay 2.5–3.7 s (connect 0.25 s, TLS 1.3–2.4 s). The
iPad showed 5–6.6 s, so it was using the public Funnel path. Installing
Tailscale on the iPad would cut this to about 1 s, but the user decided not
to pursue it: the iPad keeps using the public Funnel path.

### 2026-09 redesign: Home, Trail, Trail complete (2026-09-26, iOS)

Source: [design/redesign-2026-09/curio-redesign-handoff.md](design/redesign-2026-09/curio-redesign-handoff.md)
and its three `.dc.html` artboards. The user asked for the critique to apply
to iPad as well as iPhone. Tokens are reconciled in [DESIGN.md](DESIGN.md)
(redesign wins). Web (`src/client/`) is unchanged.

User decisions on the open questions: trails are **5 steps**; Sparks are
**shuffle-only** (no daily set); **one stamp per finished trail, unlimited**
(counter is a total, row shows the latest four and a dashed "next");
**dark tokens derived** by the agent (marked "to review" in DESIGN.md).

Implemented (`774807f` Home, `29c62cf` Trail + Complete):
- `CurioTheme.swift`: tokens, category styles for all 10 bank topics, the
  shared `BottomBar`. Fredoka and Nunito bundled (`ios/Curio/Fonts/`, OFL).
- `HomeView.swift`: greeting by first name (new Settings field "You", stored
  in `@AppStorage("childName")` on the device), resume card with 5 dots,
  Sparks 2×2 (4 across on iPad) with Shuffle, heart credit line.
- `TrailView.swift`: header, numbered step rail, category illustration,
  17/26 answer, two Dive deeper chips; New-spark carousel, Ask your own, and
  "Answered in N seconds" removed. On step 5 the bar is replaced by Finish.
- `CompleteView.swift`: stamp, recap (first sentence of answers 1, middle,
  last), stamps row, Start a new spark, Show a grown-up (shares the recap
  card as an image). `StampStore` keeps only topic + date + a random trail
  ID in UserDefaults. A trail stays resumable until Finish is tapped.
- Debug launch arguments: `-autoAsk` (first spark + one follow-up), then
  `-autoHome` (back to Home to show the resume card) or `-autoComplete`
  (follows Dive deeper to step 5 and opens Trail complete).

Verified: unsigned and signed builds succeed with no warnings in the new
files; `swift test` 9/9; derived colours ≥ 5.1:1 (light) and ≥ 7.1:1 (dark).
The signed build was installed on the iPad. **Not verified visually:** the
iPad was in use by someone else that night, so the agent did not launch
the app or take screenshots after the first attempt. Check by hand: Home,
resume card, Shuffle, trail rail/expand, Finish → Complete, share sheet,
dark mode, Dynamic Type, iPhone layout, and that Fredoka/Nunito weights
render (variable fonts; SwiftUI `.weight()` on `Font.custom`).

Known contrast gaps in the design's own values (kept, redesign wins): Sound
label `#B8452E` on `#FFE3D6` is 4.38:1 and placeholder `#7A7690` on white is
4.36:1, just under WCAG AA 4.5:1 for small text.

**Needs new feature development** (placeholders shipped instead):
- Microphone / speech-to-text: not built; the bar has no mic. Needs Speech
  framework, microphone and speech-recognition permissions, and a privacy
  decision (on-device-only recognition for children).
- Per-step illustrations: a generic per-category scene stands in. Real ones
  need generation or a drawn library.
- Short step labels ("Step 3 · The nucleus") and trail names ("Comets"):
  the question and the starter topic stand in. Needs the tutor to return a
  label, which changes the response schema/API contract.
- Recap facts: first sentences stand in; generated facts need an extra
  model call or schema change.
- Resume across launches: trails live in memory only, so the resume card
  disappears when the app is closed. Needs trail persistence (privacy
  decision, ties into history).
- Parent digest (open in the design): not started.

### Redesign v2 audit (2026-09-27, step 1 of 5, no code changed)

The handoff grew to eight artboards (adds MainDark, TrailDark, TabletHome,
TabletTrail, WebTrail), official dark tokens, and breakpoints (`<700` phone ·
`700–1100` phone layout with wider gutters and 3-column sparks · `≥1100` two
columns · `≥1400` web three columns with nav). AGENTS.md now points all
screens (phone, iPad, web, light, dark) at it. Plan agreed with the user:
1 audit · 2 tokens · 3 trail overlap fix · 4 phone Home/Trail/Complete in
light and dark · 5 responsive ≥1100 / ≥1400.

**Already matches**
- iOS light tokens, type scale, radii (`CurioTheme.swift`); fonts bundled.
- iOS phone Home, Trail, Complete structure (`774807f`, `29c62cf`), including
  the overlap fix (carousel and Ask your own removed) on iOS.
- Web theming mechanism: `theme.ts` + `data-theme` + `prefers-color-scheme`
  fallback is the pattern the handoff asks for.

**Conflicts (handoff wins)**
- iOS dark values were derived by the agent on 2026-09-26 and differ from
  the handoff's (ground `#16142A`→`#17152A`, border, muted, label, accent
  text `#A9A2FF`, new separate accent-H1 `#B1AAFF`, accent fill
  `#5E55D8`→`#6A61E8`, connector, locked, success, heart, all category
  pairs). DESIGN.md's token table records the derived set and must be
  replaced.
- iOS colours live in Swift (`Color(light:dark:)`), not the asset catalog the
  handoff asks for; `Accent.colorset` still holds the old `#4E45B6`/`#C1B2FF`
  (tints system controls and Settings).
- iOS spark icon discs are white in dark; handoff: Ground. Stamp ring uses
  category colour; handoff: accent. Light category: handoff `#FCEBC4`/`#8A5A00`
  vs derived `#FFF0C7`/`#855A00`.
- Web is still entirely the old design: old tokens (`#4e45b6`, grey
  surfaces), glass and shadows (handoff: no shadows), system font, emoji
  topic labels, hero, "Answered in N seconds", and the New-spark dock that
  causes the overlap bug. Web breakpoint is 600 px, not 700/1100/1400.

**Missing**
- Web: all three redesigned screens, Complete, stamps, name greeting.
- iOS/web: width breakpoints. iPad landscape (1180) should be two-column;
  today iOS switches on size class only (4-across sparks, phone layout).
- iPad/web trail rail with upcoming dashed steps, "So far you know" card,
  3-across Dive deeper, 360×260 / 760×280 illustration crops.
- Five bank topics have no official colours (Earth, Electricity, Forces &
  motion, Matter, Plants); "Body" is in the handoff but not in the bank.
- Dark artboard greets "tonight"; phone says "today" (time-of-day greeting
  not specified).

**Infeasible without new features or contract changes**
- Six sparks on tablet: `/api/suggestions`, the Rust bank (`COUNT = 4`), the
  Swift port, and web validation all fix four.
- Web nav My trails / Stamps / Grown-ups, profile chip, "Trails you
  finished", "N stamps" pill: need saved trails and stamps. There is no
  login or database; on-device storage would be per browser/device.
- Web fonts: the CSP (`default-src 'self'`, `style-src 'self'`) blocks Google
  Fonts, and the Rust asset allowlist serves no font files. Self-hosting
  needs new routes in `http.rs`, a release build, and a service restart to
  go live.
- Generated per-step illustrations, short step labels ("The nucleus"),
  trail names ("Comets"), and generated recap facts need model or response
  schema changes.
- Mic: iOS can use on-device recognition; on the web, Chrome's speech
  recognition sends audio to Google, a privacy decision for children.
- "Show a grown-up" on web: Web Share with files is not universal; needs a
  download fallback. What it shares is an open decision.

### Redesign v2 step 2: tokens (2026-09-27)

User decisions: yesterday's feature decisions are final (5-step trails,
one stamp per finished trail with a total counter, shuffle-only sparks);
iPad/web artboards are layout references. "Show a grown-up" shares the
recap image plus the trail's questions. Saved trails/stamps stay on the
device (UserDefaults / localStorage). Web fonts are self-hosted via Rust.

Done: [DESIGN.md](DESIGN.md) → Tokens is now the single source of truth
(semantic names shared by CSS and iOS; handoff dark values replace the
agent-derived ones; five bank topics keep derived colours, Forces & motion
moved from pink to slate to stay distinct from the handoff's Body).
iOS: 45 colour sets in `Assets.xcassets/Colors` (Any/Dark), `Accent.colorset`
→ `#4F46C9`/`#A9A2FF`, literal colours in screens replaced (icon discs use
ground in dark, stamp ring uses accent fill, current question uses
accent-heading). Web: token layer at the top of `public/styles.css`
(`prefers-color-scheme` + `data-theme`), old names remapped, shadows
removed, `theme-color` and manifest colours set to ground (manifest `?v=5`).
Fonts: four latin/latin-ext woff2 files in `public/fonts/` served by new
allowlist routes in `backend/src/http.rs` (`font/woff2`, covered by the
asset test); no CSP change was needed.

Verified: `npm test` 21 Rust + 32 HTTP/frontend passed, typecheck,
rustfmt + Clippy, iOS unsigned build. Web at 390 px in light and dark via
headless Chrome against the dev server (127.0.0.1:11437, mock tutor). The
live service still runs the old binary: the font routes and new CSS need a
release build and restart to go live (not done).

### Redesign v2 step 3: trail overlap fix (2026-09-27)

Web: removed the dock's New-spark carousel and "Ask your own" (markup,
`app.ts`, CSS); the dock now holds only the question box, and the trail's
bottom padding dropped from 220 to 130 px. Client tests were updated (spark
cards and "New sparks" replace the chips and dice; the Ask-your-own test
became "a new spark replaces the trail, and Undo brings it back"). iOS
already had this fix (`29c62cf`). Verified: `npm test` 21 + 32 passed,
typecheck; 390 px light screenshot shows Dive deeper clear of the dock.
Interim gap until step 4: the web page has no way back to Sparks during a
trail (Back/Home arrives with the redesigned Trail header).

### Redesign v2 step 4: phone screens (2026-09-27)

Web rebuilt to the redesign (plain TS): Home (greeting with name from a new
Settings dialog, resume card, tinted Sparks, Shuffle), Trail (header, rail,
illustration, Dive deeper, Finish on step 5), Trail complete (stamp, recap,
stamps, Start a new spark, Show a grown-up = recap PNG + questions via Web
Share, else download + clipboard). Stamps and finished trails in
localStorage. Client tests rewritten for the new flow (35 HTTP/frontend
tests incl. resume, Finish → stamp, name greeting). iOS: "today"/"tonight"
greeting, Show a grown-up adds the questions as the share message,
finished trails recorded with stamps (`StampStore.trails`), Complete opens
at the top, and Debug `-autoAsk` runs no longer save stamps.

Verified: `npm test` 21 Rust + 35 HTTP/frontend, typecheck, iOS build.
Web at 390 px, light and dark, Home / resume / Trail / Complete via
headless Chrome (mock tutor). iPad (landscape) light: Home, Trail,
Complete checked by screenshot; that run found the Complete scroll offset
(fixed, not re-checked on device). **iPad dark not verified**: someone was
using the iPad during the run, so launches stopped and those captures were
deleted. The latest iOS build is not installed yet.

Data note: two earlier `-autoComplete` test runs each saved a stamp (and
trail) into the iPad's real Curio storage; it held six stamps at 08:49, so
four came from real use. The test ones were not removed; ask before
deleting anything.

### Redesign v2 step 5: responsive layouts (2026-09-27)

Web: CSS breakpoints at 700 / 1100 / 1400 px with new markup for the nav,
Home columns, stamps pill, "Trails you finished", and a side rail rendered
from the trail (done/current/upcoming steps, stamp, "So far you know").
iOS: `curioWide` environment value (window ≥ 1100 pt) switches Home and
Trail to the tablet layouts; the bottom bar moves under the main column.
Also: phone illustration uses the 350:124 aspect ratio; the illustration
halo is lighter in dark (`halo-opacity` token); Trail complete on iOS is
now one scroll view (it clipped/overlapped in iPad landscape).
Deviations are listed in DESIGN.md → Screens.

Verified: `npm test` 21 Rust + 35 HTTP/frontend, typecheck, rustfmt +
Clippy, iOS unsigned and signed builds. Web by headless Chrome at 820,
1180 and 1440 px (light and dark). iPad landscape by device screenshots:
wide Home (dark) and wide Trail (light and dark) match the artboards;
Complete showed the clipping/overlap above, which was then fixed but
**not re-checked on the device**. One capture showed another app in use on
the iPad and was deleted; no further launches were made. The final build is
installed on the iPad.

iPad data: Curio holds 7 stamps; 2 were saved by agent test runs before the
Debug guard, and both "Trails you finished" entries are from those runs.
Nothing was deleted; ask the user before removing test data.

Not deployed: the live service still runs the old binary. Going live needs
`npm run build` and a service restart (new font routes).

### Follow-up batch (2026-09-27, after the user deployed the redesign)

User priorities: 1 verify deploy + iPad cleanup, 3 keep unfinished trails,
4 microphone, 5 richer tutor replies, six sparks on the tablet, small bugs.
Declined for now: contrast fixes, per-step illustrations. Later: Stamps and
My trails screens. Decision: unfinished trails are kept **7 days**.

Done and verified:
- Deploy (user redeployed at `8bdf38c` and restarted): every public asset
  and font route matched the repository byte-for-byte; a real spark was
  answered end to end on the public site at 390 px.
- iPad: the Debug argument `-removeFinishedTrails` (`22531b8`) removed the
  two agent test trails and their stamps; 5 real stamps remain. Trail
  complete in landscape (light and dark) now fits; Debug runs no longer
  save stamps or trails.
- Tutor extras (`bf810ef`): optional `fact`, `label`, `trailName` in the
  prompt, schema, Rust (`optional_text`), Swift port and grammar; dropped
  when unusable. Local qwen3:8b filled them well in English and Spanish.
  Six-spark batches (`count=6`) and a Body topic (66 questions, 11 topics).
- Clients (`2e1a368`): unfinished trail saved 7 days (web localStorage
  `curio.trail.v1`, iOS UserDefaults `unfinishedTrail`, re-validated on
  load); extras used in headers, resume card, rail, recap; 3×2 sparks when
  wide; fixed the tapped spark staying in the web grid and the pointless
  Undo after a finished trail.
- Microphone (`d597188`): iOS only, on-device `SFSpeechRecognizer`, fills
  the box, stops after a 2.5 s pause / 30 s / tap / answer / screen change;
  usage strings in Info.plist. Hidden on web.
- Checks: 24 Rust + 40 HTTP/frontend tests, typecheck, rustfmt + Clippy,
  10 ScienceCore tests, iOS unsigned and signed builds. Web screenshots at
  390 and 1180 px against local qwen3:8b. iPad screenshots: six sparks with
  Body, mic button on Home and Trail.

**Not yet verified:** speaking into the mic (needs a person; the first tap
shows the iOS permission prompts), a real saved trail surviving an app
relaunch on the iPad, and the extras on the iPad (its AI PC mode uses the
deployed server, which still has the old prompt until redeployed).

To go live: pull on mir-omarchy-pc, `npm run build`, restart
`curio-web.service` (new prompt, schema, Body topic, `count` parameter).

### iPhone feedback fixes (2026-09-27)

The user tested on the iPhone (Curio installed there today; free profile,
7 days) and reported: the resumable trail vanished once another trail was
started; only one unfinished trail was offered; no back swipe; no stamps
count on the phone. Agreed and done:
- Up to three unfinished trails (current + two earlier), 7 days each, on
  web (`curio.open-trails.v1`, migrates `curio.trail.v1`) and iOS
  (`unfinishedTrails`, migrates `unfinishedTrail`). Newest = resume card,
  earlier = rows; a fourth drops the oldest. The Undo banner was removed.
- iOS uses `NavigationStack(path:)`: Home root, Trail / Trail complete
  pushed directly on Home; a `UINavigationController` extension keeps the
  edge swipe working with the system bar hidden.
- Stamps pill on phone layouts too (web and iOS); still a count only.

Verified: 24 Rust + 40 HTTP/frontend tests (new: three open trails,
migration), typecheck, Clippy, 10 ScienceCore tests, iOS builds; web phone
Home screenshots (light/dark) with three trails and the pill. **Needs the
user on the iPhone:** the back swipe, reopening an earlier trail, and the
trails surviving a relaunch.

### Answer length regression and fix (2026-09-27)

The user noticed shorter answers. Measured on local qwen3:8b (8 questions ×
3 runs, the server's exact request): old prompt (`926f71b`) mean 74 words;
the prompt with fact/label/trailName (`bf810ef`) mean 40. Reordering the
schema alone gave 51; a sentence saying the extras do not change the answer
(which must still follow the length and brief-reply rules) gave 69–85 and
kept the creator line and the off-topic redirect exact. That wording is
now in `tutor.txt` (schema and grammar unchanged). Pre-existing quirk, not
changed: "Who created Qwen?" gets the app-creator line instead of the
Alibaba Cloud answer, with the old prompt too.

### Tutor style brief (2026-09-27)

User brief: do not fixate on length (up to ~100 words is fine); teach in a
simple, exciting way. The prompt's style paragraph now asks for three parts
(a surprising fact or vivid comparison, how it works in everyday words, and
an everyday example when one fits), accuracy over fun, comparisons that
match the science ("a baby growing up is not evolution"), science words
explained, about 60–100 words. Safety, topic, and creator rules unchanged.

How it was chosen (local qwen3:8b, the server's exact request, 8 questions
× 2): variants were read side by side, not only measured. Lessons for this
8B model: any "one short sentence" wording near the answer collapses the
answer to one sentence; naming a word ("Imagine") in a "don't" rule makes
every answer start with it; forcing an everyday example into every answer
produces odd ones. Final: mean 67 words (40–99), reading grade ~7, varied
openings; creator line, political redirect, and unsafe request unchanged.
Known limit: occasional loose analogies remain (model accuracy ceiling).

### Pixel field (2026-09-27)

User asked for an animation in the empty space at the bottom, like the
omarchy.org pixel hero (screen recording), with kid-friendly science
scenes per device and no main-thread cost; also on Trail (quieter).
Done: web `src/client/field-worker.ts` (WebGL shader in a worker on an
OffscreenCanvas; `/field-worker.js` asset route; the page measures the
empty gap and posts it as the scene's focus), iOS `PixelField.metal` +
`PixelField.swift` (colorEffect; the view fills the leftover scroll space
on Home and Trail). Field colour tokens in DESIGN.md. Xcode needed its
Metal Toolchain component (downloaded with the user's approval, 839 MB).

Verified: web 390 / 1180 / 1440 screenshots (starfield + comet, atom,
solar system) in light and dark; with the field running, headless Chrome
measured 0 main-thread long tasks and 61 fps; 40 HTTP/frontend tests.
iOS builds and is installed on the iPhone and iPad. **Not verified on iOS
by eye:** the Mac run through Xcode stalled (AppleScript to Xcode hung,
probably a dialog in Xcode), so the iOS look needs the user's check.

Placement fix (same day, user feedback from iPhone/iPad): the first version
filled only the space left under the content, which on Home was often a
single row of pixels. Now the field is a fixed band over the bottom half of
the screen behind the content (web: 50vh canvas; iOS:
`pixelFieldBackground`), with the scene centred in the band above the
question bar regardless of content; taps and hover reach it through the
content. Trail intensity 45 %.

### Stamps screen, user service, trail tests (2026-09-27)

User decisions: skip a "My trails" screen for now (Home already shows the
three unfinished trails; finished trails keep no answers until history is
built); build a Stamps screen; run Curio as a systemd user service so
deploys need no sudo; move the iOS trail logic under `swift test`; then
work on tuning Qwen's answers.

Done: Stamps screen on web (`e85f849`, view `stamps`, nav Home / Stamps,
the stamps pill is a button) and iOS (`61fc4a1`, pushed screen): 12 kinds
(11 topics + Curious Mind with a sparkles icon), counts or dashed "not
yet", latest ten with dates. `deploy/curio-web.user.service` and
INSTALL.md → "Run as a user service" (`c5c57a4`): one-time switch with
linger, copying PUBLIC_ORIGIN from the live unit; **not yet run on
omarchy** (the user runs it). ScienceCore `OpenTrailShelf`/`SavedTrail`
with 5 new tests (15 total). Web tests 41 (new Stamps test).
Stamps screenshots checked at 390 px (light) and 1440 px (dark).

### Frontend delight batch (2026-09-27)

Worked on `main` while a separate `prompt-tuning` worktree changes the
prompt (not touched here). Done: stamp celebration (`bafa5f9`),
collection-aware sparks with `prefer=` on `/api/suggestions` and the Swift
port (`1691345`), loading pixel grid + Did-you-know facts (`b22f414`,
`/did-you-know.json` route), first-launch welcome on web (`2b6c20e`) and
iOS. Verified: 25 Rust, 44 HTTP/frontend, 15 ScienceCore tests; web
screenshots of the burst, badges, loading and welcome in light and dark.
iOS builds and is installed; **its new screens were not checked by eye**
(the Mac run via Xcode is unreliable), so the iOS look needs the user.
Deployed by the agent over SSH at the user's request: mir-omarchy-pc now
runs `curio-web` as a **user service** (the user had switched; the system
unit is inactive), pulled to `29318d4`, `npm run build`, `systemctl
--user restart curio-web` without sudo. Verified: local `/healthz` ok,
public page / styles / app.js / field-worker.js / did-you-know.json match
the repository, and a real question returned an answer with trail name,
label and fact.

### Tutor prompt and model: Gemma 4 12B (2026-09-27, branch `prompt-tuning`)

Worked in a separate worktree (`../science-chatbot-prompt`, branch
`prompt-tuning`) so the frontend/service agent on `main` was not disturbed.
User brief: answers too short and uneven ("How do alveoli work?" got one
21-word sentence); tone, curiosity and accurate content matter far more than
length; the model reply must be ready within 2–3 s (the network adds 2–3 s);
thinking mode rejected as too slow. No answer length was ever enforced in
code: only `minLength: 1` in the schema and the prompt's word guide.

Evals: a scratch script sends the server's exact Ollama request (system
prompt, question, schema `format`, `think: false`) for 16 questions × 2–3
runs, including the creator line, political redirect, an unsafe request and
a model question; answers were read side by side, not only measured. Model
runs used the Omarchy PC's Ollama (0.33.3, RTX 5080) through an SSH tunnel.
`gemma4:12b` and `qwen3.5:9b` were pulled there and are to be kept.

| Model (5080, same prompt) | Reply time mean / max | Notes |
|---|---|---|
| `qwen3:8b` | 0.9 / 1.1 s | short; myths (black hole "vacuum cleaner") |
| `qwen3.5:9b` | 1.5 / 2.5 s | lively but unsafe (sparkler with a match), backwards facts |
| `gemma4:12b` (tuned prompt) | 2.3 / 3.0 s | most accurate, teaches how and why; chosen |

Prompt changes: the style paragraph asks the tutor to spark and satisfy
curiosity, explain how and why even for narrow questions, end with one more
true, amazing detail, give the scientific consensus and say when scientists
are unsure; comparisons must be right. For Gemma: open with a plain
statement rather than a question (it began most answers with "Did you
know"), keep each answer under 110 words (softer targets gave ~145 words and
~2.8 s), reply to creator questions with exactly the creator sentence, and
the underlying model is now described as Gemma by Google. Result with
`gemma4:12b`, 16 × 3: science answers 100–162 words (mean 120), 2.5 s mean /
3.0 s max for science answers; creator, redirect and model replies exact.

Lessons: rules about "your first/last sentence" made 8B models stop after one
sentence; Gemma follows a word ceiling better than a target. Gemma garbled
the end of 3 of 190 answers (cut mid-sentence, stray "1.", a trailing `",`);
a server check could catch these later. The 5080 generates ~93 tokens/s with
Gemma; the fact, label, trail name and follow-ups cost ~0.75 s of each reply.

Changed on the branch: `tutor.txt`, default model `gemma4:12b` in
`main.rs`, `http.rs`, both `deploy/` units and the README. Not changed: the
iOS offline model (4B Qwen fallback; its prompt copy now names Gemma),
`src/client/app.ts` ("private Qwen tutor" tool text) and the classroom
diagrams, which still say Qwen. After merging
the latest `main` into the branch: `npm test` (25 Rust + 44 HTTP/frontend),
`npm run typecheck`, `npm run check:rust` and `git diff --check` passed. Proposed next: stream answers
(first words in well under a second) as a joint task with frontend work.

Deployed (2026-09-27): merged to `main` (`ab2c54d`), pushed by the user, then
on the PC `git pull`, `npm ci`, `npm run build` (non-interactive SSH needs
`PATH=$HOME/.cargo/bin:$PATH`), `OLLAMA_MODEL=gemma4:12b` in
`~/.config/systemd/user/curio-web.service` (previous unit saved beside it as
`curio-web.service.bak-qwen3`), `daemon-reload`, restart. Verified on
`127.0.0.1:11436`: `/healthz` 200; five live questions returned 200 with
labels and trail names; 5.6 s for the first (model load), then 2.2–2.7 s
(creator line 1.2 s); `ollama ps` shows `gemma4:12b` 100% GPU. Ollama unloads
an idle model after 5 minutes, so the first question after a pause includes
the load; `OLLAMA_KEEP_ALIVE=-1` on the Ollama service would avoid that (not
changed). Rollback: restore the `.bak-qwen3` unit, `daemon-reload`, restart
(the prompt is compiled in, so a full rollback also needs the older build).

### Web matches iPad; pixel placement (2026-09-27)

User asked for web to match iPad (no side nav, back controls on Trail and
Stamps, browser Back in sync) and for the pixel field to reach the bottom
edge behind the question bar, with the solar system on Home and the atom
on Trail placed in empty space. Mockups in
`docs/design/web-ipad-parity-2026-09/` carry the user's annotations
(solar system in the empty lower-left, not behind trails and sparks;
pixels everywhere else and under the bar; start below the credit line;
a border on the question box; pixels under the bar on Trail too).

Done: web `9ec389c` (side nav and profile chip removed; History API with
Home as the base entry; `<main>` is the scroller with a mask above the
bar, so the bar is see-through; `sendFieldFocus` measures the lowest
content and posts a fill line and an empty-space rect; shader scenes fit
that rect; 2 px `connector` outline). iOS: the same placement in
`PixelField.metal`/`PixelField.swift` (global-coordinate measurements,
`pixelFieldContent()` marks Home's columns and Trail's steps; the field
runs to the screen bottom behind the bar) and the same outline.

Verified: 45 HTTP/frontend tests (a new browser Back/Forward test), Rust
checks, typecheck; headless-Chrome screenshots at 1440, 1180, 900 and
390 px in light and dark (Home, Trail, Stamps, browser Back from Stamps).
iOS builds and is installed on the iPhone and iPad. **Not checked by eye
on iOS:** the Mac "Designed for iPad" run started through Xcode but its
self-snapshot never saved, and the simulator cannot build (llama.xcframework
has no simulator slice).

Deployed to mir-omarchy-pc (`c1a4c35`: pull, `npm run build`, `systemctl
--user restart curio-web`); health ok and the served page, app.js and
styles.css carry the new code. A real question was not asked after the
restart.

### iPad feedback: solar system, Trail halves, microphone (2026-09-27)

User on the iPad: no solar system on Home, only pixels; Trail wastes the
space under the picture (wanted picture left half, answer right half, one
font size down); the microphone switched off within seconds.
Causes and fixes: (1) placement looked for space below *all* content and
the long Home column (open trails + "Trails you finished") left none;
now each column gets its own fill line and the scene takes the larger
empty space (under Sparks here, centred there), clipped to it. On the web
the Sparks' grid cell also stretched to the column's height and the
position was measured before sparks loaded; it now measures the cards and
re-measures on resize. (2) Trail at ≥1100: a two-column grid, picture as
tall as the answer, answer 18/28 (was 20/32), web and iOS. (3) Voice: the
2.5 s pause timer started at the tap, so a slow start or slow first
partial ended listening; now 8 s for the first words, then 3 s pauses,
and if nothing was heard an alert says so with the system's reason.
Follow-up (same day): the user preferred horizontal splits on the iPad
Trail, so the picture is now a full-width 200 pt banner above the answer
(web ≥1100 and iPad), replacing the two halves.
Voice, second pass (same day): the user found it missed words or kept
only the last word. `VoiceInput` now uses iOS 26's `SpeechAnalyzer` with a
`DictationTranscriber` (`.progressiveShortDictation`): live text as the
child speaks, finished phrases kept and only the phrase in progress
replaced (SFSpeechRecognizer's partial results reset after pauses). Still
on-device; Apple's model downloads once via `AssetInventory` if missing.
Then on the iPad it caught only the first loud words: `.measurement` mode
had turned off automatic gain, and mixing the iPad's mic channels made it
quieter. Now the input uses voice processing (`setVoiceProcessingEnabled`,
`.playAndRecord`) and only the processed first channel (`b1f05f9`,
`143914a`). **Verified by the user by voice on iPhone and iPad.**
Verified: web screenshots at 1180/1440 with a long Home column; tests.
iOS installed on iPhone and iPad, not checked by eye here.

### Model check: "answers seem shorter" (2026-09-27, evening)

Live service: `OLLAMA_MODEL=gemma4:12b` (from the user's `cf88c76`; Ollama
had it loaded). Three live questions gave 115, 135 and 127 words in about
2.5 s, so the server's answers are not short. The iOS app points at the
same server; in Automatic mode it falls back to the on-device Qwen3 4B
(with the Gemma-tuned prompt) when the server is unavailable, e.g. during
today's restarts. Likely cause of the short answers, not confirmed: the
user will retry with the engine set to mir-ai-pc. Possible follow-ups:
show which engine answered, or retry the server before falling back.

### TestFlight (planned, 2026-09-28)

The user will enrol in the Apple Developer Program (individual, $99/yr) to
share the iOS app with friends and family through TestFlight; the current
signing team cannot use TestFlight. When they return with the team and a
bundle ID: replace the placeholder `local.curio.app`, set
`ITSAppUsesNonExemptEncryption = NO` (HTTPS only), create the app in App
Store Connect (the name "Curio" may be taken), archive and upload, then
invite external testers (the first build needs Beta App Review). Testers'
copies use the home server through the Funnel host (two answers at a time;
Automatic mode can fall back to the on-device model).

Web width cap (`b5f71b8`, 2026-10-01): pushed with `d0aef22` and `2b1cc6d`
and deployed to mir-omarchy-pc (pull, `npm run build`, user-service
restart); health ok and the served styles.css carries `--page: 1240px`.

### Server hardening, phases 1 and 2 (2026-10-01)

Why: the server is public through Funnel and kept no request log, so there
was no way to see who called it; the only brake on `/api/chat` was the two
model slots. The user approved a five-phase plan; phases 1 and 2 are coded.

Committed, **not deployed** (the release build and `curio-web` restart were
not run; the live binary is still the old one):

- Request log: one line per request on standard output (journal), with
  address, method, path, status, milliseconds, `X-Curio-Client`, user agent.
  No query string and no question text.
- Question limits in `backend/src/limits.rs`: 10 per minute and 200 per day
  per caller, 1000 per day for everyone; 429 with `Retry-After`. Settings and
  how a caller is identified are in the README configuration table. The plan
  said 100 per day; 200 was chosen because the family shares one home address.
- A question body that has not arrived within 10 s gets 408.
- `Strict-Transport-Security` and `Permissions-Policy` response headers.
- The web page and iOS source send `X-Curio-Client` (`web` / `ios`).
  Enforcement (`REQUIRE_CLIENT_HEADER=1`) is off: installed iOS builds do not
  send the header yet. Turn it on in the live unit after the app is updated.

Verified: `npm test` 30 Rust + 50 HTTP/frontend, typecheck, rustfmt + Clippy.
Not verified: that Funnel passes the real caller address in
`X-Forwarded-For` (check the first live log lines; if every line shows
127.0.0.1 the per-caller limits act as one shared limit). iOS not built.

Not done: no timeout on slow request *headers* (`axum::serve` has no such
setting; Tailscale terminates the public connections). Remaining phases, all
needing the user: 3 firewall review, SSH password login off, Sunshine and the
unused Caddy service; 4 systemd sandboxing of `curio-web`; 5 outside probes.
Open question: whether Curio stays public or gets a passcode.

### Server hardening, phase 3 (2026-10-01)

Findings (read-only; `ufw status` output supplied by the user):

- ufw is active with incoming default DROP (`/etc/default/ufw`). The only
  allow rules are 53317 tcp/udp (LocalSend file sharing) from anywhere and
  Docker DNS. There is no rule for SSH (22) or Sunshine (47984-48010), so
  both are already closed to the LAN and the internet; they are reachable
  only over Tailscale, whose own firewall rules accept `tailscale0` traffic.
  This is read from configuration, not yet probed from outside (phase 5).
- sshd uses the Arch defaults: password login is still allowed.

Done: `science-chatbot-caddy` (user service, port 11435) stopped and
disabled; nothing used it and Funnel goes straight to 11436. Undo with
`systemctl --user enable --now science-chatbot-caddy`.

Waiting for the user (needs sudo): turn SSH password login off; optionally
limit 53317 to the home network.

Deployed 2026-10-01 20:23 IST: `npm run build`, `curio-web` restarted. The
public URL returned 200 with the two new headers, and the journal shows
`request ...` lines. Requests made from this machine to the public name show
its own Tailscale address (they travel inside the tailnet, not through
Funnel), so `X-Forwarded-For` is read; a request from outside the tailnet
(for example a phone on mobile data) has still not been seen in the log.
The "not deployed" note in the phases 1 and 2 section above is superseded.

### Server hardening, phase 5 checks (2026-10-01)

Verified on the live service, entering through Funnel's internet address
(curl with public DNS, so not the tailnet shortcut):

- The log shows the caller's real public address (IPv4 and IPv6 seen); a
  forged `X-Forwarded-For` header is ignored.
- Scanner paths (`/.env`, `/.git/config`, source files, `/api/tags`,
  `/api/generate`, dot-dot paths) return 404; OPTIONS 405; wrong content
  type 415; foreign `Origin` 403; 9 KB body 413; blank question 400; plain
  HTTP redirects to HTTPS.
- Twelve real questions in a row: ten answered, then 429 with `Retry-After`.
- SSH: the user turned password login off (drop-in
  `10-no-passwords.conf`, sshd reloaded 20:19); the server now offers
  `publickey` only.

Not done: a port scan of the machine's public IPv6 address from outside the
home network (cannot be done from this machine). Whether the user applied
the optional ufw change limiting 53317 to the home network is unknown.
Phase 4 (systemd sandboxing of `curio-web`) has not been started.

### Server hardening, phase 4: sandbox (2026-10-02)

The live user unit and the template `deploy/curio-web.user.service` now
carry systemd sandbox settings: the server sees an empty home directory
except `public/`, `build/client/`, `backend/data/` and
`backend/target/release/` (all read-only), cannot write to disk, gain
privileges, or use unusual system calls. `systemd-analyze --user security
curio-web` went from 9.4 (unsafe) to 1.4 (ok). A new asset folder in
`http.rs` must also be added to `BindReadOnlyPaths`. The previous live unit
is saved beside it as `curio-web.service.bak-presandbox`.

Verified live through Funnel after the restart: page, script, styles, font,
facts, suggestions and one real question all returned 200; no errors in the
journal. Not possible in a user service: limiting the process to local
network addresses (`IPAddressAllow` needs root), so it is not set.

Also confirmed by reading `/etc/ufw/user.rules` and `user6.rules` (world
readable): port 53317 is now allowed only from 192.168.29.0/24 and
fe80::/10.

Decision: Curio stays public (no passcode). Still open: set
`REQUIRE_CLIENT_HEADER=1` in the live unit once updated iOS builds are on
the devices; outside IPv6 port scan; review the request log after a few days.

### Paid developer team and TestFlight preparation (2026-10-02)

The user joined the Apple Developer Program. The team ID did not change
(the Personal Team became the paid team), so `ios/Local.xcconfig` is as
before; development profiles now last one year instead of 7 days. The user
chose the bundle ID **`app.curio.tutor`** (replaces `local.curio.app`).

Done: bundle ID in the project and `ios/README.md`;
`ITSAppUsesNonExemptEncryption = NO`; a privacy manifest
(`ios/Curio/PrivacyInfo.xcprivacy`: UserDefaults, no tracking, no collected
data); a TestFlight section in `ios/README.md`.

Verified: 15 ScienceCore tests; signed Debug build from `81399cc` (so it
sends `X-Curio-Client: ios`) installed on the iPhone and the iPad, not
launched; the Qwen GGUF copied into the new app on the iPad (the iPhone's
old app had none). Release archive built (version 1.0, build 1) and exported
as an App Store Connect `.ipa`: Xcode registered the bundle ID and created
the cloud-managed distribution certificate and store profile.

**Not done:** the upload failed with "App record with bundle identifier
app.curio.tutor not found". The user must create the app in App Store
Connect; then rerun the upload (ios/README.md → TestFlight). After that:
internal testers at once, external testers after Beta App Review.

On the devices the old `local.curio.app` is still installed beside the new
app and holds the stamps, trails and (iPad) the old model copy; the new app
starts empty and needs the Michael voice downloaded again. Nothing was
deleted; the user removes the old app when ready. `REQUIRE_CLIENT_HEADER=1`
should wait until the old app is gone and testers have the new build.
The "TestFlight (planned)" section above is superseded.

## Agreed direction, not yet implemented

The user expects login, conversation history, and more functionality over time.
Keep the current TypeScript frontend for now. Introduce React + TypeScript +
Vite when building the account/history screens, with Rust continuing to own the
backend APIs. No Next.js server is planned. This roadmap is not authorization to
start those features without a concrete next request.

The user wants **trails** (one topic's chain of questions, see
[DESIGN.md](DESIGN.md)) to become the unit of history, and later to show a
child's most frequent and deepest trails and main interests. Not scheduled;
depends on history and on privacy decisions for children's data.

### Todo (not scheduled)

- Record the questions children actually ask and use them to grow the starter
  bank (`backend/data/questions.json`). Needs privacy decisions first: what is
  stored, consent, retention, and a review step before a child's question
  becomes a starter.
- Trails as a map of interests (above and in [DESIGN.md](DESIGN.md)).
- Frontend backlog (agreed 2026-09-27, after the celebration / sparks /
  loading / welcome batch):
  - Read-aloud highlighting (sentence or word as it is spoken).
  - Accessibility pass: VoiceOver / screen-reader order, iOS Dynamic Type,
    web keyboard-only use, the four low-contrast colours in DESIGN.md.
  - Installable web app: service worker with an offline "can't reach the
    tutor" page (manifest exists).
  - "My trails" / history with finished trails to reread (needs saved
    answers and privacy decisions; where the React migration would start).
  - Grown-ups weekly summary (same privacy questions).

Authentication approach, database choice, history retention, and detailed UI
requirements have not been decided. Clarify them when beginning the feature.
The current public-origin check is not authentication.

## Classroom presentation

[diagrams/README.md](diagrams/README.md) links to a classroom-friendly PNG and
editable SVG showing six steps from asking a question to reading the answer.
It includes speaking notes and likely teacher questions for a 10-year-old.
The diagram distinguishes the browser from the home computer, format validation
from fact-checking, and current features from future login/history plans.
No application or deployment changes were needed. The user has authorized
routine artifact creation/rendering/checking and local commits without repeated
command confirmations; see the scoped exception in AGENTS.md.

## Historical recovery

- `f092f9e`: removed the obsolete Node backend; pushed to main.
- `e0a8f58`: Rust deployed, with the old Node reference still present.
- `f30e065`: first Rust validation milestone.
- `d6b36d0`: TypeScript baseline.

Recover historical Node code into a separate checkout if explicitly needed.
System-level old unit backups alone are insufficient because the compiled Node
server was removed from this workspace. Do not restore Node as incidental work.
