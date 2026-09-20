# Science Chatbot

A self-hosted science tutor with a browser frontend and a small Node.js server
that calls Ollama. It uses `qwen3:8b` by default, a fixed tutor prompt, and
independent questions without conversation history.

## Run locally

Requires Node.js 22 or newer and a running Ollama instance with the model installed.
There are no third-party npm dependencies or frontend build steps.

```sh
ollama pull qwen3:8b
npm start
```

Open <http://127.0.0.1:11436>. Run the mock-backend checks with `npm test`.

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
See [INSTALL.md](INSTALL.md) for systemd, Caddy, and boot startup instructions.

## Repository layout

- `dist/`: frontend files served directly; these are required runtime assets.
- `server.mjs`: static server and bounded question API.
- `deploy/`: portable configuration templates. Customize ignored local copies.
- `test/`: automated tests with a mock Ollama backend.

The app does not persist questions or answers. Model answers may be incorrect;
the tests verify application behavior, not scientific accuracy. Read aloud
depends on browser support and installed device voices.
