#!/bin/bash
# SessionStart hook: install the Flutter toolchain via FVM so analyze/test/build
# work in Claude Code on the web. Synchronous and idempotent.
#
# Why this is non-trivial in the remote env:
#   The environment routes github.com git traffic through a *scoped* git mirror
#   that only carries the in-scope repo, so `git clone flutter/flutter` returns
#   403. The main HTTPS egress proxy DOES allow github.com/flutter/flutter, so we
#   run FVM's git operations with GIT_CONFIG_GLOBAL pointed away from the mirror
#   rewrite. CA trust still flows through GIT_SSL_CAINFO / the proxy env vars.
set -euo pipefail

# Only run in the remote (Claude Code on the web) environment.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
FVM_VERSION="4.1.2"
FVM_DIR="$HOME/fvm"
FVM_BIN_DIR="$FVM_DIR/fvm"          # tarball extracts a top-level fvm/ dir (binary + src/)
FVM_BIN="$FVM_BIN_DIR/fvm"

log() { echo "[flutter-setup] $*"; }

# --- 1. Install the FVM binary (skip if already present) -----------------------
if [ ! -x "$FVM_BIN" ]; then
  log "Installing FVM $FVM_VERSION ..."
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) fvm_arch="x64" ;;
    aarch64|arm64) fvm_arch="arm64" ;;
    *) log "Unsupported arch: $arch"; exit 1 ;;
  esac
  tarball="fvm-${FVM_VERSION}-linux-${fvm_arch}.tar.gz"
  url="https://github.com/leoafarias/fvm/releases/download/${FVM_VERSION}/${tarball}"
  mkdir -p "$FVM_DIR"
  tmp="$(mktemp)"
  # Retry the download a few times in case of transient proxy hiccups.
  for attempt in 1 2 3 4; do
    if curl -fsSL -o "$tmp" "$url"; then break; fi
    log "FVM download attempt $attempt failed; retrying ..."
    sleep $((attempt * 2))
  done
  rm -rf "$FVM_BIN_DIR"
  tar xzf "$tmp" -C "$FVM_DIR"
  rm -f "$tmp"
  log "FVM installed at $FVM_BIN"
else
  log "FVM already present at $FVM_BIN"
fi

export PATH="$FVM_BIN_DIR:$PATH"

# --- 2. Install the pinned Flutter SDK (reads .fvmrc) --------------------------
# GIT_CONFIG_GLOBAL=/dev/null bypasses the scoped git-mirror rewrite so FVM's
# clone of flutter/flutter goes through the main HTTPS egress proxy instead.
cd "$PROJECT_DIR"
log "Installing Flutter SDK pinned in .fvmrc ..."
GIT_CONFIG_GLOBAL=/dev/null "$FVM_BIN" install --setup

# Silence Flutter/Dart first-run analytics prompts (non-interactive).
"$FVM_BIN" flutter --disable-analytics >/dev/null 2>&1 || true

# --- 3. Resolve workspace dependencies ----------------------------------------
# Use `flutter pub get` (not `dart`) because ai_sdk_flutter_ui depends on the
# Flutter SDK; a single resolve covers the whole Dart pub workspace.
log "Resolving workspace dependencies ..."
"$FVM_BIN" flutter pub get

# --- 4. Expose the toolchain to the session -----------------------------------
# Put fvm and the FVM-managed flutter/dart on PATH for the rest of the session.
SDK_BIN="$PROJECT_DIR/.fvm/flutter_sdk/bin"
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  {
    echo "export PATH=\"$FVM_BIN_DIR:$SDK_BIN:$SDK_BIN/cache/dart-sdk/bin:\$HOME/.pub-cache/bin:\$PATH\""
  } >> "$CLAUDE_ENV_FILE"
fi

log "Flutter environment ready:"
"$FVM_BIN" flutter --version 2>/dev/null | grep -E "^Flutter|Dart" || true
