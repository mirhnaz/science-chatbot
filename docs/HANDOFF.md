# Project handoff

Updated: 2026-09-26. Read [../AGENTS.md](../AGENTS.md) for working rules.
This is a checkpoint, not a live service-status report. Check the current Git
state and relevant files after obtaining command authorization before changing
anything. Do not assume another agent has the preceding conversation.

## Current state

Science Chatbot is a self-hosted science tutor for children aged 10–12, created
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
  `elapsedMs`. Existing friendly errors, headers, and asset allowlist matter.
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
The release binary includes the new `/theme.js` asset route. **The live service
still needs a user-authorized restart** to load that route. Static assets are
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
`ios/ScienceChatbot.xcodeproj` and `ios/ScienceChatbot/Info.plist` are now
committed and edited in Xcode; `ios/project.yml` was deleted. Signing uses
`ios/Signing.xcconfig`, which optionally includes the ignored
`ios/Signing.local.xcconfig` holding the personal `DEVELOPMENT_TEAM`, so the
team ID stays out of Git. Choosing a Team in Xcode's UI would write it into
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

## Agreed direction, not yet implemented

The user expects login, conversation history, and more functionality over time.
Keep the current TypeScript frontend for now. Introduce React + TypeScript +
Vite when building the account/history screens, with Rust continuing to own the
backend APIs. No Next.js server is planned. This roadmap is not authorization to
start those features without a concrete next request.

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
