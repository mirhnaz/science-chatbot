# Private self-hosted installation

Traffic flows from Tailscale HTTPS to Caddy on `127.0.0.1:11435`, then to the
web app on `127.0.0.1:11436`, which calls Ollama on `127.0.0.1:11434`.
Run these commands from the repository root on the host PC. Keep it powered on
and awake, and connect client devices to the same tailnet.

## 1. Check prerequisites

Install Node.js 22 or newer, Ollama, Caddy, and Tailscale using your system's
package management. Confirm Ollama is running and has the configured model:

```sh
node --version
command -v node
ollama pull qwen3:8b
```

No npm install or frontend build is required. Keep `dist/` with `server.mjs`.

## 2. Customize and install the web service

Make an ignored local copy of the template:

```sh
cp --no-clobber deploy/science-chatbot-web.service deploy/science-chatbot-web.local.service
```

Edit `deploy/science-chatbot-web.local.service`:

- Set `User` to the existing account that will run the app.
- Set `WorkingDirectory` to this repository's absolute path.
- Set `ExecStart` to the absolute Node executable followed by the absolute path
  to `server.mjs`. Use `command -v node` to locate Node. For mise installations,
  use an installed Node path or a maintained version alias. Systemd does not
  load your interactive shell configuration.
- Set `PUBLIC_ORIGIN` to the exact Tailscale HTTPS origin reported by
  `tailscale serve status`, such as `https://machine.tail-example.ts.net`, with
  no trailing slash. Update this value and restart the app if the domain changes.

The template values are examples; do not install it without customization.
Keep local hostnames, credentials, and personalized unit files out of Git.

```sh
systemd-analyze verify deploy/science-chatbot-web.local.service
sudo install -m 0644 deploy/science-chatbot-web.local.service /etc/systemd/system/science-chatbot-web.service
sudo systemctl daemon-reload
sudo systemctl enable science-chatbot-web.service
sudo systemctl restart science-chatbot-web.service
systemctl status science-chatbot-web.service --no-pager
curl --noproxy '*' --fail http://127.0.0.1:11436/healthz
```

Expect `{"status":"ok"}` from the health check.

## 3. Configure the dedicated Caddy proxy

The provided Caddyfile preserves GET `/api/tags` as a direct Ollama route.
All other requests go to the web app. Raw Ollama clients using `/api/generate`,
the old `/api/chat` payload, or other Ollama endpoints must use a separate
endpoint or be updated. The web app accepts `{ "question": "..." }` at `/api/chat`.

Validate before installation:

```sh
caddy validate --config deploy/Caddyfile --adapter caddyfile
```

If validation succeeds, back up any existing configuration and install it:

```sh
mkdir -p "$HOME/.config/science-chatbot"
if [ -f "$HOME/.config/science-chatbot/Caddyfile" ]; then
    backup_path=$(mktemp "$HOME/.config/science-chatbot/Caddyfile.before-web.XXXXXX")
    cp "$HOME/.config/science-chatbot/Caddyfile" "$backup_path"
    printf 'Backup: %s\n' "$backup_path"
fi
cp deploy/Caddyfile "$HOME/.config/science-chatbot/Caddyfile"
```

Use the existing user service `science-chatbot-caddy.service` if installed.
For a new installation, install the provided unit first:

```sh
mkdir -p "$HOME/.config/systemd/user"
cp --no-clobber deploy/science-chatbot-caddy.service "$HOME/.config/systemd/user/science-chatbot-caddy.service"
systemctl --user daemon-reload
systemctl --user enable science-chatbot-caddy.service
systemctl --user restart science-chatbot-caddy.service
```

Caddy has `admin off`, so use restart rather than reload. If an older Caddy
instance runs in a terminal on port 11435, stop that instance before starting
this service.

## 4. Tailscale and boot startup

If Tailscale Serve already maps HTTPS to `http://127.0.0.1:11435`, preserve that
mapping. Otherwise, configure it on the host:

```sh
tailscale serve --bg http://127.0.0.1:11435
tailscale serve status
```

Use the reported HTTPS origin for `PUBLIC_ORIGIN` in step 2. Do not enable
Funnel for this private deployment. Caddy and Ollama should remain on loopback.
`PUBLIC_ORIGIN` is a browser-origin check, not authentication; Tailscale access
rules control which tailnet users and devices can reach the service.

Check startup settings:

```sh
systemctl is-enabled science-chatbot-web.service ollama.service tailscaled.service
systemctl --user is-enabled science-chatbot-caddy.service
loginctl show-user "$USER" -p Linger
```

All services should report `enabled`. If necessary, enable the dependencies:

```sh
sudo systemctl enable --now ollama.service tailscaled.service
```

The user service needs `Linger=yes` to start without an interactive login:

```sh
sudo loginctl enable-linger "$USER"
```

Full-disk encryption may still require unlocking the host at boot.

## 5. Verify and troubleshoot

```sh
curl --noproxy '*' --fail http://127.0.0.1:11435/healthz
curl --noproxy '*' --fail http://127.0.0.1:11435/api/tags
journalctl -u science-chatbot-web.service -n 50 --no-pager
journalctl --user -u science-chatbot-caddy.service -n 50 --no-pager
```

Open the Tailscale HTTPS URL from a connected device. Submit a question and
check Stop and Read aloud. Speech availability depends on the browser and
installed voices. Check again after a reboot to verify the full startup path.

To roll back a proxy update, copy the saved backup over
`~/.config/science-chatbot/Caddyfile`, then run
`systemctl --user restart science-chatbot-caddy.service`.

References: [Tailscale Serve](https://tailscale.com/docs/features/tailscale-serve)
and [Caddy service guidance](https://caddyserver.com/docs/running).
