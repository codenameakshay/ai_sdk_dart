# AGENTS.md

## Cursor Cloud specific instructions

This is a Dart/Flutter monorepo (AI SDK Dart) with 13 library packages and 3 example apps. No Docker, databases, or backend services are required — it is a pure client-side SDK.

### Toolchain

- **Flutter 3.41.4** (pinned in `.fvmrc`) with **Dart 3.11.1**
- **FVM** manages the Flutter version; the `Makefile` uses `fvm flutter` / `fvm dart` as command prefixes
- Flutter and Dart are installed at `/opt/flutter/bin`; FVM is installed via `dart pub global activate fvm`
- PATH must include `/opt/flutter/bin`, `/opt/flutter/bin/cache/dart-sdk/bin`, and `$HOME/.pub-cache/bin`

### Key commands

Standard dev commands are documented in the `Makefile` and `README.md`. The CI workflow (`.github/workflows/ci.yml`) uses simpler direct commands:

| Task | CI-style command | Makefile command |
|------|-----------------|-----------------|
| Install deps | `fvm dart pub get` | `make get` |
| Lint/analyze | `fvm dart analyze .` | `make analyze` |
| Run all tests | see per-package commands below | `make test` |
| Format | `fvm dart format packages/ examples/` | `make format` |

### Running tests

Run tests per-package using correct directory names:

```
fvm dart test packages/ai_sdk_dart/test/
fvm dart test packages/ai_sdk_openai/test/
fvm dart test packages/ai_sdk_anthropic/test/
fvm dart test packages/ai_sdk_google/test/
fvm flutter test examples/flutter_chat/
fvm flutter test examples/advanced_app/
```

### Gotchas

- `make test` / `make analyze` use the correct package paths (`packages/ai_sdk_dart/`, `packages/ai_sdk_flutter_ui/`, etc.) and both `flutter_chat` and `advanced_app` now ship widget tests, so the full `make test` target passes.
- All 999 tests use fake/mock models and JSON fixtures — no API keys are needed to run them.
- API keys (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GOOGLE_API_KEY`) are only needed for running the example apps with real AI providers.
- To build and serve the Flutter web app: `cd examples/flutter_chat && fvm flutter build web` then serve `build/web/` with any HTTP server.
