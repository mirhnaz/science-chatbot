# Science Chatbot for iPad and iPhone

A native SwiftUI app with two ways to answer questions:

- **On this iPad** — runs a model inside the app with
  [llama.cpp](https://github.com/ggml-org/llama.cpp), the engine Ollama is
  built on. Works with no internet once the model file is on the iPad.
- **mir-ai-pc** — sends questions to the existing Rust server (which calls
  Ollama on the PC), for example through the Tailscale Funnel HTTPS address.

Ollama itself cannot run inside an iOS app: iOS does not let apps start a
separate server process. llama.cpp runs inside the app instead and reads the
same GGUF model files that Ollama uses.

The app bundles the server's `backend/src/tutor.txt` and
`backend/data/questions.json` directly, so the prompt and starter questions
stay identical. The reply rules from `backend/src/chat.rs` are ported to
`ScienceCore/Sources/ScienceCore/Validation.swift` and tested against the same
cases as `backend/tests/validation.rs`.

## Layout

```text
ScienceChatbot.xcodeproj  Xcode project (committed; edit it in Xcode)
App.xcconfig         Shared build settings; includes the ignored Local.xcconfig
ScienceCore/         Swift package: validation, reply decoding, JSON grammar, starter questions
LlamaFramework/      Swift package wrapping llama.cpp's prebuilt xcframework (pinned release)
KokoroFramework/     Swift package: sherpa-onnx + ONNX Runtime (pinned) and a small Kokoro wrapper
ScienceChatbot/      App: SwiftUI screens, local and remote engines, model files, read aloud
```

| File | Responsibility |
| --- | --- |
| `ScienceChatbot/LocalEngine.swift` | Loads the GGUF, applies the chat template, grammar-constrained generation |
| `ScienceChatbot/RemoteEngine.swift` | `POST /api/chat` and `/healthz` on the Rust server |
| `ScienceChatbot/ModelStore.swift` | Finds, imports, and downloads model files in Documents |
| `ScienceChatbot/ChatModel.swift` | Screen state: question, reply, loading, cancel, starters |
| `ScienceChatbot/NaturalVoice.swift` | Kokoro voice files (download, checksums) and sentence generation |
| `ScienceChatbot/Speech.swift` | Read aloud: natural voice with gapless sentence queue, Apple voice fallback |
| `ScienceChatbot/ContentView.swift` | Split view: Ideas sidebar, answer column, glass toolbar and compose bar ([design](../docs/DESIGN.md)) |
| `ScienceCore/.../ReplyGrammar.swift` | GBNF grammar: the on-device version of Ollama's `format` schema |

## Build on the Mac

Requirements: Xcode with the iOS platform installed, and an Apple ID. The app
needs iOS/iPadOS 26 or later (Liquid Glass).

The Xcode project is committed and managed in Xcode; add or remove files
there. `tutor.txt` and `questions.json` are referenced from `../backend/` as
app resources, not copied.

Your Apple team ID and the AI PC's hostname stay out of Git. Create
`ios/Local.xcconfig` (ignored):

```text
DEVELOPMENT_TEAM = ABCDE12345
SCIENCE_SERVER_HOST = your-pc.your-tailnet.ts.net
```

`SCIENCE_SERVER_HOST` (host only, no `https://`) is the app's AI PC address.
It is fixed at build time and cannot be changed on the iPad; without it,
AI PC mode is unavailable.

The team ID is the `OU=` value printed by
`security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject`,
or pick your Personal Team once in Xcode → Signing & Capabilities and copy it.
Choosing a Team in that screen instead writes it into `project.pbxproj`; do not
commit that change. If the bundle identifier is taken, change
`local.sciencechatbot.app` to something unique.

```sh
open ios/ScienceChatbot.xcodeproj
```

Connect the iPad with a cable, trust the Mac, and turn on
**Settings → Privacy & Security → Developer Mode** on the iPad (it restarts).
Choose the iPad as the run destination and press Run (⌘R). The first time,
allow the developer profile under **Settings → General → VPN & Device
Management** on the iPad.

With a free Apple ID the installed app stops opening after **7 days**; run it
again from Xcode to renew. A paid developer account extends this to a year.

From the command line (the device ID comes from `xcrun devicectl list devices`):

```sh
cd ios
xcodebuild -project ScienceChatbot.xcodeproj -scheme ScienceChatbot \
  -destination 'id=<device-id>' -derivedDataPath /tmp/sc-build \
  -allowProvisioningUpdates build
xcrun devicectl device install app --device <device-id> \
  "/tmp/sc-build/Build/Products/Debug-iphoneos/Science Chatbot.app"
```

## Put the model on the iPad

Recommended: `Qwen3-4B-Instruct-2507-Q4_K_M.gguf` (about 2.5 GB), a smaller
non-thinking member of the same Qwen3 family as the server's `qwen3:8b`.
Answers are a little simpler than the 8B model's. Choose one method:

1. **Download in the app**: Settings → Advanced → *Download recommended model* (needs
   internet once).
2. **Finder over a cable (no internet on the iPad)**: download the file on the
   Mac from
   <https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF>, then in Finder
   select the iPad → **Files** → drag the `.gguf` onto *Science Chatbot*.
   In the app, open Settings → Advanced → *Refresh list*. Or copy it from the Mac's
   terminal with the app installed:
   `xcrun devicectl device copy to --device <device-id> --domain-type appDataContainer --domain-identifier local.sciencechatbot.app --source <file>.gguf --destination Documents/<file>.gguf`
3. **Files app**: Settings → Advanced → *Import model file…* and pick a `.gguf`.

Then choose **On this iPad** or **Automatic** in Settings. The first question loads the model
(several seconds); later questions reuse it. Airplane mode is a good test.

Any GGUF chat model works, including Ollama's own blobs, but 8B models are
too large for most iPads. On an 8 GB M-series iPad, 4B Q4 is the sweet spot.

## Use the AI PC

Settings → Tutor has three modes:

- **Automatic** (default): asks the AI PC; falls back to the model on this
  iPad when there is no network (airplane mode skips the PC at once), when a
  4-second `/healthz` check fails, or when the server replies 429 (busy),
  502 (Ollama offline or unclear reply), or 503 (restarting). A 504 timeout
  and validation errors are shown instead, not retried locally. The status
  line names which one answered.
- **mir-ai-pc**: always the server. **On this iPad**: always local.

The AI PC address is `SCIENCE_SERVER_HOST` from `Local.xcconfig`; Settings
→ Advanced shows it with a *Test connection* button. The server's validation, two-request limit, and timeout apply. Native apps send no
browser `Origin` header, so no server change is needed.

## Settings

Settings is kept simple for 10–13 year olds: **Tutor** mode and
**Appearance**. Model files, the AI PC connection check, and the voice are on
**Advanced (for grown-ups)**, which opens with a do-not-change warning.

## Read aloud

English answers use a natural neural voice, Kokoro's **Michael**
(`am_michael`, speaker 16 of `kokoro-multi-lang-v1_0`), generated on the iPad
with [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) and no internet.
The answer is split into sentences; each one is generated while the previous
one plays, so there are no pauses between them. Stop halts it immediately.

The voice files (about 375 MB: `model.onnx`, `voices.bin`, `tokens.txt`,
`lexicon-us-en.txt`, and `espeak-ng-data/`) are downloaded in Settings →
Advanced → Read aloud from a pinned Hugging Face revision of
`csukuangfj/kokoro-multi-lang-v1_0`; the large files are checked against
their SHA-256. They live in `Documents/Kokoro/`. The full model was chosen
over int8: on Apple chips int8 generated about 2.5× slower for similar sound.

Other languages, a missing voice, the switch turned off, or a load failure use
Apple's voices: the best installed (Premium, then Enhanced, then Standard) for
the answer's language, or the one chosen in Settings. Apps cannot use Siri's
own voice.

`KokoroFramework/Package.swift` pins sherpa-onnx `v1.13.8` and ONNX Runtime
`1.28.2` by URL and checksum, copied from those projects' own `Package.swift`
files. Update each URL and checksum together.

## Adding files

Xcode manages the project, so add new Swift files in Xcode (or register them
in `project.pbxproj`); a file only on disk is not compiled.

## Checks

```sh
cd ios/ScienceCore && swift test        # validation, grammar, decoding, starters
cd ios && xcodebuild -project ScienceChatbot.xcodeproj \
  -scheme ScienceChatbot -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build         # compile check without signing
```

On the device: ask a starter question in airplane mode, tap a follow-up, press
Stop during an answer, use Read aloud, switch theme, and try the AI PC mode.

## Updating llama.cpp

`LlamaFramework/Package.swift` pins release `b11200`. To update, change the
URL's tag and set `checksum` to the zip's SHA-256 from the release page
(`gh api repos/ggml-org/llama.cpp/releases/tags/<tag>` shows it as `digest`).
The C API changes occasionally, so rebuild and rerun the device checks.
