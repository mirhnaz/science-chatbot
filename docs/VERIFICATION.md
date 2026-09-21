# Verification

Install dependencies and run strict type checks plus automated application checks:

```sh
npm ci
npm run typecheck
npm test
caddy validate --config deploy/Caddyfile --adapter caddyfile
```

`npm test` compiles the server, browser source, and tests before running the
compiled tests. The backend tests use a mock Ollama server. They cover the fixed model and
tutor prompt, invalid and cross-origin requests, upstream errors and timeouts,
empty responses, malformed or invalid follow-up suggestions, and serving static
assets from the compiled deployment layout. They do not require a running model.
A frontend interaction test checks that
clicking a suggestion submits its question, clears stale suggestions, prevents
duplicate requests, and displays new suggestions after the answer.

Deployment checks should cover the local page, `/healthz`, `/api/tags`, a real
question through the HTTPS URL, and boot startup. See [INSTALL.md](INSTALL.md).
Check desktop and mobile layouts, Stop, and Read aloud manually. Speech depends
on installed voices and browser support.

Automated tests verify application behavior, not the factual accuracy of model
answers. A successful health check does not prove Ollama can generate answers.
