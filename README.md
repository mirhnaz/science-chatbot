# Science Chatbot

A self-hosted science tutor with a TypeScript browser frontend and a Rust backend
that calls Ollama. It uses `qwen3:8b`, a fixed tutor prompt, and independent
questions without conversation history. Each answer includes three clickable,
self-contained follow-up questions. The tutor uses a kind, patient tone for
children aged 10–12.

For a child-friendly project explanation, see the
[classroom diagram and speaking notes](docs/diagrams/README.md).

## Run locally

Build prerequisites: stable Rust and Node.js 22 or newer. Run Ollama with the
configured model installed:

```sh
npm ci
ollama pull qwen3:8b
npm start
```

Open <http://127.0.0.1:11437>. `npm start` compiles the unchanged TypeScript
frontend and builds an optimized Rust binary before starting it. The installed
service explicitly uses port `11436`; the development default avoids colliding
with it. Run commands from the repository root.

```sh
npm run build          # frontend + release Rust binary
npm test               # Rust validation, HTTP integration, frontend interaction
npm run typecheck
npm run check:rust     # formatting and Clippy
```

A prebuilt deployment needs the Rust binary, `public/`, and `build/client/app.js`.
Node and Cargo are build/test tools; neither is needed to run that binary.
`npm run clean` removes `build/`; do not run it against a live deployment without
rebuilding the assets. Normal builds do not clear live assets first.

## Configuration

The app reads environment variables, not `.env` files.

| Variable | Default | Purpose |
| --- | --- | --- |
| `HOST` | `127.0.0.1` | Listen address |
| `PORT` | `11437` | Development port; systemd explicitly uses `11436` |
| `ASSET_ROOT` | `.` | Repository/deployment root containing `public/` and `build/` |
| `OLLAMA_BASE_URL` | `http://127.0.0.1:11434` | Ollama endpoint |
| `OLLAMA_MODEL` | `qwen3:8b` | Installed model |
| `PUBLIC_ORIGIN` | Unset | Exact allowed browser origin; when unset, compares request host |
| `OLLAMA_TIMEOUT_MS` | `120000` | Complete upstream deadline, including response body reads |

`PUBLIC_ORIGIN` is an origin check, not authentication. The existing deployment
uses public Tailscale Funnel directly to loopback port `11436`. Preserve its
working configuration. See [installation](docs/INSTALL.md) for systemd and
rollback instructions.

## Repository layout

```text
backend/src/chat.rs          Pure question and answer validation
backend/src/http.rs          Axum routes, assets, and Ollama integration
backend/src/main.rs          Configuration, listener, and shutdown
backend/src/tutor.txt        Unchanged system message
backend/src/reply-schema.json Unchanged structured response schema
backend/tests/              Rust validation tests
src/client/app.ts           Unchanged TypeScript browser code
public/                     HTML, CSS, images, icons, and manifest
assets/                     Original artwork, not served
test/                      Rust HTTP and frontend tests (TypeScript)
deploy/                     Service and proxy templates
docs/                       Migration lessons, installation, verification
build/                      Generated JavaScript, ignored
backend/target/             Generated Rust artifacts, ignored
```

The separate frontend build outputs `build/client/app.js`, served at `/app.js`.
Node.js runs the test harness and the TypeScript compiler; it does not serve the
application. `npm run build:tests` compiles the test files using
`tsconfig.test.json`. Keep `node_modules/` for these development dependencies.
The old Node backend is available in Git history at `e0a8f58`, rather than in
the active source tree.

See the [Rust migration guide](docs/RUST_MIGRATION.md) for small learning steps,
compatibility details, and the documented stricter handling of ill-formed JSON.
See [verification](docs/VERIFICATION.md) for test coverage and deployment checks.

The app does not persist questions or answers. Tests verify application behavior,
not scientific accuracy. Read aloud depends on browser voices and support.
