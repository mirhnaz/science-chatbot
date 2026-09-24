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
npm run test:node
npm run typecheck
npm run check:rust
```

The release binary is `backend/target/release/science-chatbot-server`.
Keep `public/` and `build/client/app.js` under the deployment root. Set
`WorkingDirectory` or `ASSET_ROOT` to that root. The running Rust server does not
need Node or Cargo installed. Preserve the Node reference and its build during
the initial Rust observation period:

```sh
npm run build:node
```

## Verify beside the running service

Rust defaults to loopback port `11437`, so it can run beside Node on `11436`:

```sh
backend/target/release/science-chatbot-server
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

## Switch an existing systemd service

Inspect `systemctl cat science-chatbot-web.service` first, including any drop-ins.
Save the exact working Node unit before changing it. In a local copy, preserve
`User`, `WorkingDirectory`, all environment variables, especially `PUBLIC_ORIGIN`
and `PORT=11436`, and the existing enablement. Change only `ExecStart` to the
absolute release-binary path. Set `TimeoutStopSec=10s` as a final stop bound.
The repository's `deploy/science-chatbot-web.service` is a Rust template for new
installations; customize it rather than installing its example account/paths.

```sh
cp /etc/systemd/system/science-chatbot-web.service deploy/science-chatbot-web.node.local.service
cp deploy/science-chatbot-web.node.local.service deploy/science-chatbot-web.local.service
# Edit the local copy's ExecStart and TimeoutStopSec as described above.
systemd-analyze verify deploy/science-chatbot-web.local.service
sudo install -m 0644 deploy/science-chatbot-web.local.service /etc/systemd/system/science-chatbot-web.service
sudo systemctl daemon-reload
sudo systemctl restart science-chatbot-web.service
systemctl status science-chatbot-web.service --no-pager
curl --noproxy '*' --fail http://127.0.0.1:11436/healthz
```

Expect the main process to be `science-chatbot-server` and health to report
`{"status":"ok"}`. Check the existing public HTTPS URL for the page, assets,
and a real question. Confirm `tailscale serve status` still shows the original
mapping; do not run a new Serve/Funnel configuration command.

For a new installation, customize the template's account, paths, and origin,
install it, and enable the service. Keep local unit copies and hostnames out of
Git. Installed units are not automatically updated by edits to this repository.

## Roll back to Node

Restore the saved Node unit and restart the same service. No Funnel change is
needed because the port stays `11436`:

```sh
npm run build:frontend
npm run build:node
sudo install -m 0644 deploy/science-chatbot-web.node.local.service /etc/systemd/system/science-chatbot-web.service
sudo systemctl daemon-reload
sudo systemctl restart science-chatbot-web.service
curl --noproxy '*' --fail http://127.0.0.1:11436/healthz
```

For a manual fallback, stop the systemd service first, then `npm run start:node`.
Do not run both servers on port `11436`. Do not delete the Node reference or unit
backup until the Rust deployment has completed its observation period.

## Operations

```sh
journalctl -u science-chatbot-web.service -n 50 --no-pager
systemctl is-enabled science-chatbot-web.service ollama.service tailscaled.service
tailscale serve status
```

Check mobile and desktop layout, follow-up clicks, Stop, and Read aloud from a
browser. Speech depends on installed voices. A health check proves only the web
server is up; send a real question to verify Ollama. Recheck startup after the
next planned reboot; the migration itself does not require rebooting the host.

`PUBLIC_ORIGIN` is a browser-origin check, not login or authentication. Funnel
makes the app publicly accessible. The migration preserves the existing access
policy rather than changing it.
