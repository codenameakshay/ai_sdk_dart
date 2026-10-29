---
name: verify-flutter-chat
description: Launch and drive the AI SDK Dart flutter_chat example app (examples/flutter_chat) as a release web build in headless Chromium, with the pinned JS reference backend, to prove user-facing behavior of the prebuilt chat widgets — local and remote conversations, tool approval, RTL strings, tab navigation, and the OpenAI-backed Chat/Completion/Object screens. Use when a change touches ai_sdk_flutter_ui, ai_sdk_conversation, ai_sdk_remote, examples/flutter_chat or examples/remote_backend and you need evidence from the real app, not only widget tests.
---

# Verify flutter_chat

This repository is a Dart SDK. Its user-facing surface is the example apps that consume it. The primary one is `examples/flutter_chat`: five tabs (Chat, Completion, Object, Local, Remote) built on the `ai_sdk_flutter_ui` prebuilt widgets. Local and Remote can also be opened as named routes; those are distinct entry points from the tabs. This skill builds it for the web, serves it on loopback, and drives it through Flutter's accessibility tree with Playwright over CDP.

Use `scripts/vfc` for all work. Run every command from the repository root. Each Bash call is a fresh shell, so put `VERIFY_RUN_ID=<id>` on every call (or `export` it in the same call):

```sh
S=.cursor/skills/verify-flutter-chat/scripts/vfc
$S new                                   # prints an id, e.g. vfc-20261029-082752-31814
VERIFY_RUN_ID=<id> $S build              # ~80 s first time; allocates this run's ports
VERIFY_RUN_ID=<id> $S up                 # backend + static server + headless Chromium
VERIFY_RUN_ID=<id> $S doctor             # must print only OK/INFO lines
VERIFY_RUN_ID=<id> $S scenario local-approve
VERIFY_RUN_ID=<id> $S down               # kills only this run's processes; evidence stays
```

Before you drive a feature, read `features/README.md` and the feature file for it.

## Requirements

- Flutter 3.44.3 through `fvm` (or set `FLUTTER=flutter`), Node.js, `python3`, `curl`, `ss`, `setsid`.
- Chromium or Chrome on `PATH` as `chromium`, `chromium-browser` or `google-chrome`, or set `CHROMIUM=/path`.
- Playwright for Node. `drive.cjs` looks in this order: `PLAYWRIGHT_MODULE`, a local or global `playwright`/`playwright-core`, then the copy bundled with the global `@playwright/mcp` package. If all fail, run `npm i -g playwright` (Chromium is still the system one, so no browser download is necessary).
- No API key for the Local, Remote and navigation features. The Chat, Completion and Object screens need `OPENAI_API_KEY` in the environment at **build** time (see `features/live-provider-screens.md`).

## Launch

`build` does these steps:

1. It selects three free loopback ports (web, backend, CDP) and writes them to `/tmp/verify-flutter-chat/runs/<id>/state.env`.
2. It runs `fvm flutter pub get` at the workspace root.
3. It runs `fvm flutter build web --release --no-pub --no-wasm-dry-run --no-web-resources-cdn` in `examples/flutter_chat` with `--dart-define=REMOTE_BACKEND_URL=http://127.0.0.1:<backend>/chat`, and with `--dart-define=OPENAI_API_KEY=...` only when that variable is set. The output goes to the run's `web/` directory. The log is `build.log`.
4. It records a source fingerprint from HEAD; tracked changes under `packages/` and `examples/flutter_chat/`; tracked changes to `pubspec.yaml`, `pubspec.lock` and `.fvmrc`; untracked files under `packages/` and `examples/flutter_chat/` (excluding build output and `.dart_tool`); package configs under those trees; and the root `pubspec.lock` and `.dart_tool/package_config.json` (or a missing-file marker). It stores the fingerprint in `BUILD_FINGERPRINT`, the built `main.dart.js` SHA-256 in `BUILD_SHA256`, the short HEAD in `BUILD_HEAD`, and the completed-build flag in `BUILD_OK`. State also records the backend URL and whether an OpenAI key was baked in.
5. If the `ai` package version is not the pinned `7.0.111`, it runs `npm ci` in `examples/remote_backend/js`.

`up` starts three process groups with `setsid`. Each process group's `.pid` file stores its leader PID and process start time:

| Process | Command | Ready when |
| --- | --- | --- |
| backend | `PORT=<backend> node server.mjs` in `examples/remote_backend/js` | `OPTIONS /chat` returns 204 |
| web | `python3 -m http.server <web> --bind 127.0.0.1 --directory <run>/web` | `GET /main.dart.js` returns 200 |
| chromium | `chromium --headless=new --remote-debugging-port=<cdp> --user-data-dir=<run>/profile` | `GET /json/version` answers |

`up` prints `ready: app http://127.0.0.1:<web> ...` when the three processes are ready. It refuses to start if this run already has live processes or if a port is in use.

After a source change, run `build` again with the same id. The existing instance can stay up; use `vfc browser open <route>` to load the new build. `up` refuses to start if this run already has live processes. `doctor` shows when a rebuild is necessary.

`vfc env` prints the URLs and paths of the run.

## Doctor

`VERIFY_RUN_ID=<id> $S doctor` is read-only. It prints `OK`, `FAIL` or `INFO` diagnostics for checks it reaches, and exits non-zero if a check fails. A shell/runtime error can stop it before all diagnostics are printed:

- The web build exists, and it contains this run's backend URL.
- The last build completed, its recorded `main.dart.js` SHA-256 matches the file on disk, and the build matches the current source fingerprint. If you see `FAIL build is stale`, rebuild, then reload the app with `browser open`.
- `INFO OpenAI key baked into build: yes|no`.
- Each recorded process is alive and owns its port (the listener is the recorded process or a member of its process group).
- The backend answers the CORS preflight and exposes `x-vercel-ai-ui-message-stream`.
- The web server serves the recorded `main.dart.js` SHA-256, and the Chromium CDP endpoint answers with its version. Curl checks use a five-second maximum time.

Run `doctor` first if something looks wrong. Do not drive an instance that fails it. Never drive an instance that another run id started: each run has its own browser profile and ports, and sharing one corrupts both runs' evidence.

Every `browser` and `scenario` call checks `BUILD_OK`, the source fingerprint, the on-disk `main.dart.js` hash, and the compiled backend URL before connecting to Chromium. It also verifies that this run owns the web and CDP ports. It does not require backend ownership, so `remote-unreachable` can run after `backend stop`. The command stops if any check fails.

## Drive

Flutter web paints to a canvas. The DOM only has an accessibility tree after the `Enable accessibility` placeholder is activated, and `drive.cjs` does this on every call. All handles are ARIA roles and accessible names from that tree. Do not use coordinates or CSS.

Canned scenarios run a full user path with assertions and evidence:

```sh
VERIFY_RUN_ID=<id> $S scenario <name>
```

| Scenario | Proves |
| --- | --- |
| `local-approve` | `/conversation` named route: approval card, composer locked while pending, keyboard Approve, `Tool result: deleted /tmp/example` |
| `local-deny` | `/conversation` named route at 390×844: Deny, `Tool denied; no local action ran.` |
| `remote-text` | `/remote` named route: one `POST /chat` with a `200` and `x-vercel-ai-ui-message-stream: v1`, the scripted answer in the body and in the UI |
| `remote-approve` / `remote-deny` | `/remote` named route approval: two `POST /chat` calls, the second carries `"approved":true/false`, the scripted resume text |
| `remote-unreachable` | Run `vfc backend stop` first. On `/remote`, shows the error banner with the startup command, `Dismiss` only (no `Retry`), and that dismiss clears it. Then run `vfc backend start` |
| `rtl-toggle` | The Arabic strings toggle mirrors the composer (Send moves left of the field), an approval in Arabic, and the conversation survives the switch back |
| `shell-nav` | Each bottom tab shows its expected screen title and is marked selected |

Primitives for paths that the scenarios do not cover. Each one connects to the run's browser, acts on the current page, and disconnects:

```sh
VERIFY_RUN_ID=<id> $S browser open /remote [--width 390 --height 844]  # fresh app instance; prints the a11y tree
VERIFY_RUN_ID=<id> $S browser aria                                     # print the current a11y tree
VERIFY_RUN_ID=<id> $S browser tab Local                                # switch shell tab
VERIFY_RUN_ID=<id> $S browser send "Request approval" [--expect "<text>"] [--lang ar]
VERIFY_RUN_ID=<id> $S browser click --name Approve [--keyboard] [--role button] [--substring]
VERIFY_RUN_ID=<id> $S browser type --name Prompt --text "Write a haiku about Flutter." # selects all, then types the replacement value
VERIFY_RUN_ID=<id> $S browser wait-text "The scripted tool call was approved and resumed."
VERIFY_RUN_ID=<id> $S browser state [--lang ar]   # composerEditable, sendEnabled, approvalPending, assistantRows, userRows
VERIFY_RUN_ID=<id> $S browser snapshot --name my-step   # my-step.aria.txt + my-step.png
```

Routes: `/` (the tab shell, starts on Chat), `/conversation` (Local) and `/remote` (Remote). The named routes push on top of the shell, so they show a `Back` button and no tab bar. `open` always reloads, which resets all in-memory conversation state.

Stable conversation handles: textbox `Message…`, buttons `Send message`, `Stop response`, `Approve`, `Deny`, `Retry`, `Dismiss`, the group `Assistant message`, the group `Tool approval required for <tool>`, and the text `Approve the tool call to continue.` The Arabic equivalents are in `drive.cjs` (`LABELS.ar`).

## Evidence

Evidence goes to `/tmp/verify-flutter-chat/evidence/<id>/` (override with `VFC_EVIDENCE_ROOT`). This directory is separate from the scratch directory, and `down` does not delete it.

- `<scenario>.json`: pass/fail, failure reason, build fingerprint and HEAD, viewport, each step with the observed state, network events with the SSE response bodies, and console or page errors.
- `<scenario>-final.{aria.txt,png}` and, for approval flows, `<route>-<action>-pending.{aria.txt,png}` (for example `local-approve-pending`): the state before and after the decision.
- `events.jsonl`: every call appends the requests it saw to non-app origins (backend, OpenAI, fonts), the failed requests, console errors and page errors.

Proof standards:

- Drive the real user path: type in the composer, click or press the control. Do not call controllers, use test-only routes, or replace the backend. The JS backend is the pinned production-shape boundary that the repo ships, and it is the only acceptable stand-in.
- Capture the action and the result: the pending snapshot and the final snapshot, not only the last screen.
- Verify side effects together with the pixels. For Remote, the request and response in the scenario JSON (method, status, stream header, body, the `approved` flag in the continuation) are the side effect. The Local tool does not touch the filesystem. Its proof is the exact result text, which the scripted model only emits after exactly one execution (approve) or zero executions (deny).
- Assistant messages must equal 1 after a turn. Duplicate assistant output is a known regression class in this app.
- Look at the PNGs. A passing text assertion does not mean the screen is visually correct.
- Report what you did not cover. The web build does not prove iOS/Android behavior, screen readers, or a live provider unless a key was baked in and you drove those screens.

## Cleanup

```sh
VERIFY_RUN_ID=<id> $S down
```

`down` verifies each recorded process identity before sending TERM (then KILL) to its process group. If a live PID no longer matches its recorded identity, or the group leader has exited while the group remains, `down` refuses cleanup and retains the run directory for inspection. On success, it deletes `/tmp/verify-flutter-chat/runs/<id>/`. That directory holds the build, which can contain a baked API key, plus the browser profile and logs. `down` keeps the evidence and prints its path. It never kills by process name. Run `down` after every failed iteration too. Use `ls /tmp/verify-flutter-chat/runs/` to find runs that were left behind.

## Helpers

- `scripts/vfc`: the lifecycle (`new`, `build`, `up`, `doctor`, `browser`, `scenario`, `backend stop|start`, `env`, `down`). `vfc help` lists them.
- `scripts/drive.cjs`: the Playwright driver. `vfc browser help` lists the primitives and scenarios. Add a scenario to its `SCENARIOS` map when a new feature file needs a repeatable proof.

## Gotchas

- Do not run two `build` commands at the same time in the same checkout. They share `examples/flutter_chat/.dart_tool`. Running instances side by side is safe.
- `up` attempts to stop the process groups it started if a readiness or ownership check fails.
- The backend URL is compiled in. A run's build only talks to that run's backend port, so do not reuse a `web/` directory across run ids.
- `type` and `send` select all existing field text, then type the replacement value with `pressSequentially`. DOM `fill` does not reliably reach Flutter's editing state.
- The app may request Roboto from `fonts.gstatic.com`; when offline, text can render with a fallback font while semantics remain available. Do not assume a keyless run has no other network activity.
- Without a key, requests from Chat, Completion or Object can fail (commonly with `401`) and show an error, but network-dependent outcomes are not guaranteed offline.
- `send` without `--expect` waits only 1 s before it prints the state. Use `--expect` or `wait-text` before you make an assertion.

## Other surfaces (not covered by this harness)

- `examples/basic`: a Dart CLI. `make run-mcp` runs the MCP demo with no key (in-process MCP server, discovery, one direct tool call). `make run-basic` needs `OPENAI_API_KEY`. To drive it, run it in a tmux session and capture the pane, and record the exit code.
- `examples/advanced_app`: a larger Flutter app (`make run-advanced-web`). It has the same build and serve shape on its own port, but no feature map yet.
- Native iOS/Android: the `flutter-chat-ios-e2e` workflow and `examples/flutter_chat/e2e/README.md` cover the simulator integration suite.
