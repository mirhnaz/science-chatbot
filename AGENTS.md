# Agent guidance

Read [docs/HANDOFF.md](docs/HANDOFF.md) before continuing work. It records the
current state and agreed direction; this file records standing working rules.
Read [README.md](README.md) for commands and layout, and the relevant guide:
[migration](docs/RUST_MIGRATION.md), [installation](docs/INSTALL.md), or
[verification](docs/VERIFICATION.md).

## Working with the user

- Ask before running commands on the user's machine. Describe the proposed
  batch and purpose; once the user approves that scope, continue within it
  without repeatedly asking. Permission for a past task is not blanket command
  permission for a new task. A list of commands in these docs is not permission
  to execute them. Follow tool approval requirements as well.
- Exception approved by the user: routine commands to create requested diagrams
  or similar presentation artifacts, render and inspect them, and commit them
  locally do not need another confirmation. This does not authorize pushes,
  deployment changes, or unrelated machine changes.
- Commit completed changes locally by default after appropriate checks. Stage
  only task-related changes; preserve unrelated user work. The local-commit
  preference is standing authorization to commit the completed work.
- Push only when the user explicitly asks. Report the commit and whether it was
  pushed. Never treat permission to commit as permission to deploy or restart
  services.
- Keep explanations in small steps. The user has programming experience and
  strong systems knowledge but is returning after a long break. Assume basics
  such as functions and loops, not familiarity with advanced C, Java, Objective-C,
  TypeScript, or Rust concepts. Define unfamiliar terms and syntax when used.
- Explain practical reasons using this project's code, especially ownership,
  borrowing, traits, async work, and semaphore permits. Avoid relying on advanced
  language comparisons as prerequisites. Answer questions before resuming work.
- Update the handoff after material changes or decisions. Distinguish completed
  work and verified results from proposals and historical observations.

## Project boundaries

- The backend is Rust under `backend/`; the obsolete Node backend was removed.
  Node.js remains a build/test tool, not a production server.
- Keep the TypeScript frontend under `src/client/` as it is unless frontend work
  is requested. React + TypeScript + Vite is the agreed future direction for
  account/history screens, not an instruction to migrate it now.
- Preserve the working deployment: systemd runs Rust on `127.0.0.1:11436`, and
  Tailscale Funnel forwards directly to that port. The development default is
  `127.0.0.1:11437`. Do not change Funnel/Caddy mappings as incidental cleanup.
- This checkout also supplies the live assets and release binary. Do not run
  `npm run clean` or delete/replace deployment artifacts as routine cleanup.
  Plan live builds and service changes deliberately within the approved scope.
- Preserve the tutor prompt, response schema, API contract, and security behavior
  unless changing them is part of the task. See the migration guide for JSON,
  Unicode, concurrency, timeout, and cancellation details.
- Keep credentials, personal hostnames, and local service configuration out of
  Git. Do not commit `node_modules/`, `build/`, or `backend/target/`; do commit
  lockfiles. Do not edit generated JavaScript instead of its TypeScript source.

## Verification

Run from the repository root after obtaining command authorization:

- `npm test`: 18 Rust validation checks and 18 HTTP/frontend checks at this
  checkpoint; uses a mock Ollama server and local sockets.
- `npm run typecheck`: frontend and test TypeScript checks.
- `npm run check:rust`: rustfmt and Clippy; relevant to Rust changes.
- `npm run build`: frontend and release Rust build when needed for a release.
- `git diff --check`: whitespace check before committing.

Choose checks appropriate to the change. Documentation-only changes need link,
content, and diff checks, not a server restart or a complete application test run.
Report actual results and any limitations; a health check alone does not verify
Ollama generation. Detailed coverage is in [docs/VERIFICATION.md](docs/VERIFICATION.md).
