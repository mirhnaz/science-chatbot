# Rust backend migration

## Current checkpoint

The backend now uses Rust, Axum, Tokio, and reqwest. The TypeScript frontend,
HTML, CSS, images, tutor prompt, model, and response schema are unchanged.
The baseline Node implementation is retained in `src/server.ts` for rollback and
as the reference used by compatibility tests. It is not the default npm server.
Baseline commits: `d6b36d0` (TypeScript), `f30e065` (Rust validation).

The Rust binary defaults to `127.0.0.1:11437` for safe side-by-side development.
The systemd template explicitly uses `127.0.0.1:11436`, preserving the deployed
Funnel destination. Do not reconfigure Funnel or Caddy to migrate the backend.
See [INSTALL.md](INSTALL.md) for deployment and rollback.

The live service was switched to Rust on 2026-09-24. Local and public HTTPS
checks, including a real Ollama question, passed. Node remains available solely
as a tested fallback during the observation period.

## Milestones implemented

1. Validation: pure functions and 18 passing checks (17 integration tests plus
   one documentation example).
2. HTTP: health endpoint, exact asset allowlist, MIME types, cache policy, security
   headers, and friendly method/route errors.
3. Ollama: one shared reqwest client, unchanged prompt/schema, validated two-layer
   JSON response, `answer`, `followUps`, and `elapsedMs` fields.
4. Behavior: shared HTTP tests against Rust and Node, including real sockets for
   concurrency, disconnects, timeouts during body reads, and shutdown.
5. Deployment tooling: optimized build, Rust-default npm scripts, systemd template,
   and Node rollback instructions. Runtime verification is recorded separately
   in [VERIFICATION.md](VERIFICATION.md).

## Run and check

Use the installed stable Rust toolchain and Node.js 22 or newer. The package uses
Rust 2024 edition with a declared minimum of 1.85; verification currently uses
Rust 1.98.1. The lockfile selects compatible dependency versions; the minimum
compiler version has not been separately tested. Commit `backend/Cargo.lock`,
never `backend/target/`.

```sh
npm ci
npm start                   # builds frontend + release Rust; loopback 11437
npm test                    # Rust validation + Rust HTTP/frontend checks
npm run test:node           # shared checks against retained Node reference
npm run typecheck
npm run check:rust          # rustfmt + Clippy with warnings denied
```

For a faster development loop:

```sh
npm run build:frontend
cargo run --manifest-path backend/Cargo.toml --locked
cargo run --manifest-path backend/Cargo.toml --locked --example validate -- "  Why is the sky blue?  "
```

Run from the repository root, or set `ASSET_ROOT` to its absolute path. Runtime
configuration is listed in [README.md](../README.md). No `.env` file is loaded.

## Small Rust lessons

### 1. Keep validation independent

Start with `backend/src/chat.rs` and `backend/tests/validation.rs`.

```rust
pub fn validate_question(input: &str) -> Result<&str, ValidationError>
```

`&str` borrows text, and the returned trimmed slice borrows that same text.
`Result` makes success and failure explicit. The reply validator returns owned
`String` values because the parsed upstream response will eventually be dropped.
The fixed `[String; 3]` makes the suggestion count part of the validated type.

### 2. Enter the asynchronous runtime

Read `backend/src/main.rs`. `#[tokio::main]` sets up the runtime. An `async`
function returns work that can pause at `.await` while a network operation is
pending. The runtime can drive other requests during that pause.

The binary binds the configured socket, builds an Axum router, and waits for
SIGINT or SIGTERM. Axum's graceful shutdown stops accepting connections; our
cancellation token also stops pending handlers, including incomplete uploads.

### 3. Share state safely

Read `Config`, `AppState`, and `app` in `backend/src/http.rs`. `Arc<AppState>` lets
handlers share ownership of one configuration, HTTP client, and semaphore.
Cloning an `Arc` adds an owner; it does not copy the state or create a new client.

The fallback handler deliberately checks methods itself: Axum's default routing
would otherwise add HEAD behavior and different error bodies. Asset paths come
only from the fixed allowlist, never directly from a user-provided filesystem path.

### 4. Bound model work by ownership

`try_acquire()` obtains one of two semaphore permits without waiting. A third
request gets `429` immediately. The `_permit` variable owns its slot until the
handler returns or is dropped. Rust then releases it automatically.

`tokio::time::timeout` wraps the complete upstream operation, including reading
its response body. Nothing spawns a detached model task. Real-socket tests verify
that disconnecting clients closes upstream sockets and returns permits.
The application can close a request; how quickly Ollama stops computation after
disconnection remains an upstream concern.

### 5. Translate the JSON boundary deliberately

The handler reads at most 8 KiB before parsing. It validates content type and
origin first, then uses the original validation functions. Extra ordinary JSON
fields are ignored. reqwest sends the fixed prompt embedded from `tutor.txt` and
the schema from `reply-schema.json`; tests compare the complete system message
with the Node reference.

## Compatibility decisions

- Question and follow-up limits remain 2,000 and 180 **UTF-16 code units**,
  matching JavaScript, rather than UTF-8 byte lengths.
- Trimming matches JavaScript: U+FEFF is removed; U+0085 is retained.
- Suggestions are trimmed and compared using Unicode lowercase, preserving
  display case and order. There is no new answer-length limit or requirement
  that suggestions end with a question mark.
- Invalid UTF-8 request bytes are decoded with replacement before JSON parsing,
  as in Node. Escaped **unpaired UTF-16 surrogates** are rejected by Rust's JSON
  parser with the existing unreadable-question `400`; Node accepts these strings.
  Serde also bounds JSON nesting and rejects out-of-range JSON numbers. Thus
  this is tested application-contract compatibility, not identical acceptance
  of every possible JavaScript JSON value. These cases do not reach Ollama.
- Missing/non-string questions use the existing validation error. Invalid inner
  model JSON uses the existing unclear-answer error; malformed outer JSON or
  transport failure uses the existing offline error.
- Shutdown returns a friendly `503` to pending requests, closes upstream work,
  and exits promptly. Node's older shutdown behavior waits for pending work.
- No login, quotas, streaming, prompt changes, frontend changes, or Funnel
  configuration changes are part of this migration.

## References

- [Rust ownership](https://doc.rust-lang.org/book/ch04-00-understanding-ownership.html)
- [Axum graceful shutdown](https://docs.rs/axum/0.8.9/axum/serve/struct.Serve.html#method.with_graceful_shutdown)
- [reqwest client](https://docs.rs/reqwest/0.12.28/reqwest/struct.ClientBuilder.html)
- [ECMAScript whitespace](https://tc39.es/ecma262/multipage/ecmascript-language-lexical-grammar.html#sec-white-space)
