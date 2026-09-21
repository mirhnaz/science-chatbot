# Science Chatbot

A self-hosted science tutor with a browser frontend and a small Node.js server
that calls Ollama. It uses `qwen3:8b` by default, a fixed tutor prompt, and
independent questions without conversation history. Each answer includes three
clickable, self-contained follow-up questions to keep exploring the topic.
The tutor uses a kind, patient tone for children aged 10–12.

## Run locally

Requires Node.js 22 or newer and a running Ollama instance with the model installed.
There are no third-party runtime dependencies. TypeScript and Node.js type
definitions are installed as development dependencies for building and checking
the server, browser code, and tests.

```sh
npm ci
ollama pull qwen3:8b
npm start
```

Open <http://127.0.0.1:11436>. `npm start` builds the project before starting it.
Run strict type checks with `npm run typecheck` and the mock-backend and browser
checks with `npm test` (which also builds first). To build without starting the
server, run `npm run build`.
Each build clears old generated files first; `npm run clean` removes only `build/`.

## Configuration

Set environment variables in your shell or systemd service. The app does not
automatically load `.env` files.

| Variable | Default | Purpose |
| --- | --- | --- |
| `HOST` | `127.0.0.1` | Listen address |
| `PORT` | `11436` | Listen port |
| `OLLAMA_BASE_URL` | `http://127.0.0.1:11434` | Ollama endpoint |
| `OLLAMA_MODEL` | `qwen3:8b` | Installed model |
| `PUBLIC_ORIGIN` | Unset | Exact allowed browser origin, including scheme, without a trailing slash; when unset, checks the request host |

`PUBLIC_ORIGIN` is an origin check, not authentication. The intended deployment
uses Tailscale Serve for private access, with Caddy and Node bound to loopback.
See [installation guide](docs/INSTALL.md) for systemd, Caddy, and boot startup instructions.

## Repository layout

```text
src/
  server.ts           Node.js static server and question API
  client/
    app.ts            Browser interaction code
public/               HTML, CSS, images, icons, and web manifest
assets/               Original design artwork, not served to browsers
test/                 Backend and browser tests written in TypeScript
deploy/               Caddy and systemd configuration templates
docs/                 Installation and verification guides
build/                Generated JavaScript; ignored by Git
package.json          Dependencies and build/run/test commands
tsconfig*.json        Shared, Node.js, and browser compiler settings
```

Node.js and TypeScript do not mandate these directory names. Here, `public/`
contains source assets and `build/` contains generated output. `dist/` is another
common name for generated output; this project uses `build/` consistently.
Keep application code in `src/`, and add subdirectories when there are enough
related modules to justify them.

The Node.js build preserves source paths: `src/server.ts` becomes
`build/src/server.js`, and `test/*.ts` becomes `build/test/*.js`. The separate
browser build compiles `src/client/app.ts` to `build/client/app.js`, served at
`/app.js`. This keeps browser and Node.js types separate without adding a bundler.

Edit the TypeScript sources and `public/` assets; do not edit `build/`.
Deploy `package.json` plus the complete `build/` and `public/` directories in
their existing relative locations. A prebuilt deployment can run
`node build/src/server.js` without npm dependencies installed. Keep `package.json`
so Node.js recognizes the compiled server as an ES module.

See [verification](docs/VERIFICATION.md) for automated and manual checks.

The app does not persist questions or answers. Model answers may be incorrect;
the tests verify application behavior, not scientific accuracy. Read aloud
depends on browser support and installed device voices.
