# Offline iOS conversation E2E

The conversation suite runs local and remote approval flows on an iOS
Simulator. It uses Flutter 3.44.3, the static JavaScript backend fixture, and
the `integration_test` package. It does not require an OpenAI key.

The GitHub workflow is
`.github/workflows/flutter-chat-ios-e2e.yml`. It boots one available iPhone
Simulator, starts the pinned reference backend, runs the suite twice, and
uploads screenshots from both runs. It can be started manually and runs for
pull requests that touch the harness, conversation UI, remote fixture, or
workspace dependency manifests.

To run locally on macOS:

```sh
cd examples/remote_backend/js
npm ci
node server.mjs
```

In another terminal, from the repository root:

```sh
fvm flutter pub get
cd examples/flutter_chat
fvm flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/conversation_e2e_test.dart \
  -d <ios-simulator-udid> \
  --dart-define=REMOTE_BACKEND_URL=http://127.0.0.1:8081/chat
```

Run that command twice. The extended integration driver writes the named PNG
screenshots into the current directory. The test also includes a backend error
fixture for the scaffold's `Retry`/`Dismiss` presentation.

The `/conversation` and `/remote` routes are not reachable from the shipped
navigation shell, so the integration test boots those public page widgets
directly. The app has no tracked iOS `Podfile`, native integration-test target,
or `flutter_driver` dependency; Flutter's SDK integration-test package and the
existing Runner project are sufficient for this harness. The workflow does not
claim physical-device coverage or provider/API coverage.

The CI harness builds and installs the integration target once, launches it
paused on a fixed loopback VM-service port, and attaches `flutter drive` with
`--use-existing-app`. This avoids log-based VM-service discovery, which missed
a recorded service address in run35882901359. The app restarts before each
required run. Debug-service authentication is disabled only for this isolated,
key-free simulator fixture; no production app configuration is changed.
