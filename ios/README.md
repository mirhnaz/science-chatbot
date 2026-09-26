# Science Chatbot for iPad and iPhone

A native SwiftUI app with two ways to answer questions:

- **On this iPad** — runs a model inside the app with
  [llama.cpp](https://github.com/ggml-org/llama.cpp), the engine Ollama is
  built on. Works with no internet once the model file is on the iPad.
- **My AI PC** — sends questions to the existing Rust server (which calls
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
project.yml          XcodeGen spec; generates ScienceChatbot.xcodeproj (not committed)
ScienceCore/         Swift package: validation, reply decoding, JSON grammar, starter questions
LlamaFramework/      Swift package wrapping llama.cpp's prebuilt xcframework (pinned release)
ScienceChatbot/      App: SwiftUI screens, local and remote engines, model files, read aloud
```

| File | Responsibility |
| --- | --- |
| `ScienceChatbot/LocalEngine.swift` | Loads the GGUF, applies the chat template, grammar-constrained generation |
| `ScienceChatbot/RemoteEngine.swift` | `POST /api/chat` and `/healthz` on the Rust server |
| `ScienceChatbot/ModelStore.swift` | Finds, imports, and downloads model files in Documents |
| `ScienceChatbot/ChatModel.swift` | Screen state: question, reply, loading, cancel, starters |
| `ScienceChatbot/Theme.swift` | Web colour palette (light and dark) and panel styles |
| `ScienceCore/.../ReplyGrammar.swift` | GBNF grammar: the on-device version of Ollama's `format` schema |

## Build on the Mac

Requirements: Xcode with the iOS platform installed, and an Apple ID.

```sh
brew install xcodegen          # once
cd ios
xcodegen                       # creates ScienceChatbot.xcodeproj
open ScienceChatbot.xcodeproj
```

In Xcode, select the **ScienceChatbot** target → **Signing & Capabilities**
→ Team: your Apple ID (“Personal Team”). If the bundle identifier is taken,
change `local.sciencechatbot.app` to something unique.

Connect the iPad with a cable, trust the Mac, and turn on
**Settings → Privacy & Security → Developer Mode** on the iPad (it restarts).
Choose the iPad as the run destination and press Run (⌘R). The first time,
allow the developer profile under **Settings → General → VPN & Device
Management** on the iPad.

With a free Apple ID the installed app stops opening after **7 days**; run it
again from Xcode to renew. A paid developer account extends this to a year.

Re-run `xcodegen` after pulling changes that add or remove Swift files.

## Put the model on the iPad

Recommended: `Qwen3-4B-Instruct-2507-Q4_K_M.gguf` (about 2.5 GB), a smaller
non-thinking member of the same Qwen3 family as the server's `qwen3:8b`.
Answers are a little simpler than the 8B model's. Choose one method:

1. **Download in the app**: Settings → *Download recommended model* (needs
   internet once).
2. **Finder over a cable (no internet on the iPad)**: download the file on the
   Mac from
   <https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF>, then in Finder
   select the iPad → **Files** → drag the `.gguf` onto *Science Chatbot*.
   In the app, open Settings → *Refresh list*.
3. **Files app**: Settings → *Import model file…* and pick a `.gguf`.

Then choose **On this iPad** in Settings. The first question loads the model
(several seconds); later questions reuse it. Airplane mode is a good test.

Any GGUF chat model works, including Ollama's own blobs, but 8B models are
too large for most iPads. On an 8 GB M-series iPad, 4B Q4 is the sweet spot.

## Use the AI PC

Choose **My AI PC** in Settings and enter the server's HTTPS address (for
example the Tailscale Funnel URL), then *Test connection*. The address is saved
only on the iPad. The server's validation, two-request limit, and timeout apply.
Native apps send no browser `Origin` header, so no server change is needed.

## Checks

```sh
cd ios/ScienceCore && swift test        # validation, grammar, decoding, starters
cd ios && xcodegen && xcodebuild -project ScienceChatbot.xcodeproj \
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
