# Verification

From the repository root:

```sh
npm ci
npm test
npm run typecheck
npm run check:rust
npm run build
RUST_SERVER_BIN=backend/target/release/science-chatbot-server node --test build/test/*.test.js
```

`npm test` builds the unchanged frontend, TypeScript test files, and debug Rust
binary. It runs 21 Rust checks (17 validation tests, three question-bank tests, and one
documentation example), then all 23 HTTP/frontend checks against Rust with no backend selector
or skipped cases. Node runs the test harness and mock Ollama server only. Socket
tests need permission to bind loopback ports; they never load the real model.

Coverage includes:

- Byte-identical assets across the allowlist, MIME types, query handling,
  security headers, caching, source-file exclusion, and friendly route/method errors.
- Exact copied system prompt, schema, model, trimmed question, and response fields.
- JSON types, malformed bodies, UTF-16 limits, JavaScript whitespace, content
  types, host-based origins, and explicitly configured public origins.
- The 8 KiB limit with chunked uploads, two simultaneous model requests, immediate
  `429` for a third, and capacity recovery after success/error/timeout/disconnect.
- Real-socket upstream closure on client disconnect and body-read timeout.
- Friendly errors for unavailable models, transport failures, malformed outer
  and inner JSON, and invalid suggestions.
- Rust-specific graceful shutdown during model work and an unfinished upload,
  missing-asset errors, and explicit rejection of unpaired Unicode surrogates.
- Existing frontend interaction: following a suggestion submits it, clears stale
  suggestions, prevents duplicate requests, and renders new suggestions.

## Dynamic suggestions checks (2026-09-26)

- `npm test`, `npm run typecheck`, and `npm run check:rust` passed; the release
  binary built successfully.
- The bank tests check question validity, unique IDs/text, topic diversity, recent
  exclusions over repeated rounds, and a complete result if exclusions exhaust
  the available bank.
- HTTP tests verify four catalogue entries from different topics, repeat avoidance,
  no Ollama calls, no-store/security headers, method errors, and bounded exclusions.
- Browser-code tests cover loading, selection without submitting, refresh and
  duplicate-click prevention, bounded storage/reload history, unavailable/corrupt
  storage, network failure, malformed data, timeout, preserving drafts/old cards,
  and an overlapping chat request.
- Rendered the running development page at 1360×1150 and 390×1250 using headless
  Chromium and visually checked the question cards, text wrapping, and controls.
  These are viewport checks, not a physical phone or screen-reader audit.
- The user restarted the service on 2026-09-26. Local and public HTTPS health
  and suggestions checks passed: four distinct topics, no repeats from the
  immediately excluded batch, and no-store caching. Public HTML, JavaScript, and
  CSS matched the tested files. A real starter question returned an answer and
  three follow-ups in 2,916 ms. Funnel still points directly to port 11436.
  The temporary development server on 11437 was stopped afterward.

## Host checks during migration

Verified with Rust 1.98.1 on the Linux host:

- Rust release server on `127.0.0.1:11437` alongside Node on `11436`.
- Both health endpoints healthy; sampled live assets byte-identical.
- A real question through Rust returned an answer, three follow-ups, and elapsed
  time from the existing Ollama model.
- TypeScript type checking, Rust formatting, Clippy, and release-build tests pass.

On 2026-09-24, the installed systemd service was switched to the release Rust
binary on `127.0.0.1:11436`. It remains enabled and active. The existing Funnel
mapping still targets that same port; no proxy configuration was changed.
Both local and public HTTPS health checks passed. The public page, JavaScript,
CSS, banner, favicon, and manifest matched the local assets byte-for-byte.
A real question through the public HTTPS URL and its configured Origin returned
an answer, three follow-ups, and `elapsedMs: 3006`.

The temporary side-by-side Rust process on `11437` was stopped after testing.
After the user confirmed the deployed app works, the obsolete Node source,
compiled backend, local Node unit copy, and one-time migration script were
removed from the repository workspace. System-level historical backups were
left untouched. The old implementation remains in Git at `e0a8f58`; see
[INSTALL.md](INSTALL.md) for recovery guidance.

## Remaining manual checks

Desktop/mobile visual behavior, audio playback, and startup after a planned
reboot require separate checks. The frontend source and assets have not changed.
Tests verify application behavior, not scientific accuracy, and cannot guarantee
how quickly Ollama stops computing after its HTTP client disconnects.
