# Rust backend migration

## Current checkpoint

The working TypeScript baseline is commit `d6b36d0` on `main`, pushed to GitHub
before starting the `rust-backend-migration` branch. The first Rust milestone is
a library in `backend/` plus a command-line example. There is no Rust HTTP server
yet. The TypeScript app remains the running implementation and reference behavior.

The frontend remains TypeScript throughout this migration. The user confirmed
that public access through Tailscale Funnel works; no changes to the home PC,
systemd, or Funnel are part of this checkpoint.

## Milestones

1. **Baseline and toolchain:** preserve the Node implementation, create a migration
   branch, and install stable Rust with rustfmt and Clippy.
2. **Validation (this checkpoint):** port question and answer validation into
   ordinary Rust functions with tests, before adding async code or HTTP libraries.
3. **HTTP and static assets:** add Axum and Tokio, `/healthz`, and the existing
   asset allowlist. Run Rust on loopback port `11437` alongside Node on `11436`.
4. **Ollama:** add Serde and reqwest, a shared HTTP client, the unchanged tutor
   prompt and schema, and the existing API response fields.
5. **Behavior parity:** adapt the existing HTTP tests to run against either
   implementation with the same mock Ollama backend. Add coverage for concurrency,
   cancellation, origin checks, body limits, headers, and shutdown.
6. **Deployment:** build for the Linux host, verify the public flow, and switch
   systemd to the Rust binary on `11436`. Preserve Node for rollback until the Rust
   deployment is proven. Update run/build scripts and remove Node backend code last.

## Run this checkpoint

Install the stable toolchain using [rustup](https://rust-lang.org/tools/install/).
The package uses Rust 2024 edition (Rust 1.85 or newer) and has no dependencies.
Commit `backend/Cargo.lock`; never commit `backend/target/`.

From the repository root:

```sh
cargo test --manifest-path backend/Cargo.toml --locked
cargo fmt --manifest-path backend/Cargo.toml --check
cargo clippy --manifest-path backend/Cargo.toml --locked --all-targets -- -D warnings
cargo run --manifest-path backend/Cargo.toml --locked --example validate -- "  Why is the sky blue?  "
```

The example prints the trimmed question on success. Blank or oversized input
prints the existing friendly validation message and exits unsuccessfully. It does
not send a question to Ollama. `npm start` and `npm test` keep their current meaning.

## Reading the code as a Rust lesson

Start with `backend/src/chat.rs`, then `backend/tests/validation.rs`, then the
`backend/examples/validate.rs` command-line example.

```rust
pub fn validate_question(input: &str) -> Result<&str, ValidationError>
```

- `&str` borrows text; it does not take ownership of the caller's `String`.
- The successful result is a slice of that input, so trimming needs no new string.
  Rust infers that the returned reference cannot outlive the input.
- `Result` makes success and failure explicit through `Ok` and `Err`.
- `ValidationError` is an enum. Pattern matching covers each failure case, while
  its `Display` implementation preserves the messages shown by the existing app.
- `validate_reply` returns owned `String` values. They remain available even when
  the original model-response strings are dropped.
- `?` propagates an error to the caller. The `match` in the CLI demonstrates how
  the caller handles both outcomes.
- `Vec<String>` stores the incoming variable-length suggestions; the validated
  reply uses `[String; 3]` to represent its required count.

Try these exercises before the HTTP milestone:

1. Explain why `validate_question` can return a reference to its argument, but
   cannot return a reference to a new local `String` created inside the function.
2. Compare `"🚀".len()`, `"🚀".chars().count()`, and
   `"🚀".encode_utf16().count()` in a scratch test. Predict each result first.
3. Add a test where the first and third suggestions are duplicates. Explain why
   `HashSet::insert` detects the duplicate without a separate lookup.

Use the [Rust Book's ownership chapter](https://doc.rust-lang.org/book/ch04-00-understanding-ownership.html)
and [Rustlings](https://rustlings.rust-lang.org/) for supporting exercises.

## Compatibility decisions

- Question and follow-up limits remain 2,000 and 180 **UTF-16 code units**,
  respectively, matching JavaScript `String.length`. Rust `str::len()` counts
  UTF-8 bytes instead; substituting it would reject some previously valid text.
- Trimming follows JavaScript's whitespace set. In particular, U+FEFF is removed
  and U+0085 is retained. Rust's default `trim()` behaves differently for these.
  See [ECMAScript whitespace](https://tc39.es/ecma262/multipage/ecmascript-language-lexical-grammar.html#sec-white-space)
  and [Rust string encoding](https://doc.rust-lang.org/std/primitive.str.html#method.encode_utf16).
- Suggestions are trimmed and compared using Unicode lowercase, preserving their
  display case and order. They need not end in a question mark, since the existing
  validator does not enforce one. No new maximum answer length is introduced.
- This library only accepts valid Rust strings. Handling malformed JSON, missing
  or non-string fields, and JavaScript's possible unpaired UTF-16 surrogates belongs
  to the JSON-boundary milestone. The current tests do not claim HTTP parity yet.
- No login, usage quotas, streaming, or prompt changes are included in the migration.

## HTTP contract to preserve in later milestones

- GET `/healthz` and the explicit static asset routes, with their content types.
- POST `/api/chat`: `{ "question": "..." }` in; `answer`, `followUps`, and
  `elapsedMs` out. Ignore additional request fields as the Node server does.
- Existing friendly JSON errors and HTTP statuses, including `400`, `403`, `404`,
  `405` (with `Allow: POST`), `413`, `415`, `429`, `502`, and `504`.
- An 8 KiB body limit, origin validation, security headers, and cache policy.
- At most two active Ollama calls; a third request is rejected immediately rather
  than queued. Release concurrency permits on success, failure, timeout, and cancel.
- The existing model, system prompt, structured reply schema, and non-streaming
  request. Upstream response parsing must validate both layers of JSON.
- A 120-second upstream deadline, disconnect handling, and graceful shutdown.

Axum's default extractor errors may not match Node's status codes or JSON shape.
Translate them deliberately. A timeout or client disconnect must not leave an
unbounded background model call; test this over real sockets rather than assuming
that dropping a handler cancels all work.
