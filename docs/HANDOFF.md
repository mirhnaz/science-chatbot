# Project handoff

Updated: 2026-09-25. Read [../AGENTS.md](../AGENTS.md) for working rules.
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
- The old TypeScript/Node backend, compiled Node server, fallback npm scripts,
  local Node unit copy, and one-time migration script have been removed.
- TypeScript tests run under Node and exercise the Rust binary through real
  sockets with a mock Ollama server. `node_modules/` is still needed for frontend
  compilation and tests; its presence does not mean a Node backend is running.
- Work is on `main`. The latest implementation commit at this checkpoint is
  `f092f9e` (backend cleanup), pushed to `origin/main`. This handoff and AGENTS.md
  are a subsequent documentation change; check Git for their commit/push state.

## Code map

| File | Responsibility |
| --- | --- |
| `backend/src/chat.rs` | Pure question/reply validation and error types |
| `backend/src/main.rs` | Environment settings, listener, runtime, shutdown signals |
| `backend/src/http.rs` | Routes, asset allowlist, shared client, concurrency, Ollama, responses |
| `backend/src/tutor.txt` | Embedded tutor system message |
| `backend/src/reply-schema.json` | Embedded structured response schema |
| `backend/tests/validation.rs` | Rust validation tests |
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
  and `build/client/app.js`. The service's `PUBLIC_ORIGIN` is configured locally;
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

After backend cleanup, `npm test` passed all 18 Rust validation checks (17 tests
plus one doc example) and all 18 HTTP/frontend checks with no skipped cases.
`npm run typecheck` and `git diff --check` also passed. Rust formatting, Clippy,
release-build tests, and public HTTPS generation passed during the migration;
Rust source was unchanged by the cleanup. See [VERIFICATION.md](VERIFICATION.md).

No application changes are pending from that cleanup. This documentation update
does not require repeating the application suite. Future changes should run
relevant checks after command authorization. Mobile/audio behavior and startup
after a planned reboot were not separately verified in this session.

## Agreed direction, not yet implemented

The user expects login, conversation history, and more functionality over time.
Keep the current TypeScript frontend for now. Introduce React + TypeScript +
Vite when building the account/history screens, with Rust continuing to own the
backend APIs. No Next.js server is planned. This roadmap is not authorization to
start those features without a concrete next request.

Authentication approach, database choice, history retention, and detailed UI
requirements have not been decided. Clarify them when beginning the feature.
The current public-origin check is not authentication.

## Historical recovery

- `f092f9e`: removed the obsolete Node backend; pushed to main.
- `e0a8f58`: Rust deployed, with the old Node reference still present.
- `f30e065`: first Rust validation milestone.
- `d6b36d0`: TypeScript baseline.

Recover historical Node code into a separate checkout if explicitly needed.
System-level old unit backups alone are insufficient because the compiled Node
server was removed from this workspace. Do not restore Node as incidental work.
