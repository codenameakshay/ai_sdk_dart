# AGENTS.md

## Repository instructions

This is a Dart/Flutter monorepo (AI SDK Dart) with 13 library packages and 3 example apps. No Docker, databases, or backend services are required — it is a pure client-side SDK.

### Toolchain

- **Flutter 3.44.3** (pinned in `.fvmrc`) with **Dart 3.12.2**
- **FVM** manages the Flutter version; the `Makefile` uses `fvm flutter` / `fvm dart` as command prefixes.
- In Cursor Cloud, Flutter is available at `/opt/flutter/bin`. Other environments
  should install FVM and let it resolve the version from `.fvmrc`.
- The active environment needs Flutter, its bundled Dart SDK, FVM, and the Dart
  pub cache on `PATH`.

### Key commands

Standard dev commands are documented in the `Makefile` and `README.md`. The CI workflow (`.github/workflows/ci.yml`) uses simpler direct commands:

| Task | CI-style command | Makefile command |
|------|-----------------|-----------------|
| Install deps | `fvm flutter pub get` | `make get` |
| Lint/analyze | `make analyze DART=dart FLUTTER=flutter` | `make analyze` |
| Run all tests | `make test DART=dart FLUTTER=flutter` | `make test` |
| Format | `make format-check DART=dart` | `make format` |

### Running tests

Run the complete matrix through the repository target:

```
make test
```

For a focused run, use the package's `test/` directory. The `make test` target
is the source of truth for the full package and example matrix.

### Gotchas

- `make test` / `make analyze` enumerate every package and example path. They
  use fake/mock models and JSON fixtures, so no API keys are needed.
- API keys (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GOOGLE_API_KEY`) are only needed for running the example apps with real AI providers.
- To build and serve the Flutter web app: `cd examples/flutter_chat && fvm flutter build web` then serve `build/web/` with any HTTP server.
