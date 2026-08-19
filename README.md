# dsh-studio

A native macOS client for **dsh** — the [`@deepseek-ai/dsh`](https://www.npmjs.com/package/@deepseek-ai/dsh) coding-agent harness. SwiftUI, no Electron, no web view. It talks to a local dsh server over its JSON-RPC surface and a WebSocket event stream, and gives you a real Mac app for driving agent sessions.

> Unofficial and community-built. Not affiliated with or endorsed by DeepSeek. dsh is a separate project with its own license and terms.

![dsh-studio](docs/screenshot.png)

## Why

dsh ships a capable local agent harness, but the day-to-day surface is a terminal. dsh-studio wraps the same server in a native window: a session list, a live trajectory with streaming text and reasoning, tool calls, approvals, and the session controls (model, reasoning effort, permission mode, presets, goals) as first-class UI instead of slash commands.

## Features

- **Sessions** — list, create (pick a working directory), rename, fork, search.
- **Live trajectory** — streaming assistant text and reasoning, collapsible thinking, tool calls with arguments, and rendered markdown with copy-able fenced code blocks.
- **Model & reasoning** — switch model/provider and reasoning effort per session.
- **Approvals & questions** — respond to tool-approval prompts (with the actual arguments shown) and structured questions inline.
- **Session controls** — permission mode, agent presets, and available skills from the top bar.
- **Goals, jobs, subagents** — set and drive a session goal, watch background jobs, inspect and interrupt subagents.
- **Images** — attach images to a prompt; view image attachments from history.
- **Context & tokens** — token usage breakdown and a context-pressure meter.
- **Metal background** — a lightweight domain-warped gradient that responds to mouse and agent activity, paused when the window is occluded.

## Requirements

- macOS 14 or later
- [dsh](https://www.npmjs.com/package/@deepseek-ai/dsh) installed (`npm i -g @deepseek-ai/dsh`), reachable at `~/.npm-global/bin/dsh`
- An `ANTHROPIC_AUTH_TOKEN` line in `~/.hermes/.env` (used when the app launches its own dsh server)
- Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build & run

```bash
git clone https://github.com/kasparovabi/dsh-studio.git
cd dsh-studio
xcodegen generate
open DshStudio.xcodeproj   # then Run, or:
xcodebuild -scheme DshStudio -configuration Debug build
```

## How it connects

On launch the app probes `http://127.0.0.1:3080`. If a dsh server is already answering there it attaches to it; otherwise it launches its own `dsh web --port <port>` (reading the token from `~/.hermes/.env`) and shuts that child down on quit. Override the port with the `DSH_STUDIO_PORT` environment variable. Requests go to `POST /api/<method>`; events arrive on `ws://127.0.0.1:<port>/api/events.mux`.

## Notes and limitations

- dsh is pre-release; its RPC surface can change between versions, and this client tracks a specific snapshot of it.
- The token source (`~/.hermes/.env`) is currently hardcoded — adjust `ServerManager.swift` if yours lives elsewhere.
- The local dsh API is unauthenticated by design (loopback only); treat it like any other local dev server.
- Single-user, local-first. No telemetry, no accounts.

## License

MIT — see [LICENSE](LICENSE).
