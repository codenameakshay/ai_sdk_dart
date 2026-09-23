# ──────────────────────────────────────────────────────────────────────────────
# AI SDK Dart — Makefile
#
# Reads API keys from the shell environment and forwards them as --dart-define
# flags so they work on every Flutter target (Android, iOS, web, desktop).
#
# Usage:
#   export OPENAI_API_KEY=sk-...
#   export ANTHROPIC_API_KEY=sk-ant-...
#   export GOOGLE_API_KEY=AIza...
#
#   make get               # install all workspace dependencies
#   make run               # run the Flutter chat example on the default device
#   make run-web           # run on Chrome
#   make run-advanced      # run the advanced app on the default device
#   make run-advanced-web  # run the advanced app on Chrome
#   make run-basic         # run the Dart CLI example
#   make test              # run all package tests
#   make analyze           # dart analyze across all packages
#   make format            # dart format across all packages
#   make dry-run           # pub publish --dry-run for all packages
#   make benchmark         # run the structured-stream benchmark
# ──────────────────────────────────────────────────────────────────────────────

FLUTTER   ?= fvm flutter
DART      ?= fvm dart

FLUTTER_APP  := examples/flutter_chat
ADVANCED_APP := examples/advanced_app
DART_APP     := examples/basic

# Pure-Dart packages (test/analyze order). Publish order is separate below
# since publish order matters (dependencies before dependents).
DART_PKGS    := ai_sdk_telemetry ai_sdk_remote ai_sdk_realtime ai_sdk_conversation ai_sdk_json_schema ai_sdk_dart ai_sdk_provider ai_sdk_openai_compatible ai_sdk_openai \
                ai_sdk_anthropic ai_sdk_google ai_sdk_azure ai_sdk_cohere ai_sdk_groq \
                ai_sdk_mistral ai_sdk_ollama ai_sdk_mcp
FLUTTER_PKGS := ai_sdk_flutter_ui
PUBLISH_PKGS := ai_sdk_provider ai_sdk_openai_compatible ai_sdk_openai ai_sdk_anthropic \
                ai_sdk_google ai_sdk_azure ai_sdk_cohere ai_sdk_groq ai_sdk_mistral \
                ai_sdk_ollama ai_sdk_dart ai_sdk_json_schema ai_sdk_conversation ai_sdk_remote ai_sdk_mcp ai_sdk_telemetry

# Build --dart-define flags from env vars (only included when the var is set)
DART_DEFINES :=
ifdef OPENAI_API_KEY
  DART_DEFINES += --dart-define=OPENAI_API_KEY=$(OPENAI_API_KEY)
endif
ifdef ANTHROPIC_API_KEY
  DART_DEFINES += --dart-define=ANTHROPIC_API_KEY=$(ANTHROPIC_API_KEY)
endif
ifdef GOOGLE_API_KEY
  DART_DEFINES += --dart-define=GOOGLE_API_KEY=$(GOOGLE_API_KEY)
endif

# `dart run` uses --define (compile-time consts via String.fromEnvironment),
# whereas `flutter run` uses --dart-define. The example providers read keys
# through String.fromEnvironment, so a plain shell export is not enough.
DART_RUN_DEFINES :=
ifdef OPENAI_API_KEY
  DART_RUN_DEFINES += --define=OPENAI_API_KEY=$(OPENAI_API_KEY)
endif
ifdef ANTHROPIC_API_KEY
  DART_RUN_DEFINES += --define=ANTHROPIC_API_KEY=$(ANTHROPIC_API_KEY)
endif
ifdef GOOGLE_API_KEY
  DART_RUN_DEFINES += --define=GOOGLE_API_KEY=$(GOOGLE_API_KEY)
endif

.PHONY: all get run run-web run-advanced run-advanced-web run-basic run-mcp \
        test analyze format format-check dry-run publish help \
        coverage coverage-check benchmark catalog-check test-mcp-reference

all: help

# ── Dependencies ──────────────────────────────────────────────────────────────

## Install all workspace dependencies
get:
	$(FLUTTER) pub get

# ── Run ───────────────────────────────────────────────────────────────────────

## Run the Flutter chat example on the default connected device
run:
	cd $(FLUTTER_APP) && $(FLUTTER) run $(DART_DEFINES)

## Run the Flutter chat example on Chrome (web)
run-web:
	cd $(FLUTTER_APP) && $(FLUTTER) run $(DART_DEFINES) -d chrome

## Run the advanced Flutter app on the default connected device
run-advanced:
	cd $(ADVANCED_APP) && $(FLUTTER) run $(DART_DEFINES)

## Run the advanced Flutter app on Chrome (web)
run-advanced-web:
	cd $(ADVANCED_APP) && $(FLUTTER) run $(DART_DEFINES) -d chrome

## Run the Dart CLI example (passes OPENAI_API_KEY as a compile-time --define)
run-basic:
	@if [ -z "$(OPENAI_API_KEY)" ]; then \
		echo "Error: OPENAI_API_KEY is not set."; \
		echo "  export OPENAI_API_KEY=sk-..."; \
		exit 1; \
	fi
	cd $(DART_APP) && $(DART) run $(DART_RUN_DEFINES) lib/main.dart

## Run the MCP (Model Context Protocol) CLI demo. Works without a key (the
## tool-discovery + direct-call steps); set OPENAI_API_KEY to also run the
## generateText-with-MCP-tools step.
run-mcp:
	cd $(DART_APP) && $(DART) run $(DART_RUN_DEFINES) lib/mcp_demo.dart

# ── Quality ───────────────────────────────────────────────────────────────────

## Run tests across all packages
test:
	$(DART) test tool/provider_capability_catalog_test.dart
	$(foreach p,$(DART_PKGS),$(DART) test packages/$(p)/test/ &&) true
	$(foreach p,$(FLUTTER_PKGS),$(FLUTTER) test packages/$(p)/ &&) true
	$(FLUTTER) test $(FLUTTER_APP)/
	$(FLUTTER) test $(ADVANCED_APP)/

## Run dart analyze across all packages
analyze:
	$(DART) analyze tool/provider_capability_catalog.dart tool/provider_capability_catalog_test.dart
	$(DART) analyze $(DART_APP)/
	$(foreach p,$(DART_PKGS),$(DART) analyze packages/$(p)/ &&) true
	$(foreach p,$(FLUTTER_PKGS),$(FLUTTER) analyze packages/$(p)/ &&) true
	$(FLUTTER) analyze $(FLUTTER_APP)/
	$(FLUTTER) analyze $(ADVANCED_APP)/

## Run the structured-stream benchmark and print JSON results
benchmark:
	$(DART) run packages/ai_sdk_dart/benchmark/structured_stream_benchmark.dart --json

## Validate the advisory model catalog and generated documentation offline
catalog-check:
	$(DART) run tool/provider_capability_catalog.dart check docs/provider-capability-catalog.json

## Verify legacy MCP interoperability against the pinned TypeScript SDK
test-mcp-reference:
	npm ci --ignore-scripts --prefix examples/mcp_reference/js
	AI_SDK_MCP_REFERENCE=1 $(DART) test packages/ai_sdk_mcp/test/typescript_reference_test.dart

## Run tests with coverage across all packages and print a summary
coverage:
	$(DART) pub global activate coverage >/dev/null
	DART="$(DART)" FLUTTER="$(FLUTTER)" tool/coverage.sh

## Run coverage and fail if total line coverage is below the 99% gate
coverage-check:
	$(DART) pub global activate coverage >/dev/null
	DART="$(DART)" FLUTTER="$(FLUTTER)" tool/coverage.sh 99

## Format all Dart source files
format:
	$(DART) format packages/ examples/

## Verify formatting without writing changes
format-check:
	$(DART) format --output=none --set-exit-if-changed packages/ examples/

# ── Publish ───────────────────────────────────────────────────────────────────

## Dry-run publish for all packages (checks pub.dev readiness)
dry-run:
	$(foreach p,$(PUBLISH_PKGS),$(DART) pub publish --dry-run -C packages/$(p) &&) true
	$(foreach p,$(FLUTTER_PKGS),$(FLUTTER) pub publish --dry-run -C packages/$(p) &&) true

## Publish all packages to pub.dev (run dry-run first to verify)
publish:
	$(foreach p,$(PUBLISH_PKGS),$(DART) pub publish -C packages/$(p) &&) true
	$(foreach p,$(FLUTTER_PKGS),$(FLUTTER) pub publish -C packages/$(p) &&) true

# ── Help ──────────────────────────────────────────────────────────────────────

help:
	@echo ""
	@echo "AI SDK Dart — available targets:"
	@echo ""
	@echo "  make get               Install all workspace dependencies"
	@echo "  make run               Run Flutter chat app on default device"
	@echo "  make run-web           Run Flutter chat app on Chrome"
	@echo "  make run-advanced      Run advanced app on default device"
	@echo "  make run-advanced-web  Run advanced app on Chrome"
	@echo "  make run-basic         Run Dart CLI example"
	@echo "  make run-mcp           Run the MCP CLI demo (works without a key)"
	@echo "  make test              Run all package tests"
	@echo "  make analyze           Run dart analyze across all packages"
	@echo "  make format            Format all Dart source files"
	@echo "  make format-check      Verify Dart formatting without writing changes"
	@echo "  make dry-run           pub publish --dry-run for all packages"
	@echo "  make publish           pub publish for all packages (run dry-run first)"
	@echo "  make benchmark         Run the structured-stream benchmark"
	@echo ""
	@echo "  Required env vars (set before running):"
	@echo "    OPENAI_API_KEY       OpenAI API key"
	@echo "    ANTHROPIC_API_KEY    Anthropic API key"
	@echo "    GOOGLE_API_KEY       Google Generative AI API key"
	@echo ""
