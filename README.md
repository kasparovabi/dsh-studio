<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/logo-dark.png">
    <img src="docs/logo.png" alt="dsh-studio" width="96" height="96">
  </picture>
</p>

# dsh-studio

A native macOS client for **dsh**, the [`@deepseek-ai/dsh`](https://www.npmjs.com/package/@deepseek-ai/dsh) coding agent harness. SwiftUI, no Electron, no web view. It talks to a local dsh server over its JSON-RPC surface and a WebSocket event stream, and gives you a real Mac app for driving agent sessions.

> Unofficial, built by the community. Not affiliated with or endorsed by DeepSeek. dsh is a separate project with its own license and terms.

![dsh-studio](docs/screenshot.png)

▶ [Watch a 20 second demo](docs/demo.mp4)

## Why

dsh ships a capable local agent harness, but everyday use runs through a terminal. dsh-studio wraps the same server in a native window: a session list, a live trajectory with streaming text and reasoning, tool calls, approvals, and the session controls (model, reasoning effort, permission mode, presets, goals) as real interface elements instead of slash commands.

## Features

- **Sessions.** A browser grouped by date (Today / Yesterday / Last 7 days / Older) sorted by recency, showing the project, relative time, turn count and a live dot on every row. Filter by project, search, create (pick a working directory), rename, fork. Every session already on disk shows up, including ones started from the dsh CLI long before this app.
- **History recovery.** The dsh server refuses to serve a session log whose sequence numbers or frame boundaries fail its integrity check. When that happens the app reads the log itself, skips the records it cannot parse, and shows the transcript instead of an error.
- **Live trajectory.** Streaming assistant text and reasoning, collapsible thinking, tool calls with arguments, and rendered markdown with fenced code blocks you can copy.
- **Model & reasoning.** Switch model, provider and reasoning effort per session.
- **Approvals & questions.** Respond to tool approval prompts (with the actual arguments shown) and structured questions inline.
- **Session controls.** Permission mode, agent presets, and available skills from the top bar.
- **Settings.** The gear button opens a panel where you enter each provider's API key or token and set the default model, written through dsh's own credential store (`~/.dsh/.credentials.yaml`) so a fresh install needs no shell setup.
- **Goals, jobs, subagents.** Set and drive a session goal, watch background jobs, inspect and interrupt subagents.
- **Images.** Attach images to a prompt; view image attachments from history.
- **Context & tokens.** Token usage breakdown and a meter for context pressure.
- **Metal background.** A light animated gradient that responds to mouse and agent activity, paused when the window is occluded.

## Requirements

- macOS 14 or later
- [dsh](https://www.npmjs.com/package/@deepseek-ai/dsh) installed (`npm i -g @deepseek-ai/dsh`), reachable at `~/.npm-global/bin/dsh`
- Provider credentials for the models you use. Enter them in the app's Settings panel (the gear button), which stores each key in dsh's credential store and applies it on the next request. dsh also reads keys from the env var named by `apiKeyEnv` in `~/.dsh/settings.yaml`; when the app launches its own server it forwards the environment of your login shell plus every key in `~/.hermes/.env`, so an existing shell setup keeps working for any provider, not just Anthropic. A key supplied by the environment is shown but cannot be edited in the panel, since dsh treats the launching environment as authoritative.
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

On launch the app probes `http://127.0.0.1:3080`. If a dsh server is already answering there it attaches to it; otherwise it launches its own `dsh web --port <port>` (forwarding the environment of your login shell and `~/.hermes/.env` so every configured provider is available) and shuts that child down on quit. Override the port with the `DSH_STUDIO_PORT` environment variable. Requests go to `POST /api/<method>`; events arrive on `ws://127.0.0.1:<port>/api/events.mux`.

## Notes and limitations

- dsh is prerelease; its RPC surface can change between versions, and this client tracks a specific snapshot of it.
- Credentials are taken from the environment of your login shell and `~/.hermes/.env`. If you keep keys elsewhere, export them in your shell profile or add them to `~/.hermes/.env`.
- The local dsh API is unauthenticated by design (loopback only); treat it like any other local dev server.
- One person, one machine, nothing leaves it. No telemetry, no accounts.

## License

MIT. See [LICENSE](LICENSE).
