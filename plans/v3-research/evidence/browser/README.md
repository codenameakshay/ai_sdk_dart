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
