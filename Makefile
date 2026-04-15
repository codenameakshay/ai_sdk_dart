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
# ──────────────────────────────────────────────────────────────────────────────

FLUTTER   := fvm flutter
DART      := fvm dart

FLUTTER_APP  := examples/flutter_chat
ADVANCED_APP := examples/advanced_app
DART_APP     := examples/basic

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

.PHONY: all get run run-web run-advanced run-advanced-web run-basic \
        test analyze format dry-run clean help

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

## Run the Dart CLI example (uses OPENAI_API_KEY from env directly)
run-basic:
	@if [ -z "$(OPENAI_API_KEY)" ]; then \
		echo "Error: OPENAI_API_KEY is not set."; \
		echo "  export OPENAI_API_KEY=sk-..."; \
		exit 1; \
	fi
	$(DART) run -C $(DART_APP) lib/main.dart

# ── Quality ───────────────────────────────────────────────────────────────────

## Run tests across all packages
test:
	$(DART) test packages/ai_sdk_dart/test/
	$(DART) test packages/ai_sdk_provider/test/
	$(DART) test packages/ai_sdk_openai/test/
	$(DART) test packages/ai_sdk_anthropic/test/
	$(DART) test packages/ai_sdk_google/test/
	$(DART) test packages/ai_sdk_azure/test/
	$(DART) test packages/ai_sdk_cohere/test/
	$(DART) test packages/ai_sdk_groq/test/
	$(DART) test packages/ai_sdk_mistral/test/
	$(DART) test packages/ai_sdk_ollama/test/
	$(DART) test packages/ai_sdk_mcp/test/
	$(FLUTTER) test $(FLUTTER_APP)/
	$(FLUTTER) test $(ADVANCED_APP)/

## Run dart analyze across all packages
analyze:
	$(DART) analyze packages/ai_sdk_dart/
	$(DART) analyze packages/ai_sdk_provider/
	$(DART) analyze packages/ai_sdk_openai/
	$(DART) analyze packages/ai_sdk_anthropic/
	$(DART) analyze packages/ai_sdk_google/
	$(DART) analyze packages/ai_sdk_azure/
	$(DART) analyze packages/ai_sdk_cohere/
	$(DART) analyze packages/ai_sdk_groq/
	$(DART) analyze packages/ai_sdk_mistral/
	$(DART) analyze packages/ai_sdk_ollama/
	$(DART) analyze packages/ai_sdk_mcp/
	$(FLUTTER) analyze packages/ai_sdk_flutter_ui/
	$(FLUTTER) analyze $(FLUTTER_APP)/
	$(FLUTTER) analyze $(ADVANCED_APP)/

## Format all Dart source files
format:
	$(DART) format packages/ examples/

# ── Publish dry-runs ──────────────────────────────────────────────────────────

## Dry-run publish for all packages (checks pub.dev readiness)
dry-run:
	$(DART) pub publish --dry-run -C packages/ai_sdk_provider
	$(DART) pub publish --dry-run -C packages/ai_sdk_dart
	$(DART) pub publish --dry-run -C packages/ai_sdk_openai
	$(DART) pub publish --dry-run -C packages/ai_sdk_anthropic
	$(DART) pub publish --dry-run -C packages/ai_sdk_google
	$(DART) pub publish --dry-run -C packages/ai_sdk_azure
	$(DART) pub publish --dry-run -C packages/ai_sdk_cohere
	$(DART) pub publish --dry-run -C packages/ai_sdk_groq
	$(DART) pub publish --dry-run -C packages/ai_sdk_mistral
	$(DART) pub publish --dry-run -C packages/ai_sdk_ollama
	$(DART) pub publish --dry-run -C packages/ai_sdk_mcp
	$(FLUTTER) pub publish --dry-run -C packages/ai_sdk_flutter_ui

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
	@echo "  make test              Run all package tests"
	@echo "  make analyze           Run dart analyze across all packages"
	@echo "  make format            Format all Dart source files"
	@echo "  make dry-run           pub publish --dry-run for all packages"
	@echo ""
	@echo "  Required env vars (set before running):"
	@echo "    OPENAI_API_KEY       OpenAI API key"
	@echo "    ANTHROPIC_API_KEY    Anthropic API key"
	@echo "    GOOGLE_API_KEY       Google Generative AI API key"
	@echo ""
