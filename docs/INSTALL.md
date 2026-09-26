# Build, deploy, and roll back

The backend is Rust; the frontend remains TypeScript. The existing host uses
Tailscale Funnel directly to `127.0.0.1:11436`. Preserve that working mapping.
A separate Caddy configuration is supplied for installations that already use
it, but switching the backend does not require changing any proxy configuration.

## Build and test

Install stable Rust and Node.js 22 or newer for building, and run Ollama with the
configured model. From the repository root:

```sh
npm ci
npm run build
npm test
npm run typecheck
npm run check:rust
```

The release binary is `backend/target/release/curio-server`.
Keep `public/` and `build/client/app.js` under the deployment root. Set
`WorkingDirectory` or `ASSET_ROOT` to that root. The running Rust server does not
need Node or Cargo installed. Node.js is used only to compile the frontend and
run the TypeScript tests.

## Verify beside the running service

Rust defaults to loopback port `11437`, so it can run beside the deployed service on `11436`:

```sh
backend/target/release/curio-server
```

In another terminal:

```sh
curl --noproxy '*' --fail http://127.0.0.1:11437/healthz
curl --noproxy '*' --fail http://127.0.0.1:11437/app.js
curl --noproxy '*' --fail http://127.0.0.1:11437/api/chat \
  -H 'Content-Type: application/json' --data '{"question":"Why is the sky blue?"}'
```

Verify `answer`, exactly three `followUps`, and numeric `elapsedMs`. Stop the
side-by-side instance with Ctrl+C after checking it.

## Install or update the systemd service

Inspect `systemctl cat curio-web.service` first, including any drop-ins.
For an existing installation, preserve `User`, `WorkingDirectory`, all environment
variables, especially `PUBLIC_ORIGIN` and `PORT=11436`, and enablement. The current
service already runs Rust; removing the old Node source requires no restart.

For a new installation, copy `deploy/curio-web.service` to
`deploy/curio-web.local.service`. Customize the account, working
directory, absolute release-binary path, and public origin. Do not install the
example values unchanged. Local unit copies are ignored by Git.

After building and testing, install the customized unit:

```sh
systemd-analyze verify deploy/curio-web.local.service
sudo install -m 0644 deploy/curio-web.local.service /etc/systemd/system/curio-web.service
sudo systemctl daemon-reload
sudo systemctl enable curio-web.service
sudo systemctl restart curio-web.service
systemctl status curio-web.service --no-pager
curl --noproxy '*' --fail http://127.0.0.1:11436/healthz
```

Expect the main process to be `curio-server` and health to report
`{"status":"ok"}`. Check the existing public HTTPS URL for the page, assets,
and a real question. Confirm `tailscale serve status` still shows the original
mapping; do not run a new Serve/Funnel configuration command.

Installed units are not automatically updated by edits to this repository.

## Recover an earlier version

Keep a known-good release binary and matching frontend assets before deploying
future changes. To roll back, restore that release and restart the web service
with its existing environment and port; the Funnel mapping stays unchanged.

The obsolete Node backend and its npm commands are no longer in the active tree.
Commit `e0a8f58` preserves the last version with the Node fallback and its original
build instructions. If that fallback is ever needed, recover it into a separate
checkout and follow that version's installation guide. Old system-level Node unit
backups alone are insufficient: their executable path pointed to the compiled
JavaScript backend, which has now been removed from this workspace.

## Operations

```sh
journalctl -u curio-web.service -n 50 --no-pager
systemctl is-enabled curio-web.service ollama.service tailscaled.service
tailscale serve status
```

Check mobile and desktop layout, follow-up clicks, Stop, and Read aloud from a
browser. Speech depends on installed voices. A health check proves only the web
server is up; send a real question to verify Ollama. Recheck startup after the
next planned reboot; the migration itself does not require rebooting the host.

`PUBLIC_ORIGIN` is a browser-origin check, not login or authentication. Funnel
makes the app publicly accessible. The migration preserves the existing access
policy rather than changing it.
