# Flutter web fixture smoke — 2026-09-23

Build command (from `examples/advanced_app`):

```sh
fvm flutter build web --release
```

Result: exit 0, JavaScript release build, 113.4 seconds. Flutter also reported a
successful Wasm dry run; Wasm runtime was not tested. The build warned that a
referenced CupertinoIcons font family was absent. Build log:
`/tmp/v3-flutter-web-build.log`.

Serve from the repository root:

```sh
python3 -m http.server 8082 --bind 127.0.0.1 --directory examples/advanced_app/build/web
```

Run `approval-smoke.cjs` with Playwright installed. `PLAYWRIGHT_MODULE` can name
the installed module when it is outside Node's ordinary resolution paths.
Chromium 154.0.8037.0 was used. This container cannot run Chromium's normal
sandbox; the script launches a fresh headless browser with Chromium sandboxing
disabled and visits only the local fixture server.

Verified:

- At 1280 × 900, focusing Approve and pressing Enter displays the expected
  fixture confirmation.
- At 390 × 844, clicking Deny displays the expected fixture confirmation.
- Both pages expose approval controls and the disabled composer in Flutter's
  semantics tree. Semantics were activated programmatically through Flutter's
  accessibility placeholder; this does not prove screen-reader startup behavior.
- No page errors were captured. Screenshots were opened and visually inspected.

Artifacts:

- `approval-desktop.png`: initial desktop pending-approval fixture.
- `approval-keyboard-desktop.png`: keyboard action and confirmation.
- `approval-mobile-viewport.png`: narrow viewport pending-approval fixture.
- `approval-smoke.json`: browser version, dimensions, assertions and semantics.

These are fixture callbacks. They do not execute a provider or approved tool,
prove a persisted approval resumes, or establish device/mobile accessibility.
The real local-backend execution and restore tests cover different boundaries.
This checkpoint also predates remaining source changes; final release evidence
needs a rebuilt app. No before/after visual improvement is claimed from these
screenshots.

## Conversation backend checkpoint

`examples/flutter_chat` was built with `fvm flutter build web --release --no-pub`
(exit 0, 70.4 seconds; the same missing CupertinoIcons font warning). Serve its
`build/web` on port 8083 and run the pinned JS backend on port 8081, then run:

```sh
PLAYWRIGHT_MODULE=/path/to/playwright node plans/v3-research/evidence/browser/conversation-smoke.cjs
```

The parent ran this command successfully. `conversation-smoke.json` records
browser version, exact build/source hashes, semantics, and zero page errors.
The local model checks the actual resumed tool result and execution count:
keyboard approval runs the simulated tool exactly once; narrow-viewport denial
runs it zero times. No filesystem deletion occurs. Remote text traverses the
prebuilt widget, conversation backend, HTTP transport, and pinned JavaScript
AI SDK server. All three return the composer to an enabled state.

The first remote browser run failed CORS preflight because the example server
did not allow `x-vercel-ai-ui-message-stream`. The server now allows and exposes
that header; the identical browser flow passes. The script uses ordinary key
input because direct DOM `fill` did not reliably reach Flutter's editing state
in the narrow viewport.

Visual inspection found **duplicate assistant output** in the saved screenshots:
the conversation adapter exposes the same answer through both message history
and optimistic streaming content. This remains an open UI defect at this
checkpoint; successful content assertions do not imply visual acceptance.
These artifacts do not qualify persistent reload, remote approval continuation,
live providers, native devices, or screen-reader interaction.

## Subsequent rebuild and remaining accessibility failure

The next stable build completed in 84.4 seconds. The duplicate assistant row is
visibly removed (`intermediate-no-duplicate-Approve.png`), but its replacement
exposes an empty disabled textbox in Chromium's accessibility tree. The earlier
text locator had been matching the unwanted optimistic row. The browser test
now requires the answer in the accessibility tree and exactly one assistant
row; this remains red until the selectable answer has correct semantics.

The JS example now accepts the user phrase `Request approval` to initiate a
scripted approval from an empty remote conversation. Both remote decisions
resume over HTTP with status 200 and render output; intermediate screenshots
are saved. Console inspection caught a Flutter web text-editing null-check
exception during those transitions. The formal script now monitors console
errors too. These intermediate images are diagnostic evidence, not a passing
five-flow browser report. `before-conversation-*` preserves the earlier
duplicate-row state for comparison.
