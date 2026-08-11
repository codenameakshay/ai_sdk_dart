# Release and Platform Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the release reproducible, documentation executable, examples representative, and provider contract ready for the next capability stage.

**Architecture:** Root tooling is the single source of truth for versions and quality gates. Contract fixtures define cross-provider behavior before provider implementations adopt a new specification version.

**Tech Stack:** FVM, Dart/Flutter analysis and tests, GitHub Actions, Markdown examples, JSON conformance fixtures.

---

### Task 1: Pin and install the toolchain

**Files:**
- Modify: `.fvmrc`
- Modify: `.github/workflows/ci.yml`
- Modify: SDK constraints where required

- [ ] Set `.fvmrc` and CI to the same exact Flutter release and install it with FVM.
- [ ] Run `fvm flutter --version` and record the Flutter/Dart pair in the README development section.
- [ ] Align Dart and Flutter lower bounds so no declared Flutter version can violate the Dart constraint.
- [ ] Run dependency resolution and commit.

### Task 2: Complete quality gates

**Files:**
- Create: root `analysis_options.yaml`
- Modify: `Makefile`
- Modify: `tool/coverage.sh`
- Modify: `.github/workflows/ci.yml`

- [ ] Add the existing lint package's recommended rules at the root without adding dependencies.
- [ ] Add `ai_sdk_flutter_ui` to `make test` and `ai_sdk_provider` to coverage.
- [ ] Add non-writing format verification to CI and make the repository conform to the pinned formatter.
- [ ] Run `make analyze`, `make test`, and the coverage gate; commit.

### Task 3: Documentation correctness

**Files:**
- Modify: root and package `README.md` files, example READMEs, changelogs, and configuration comments
- Add: compile-checked snippet files under existing package examples/tests

- [ ] Correct Google provider class/key names, missing imports, controller signatures, package versions, and nonexistent commands.
- [ ] Replace shell-export claims with explicit CLI/server environment access and compile-time-define examples where appropriate.
- [ ] Add prominent production guidance for proxy or short-lived credentials in distributable clients.
- [ ] Compile/analyze public snippets and commit.

### Task 4: Example smoke coverage

**Files:**
- Modify: `examples/flutter_chat/test/widget_test.dart`
- Modify: `examples/advanced_app/test/widget_test.dart`
- Modify example code only where tests reveal broken flows

- [ ] Add deterministic fake-model smoke navigation through every documented primary screen.
- [ ] Cover streaming text, Stop, retry, tool approval, structured output, and state restoration without network keys.
- [ ] Run both example test suites and commit.

### Task 5: Provider-contract modernization fixtures

**Files:**
- Add contract types/tests in `packages/ai_sdk_provider/lib/src/` and `packages/ai_sdk_provider/test/`
- Add cross-provider fixtures under `packages/ai_sdk_dart/test/conformance/specs/`
- Modify provider adapters incrementally as required

- [ ] Define typed timeout scopes, runtime context, reasoning controls, approval policy metadata, and telemetry metadata needed by the next provider contract.
- [ ] Add failing provider-contract tests for serialization-neutral propagation of each field.
- [ ] Introduce the new specification version and migrate core before concrete providers.
- [ ] Migrate each provider in working groups, deleting V3-only paths after the final provider moves.
- [ ] Run all provider and core suites after each group; commit each working migration stage.

### Task 6: Final verification and screenshots

**Files:**
- Create/update: `docs/screenshots/next-release-*.png`
- Modify: release changelogs and version metadata after verification

- [ ] Run formatter verification, analyzer, all tests, coverage, and Flutter web builds from a clean dependency resolution.
- [ ] Launch the deterministic advanced example and capture normal, approval, error, sources/tool, and long-history states at consistent desktop and mobile viewports.
- [ ] Review images for overflow, contrast, semantics-visible labels, and stale data; fix and recapture failures.
- [ ] Review the complete diff against every design requirement and record verification in release notes.
- [ ] Commit the final artifacts with Lore trailers, push the branch, and open a PR whose description embeds the repository screenshots.

