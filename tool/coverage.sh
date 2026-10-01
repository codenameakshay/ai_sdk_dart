#!/usr/bin/env bash
#
# Runs every published package's tests once with coverage, merges the LCOV
# into coverage/lcov.info, prints a per-package + total line-coverage summary,
# and (optionally) enforces a minimum total threshold.
#
# Usage:
#   tool/coverage.sh            # measure + print summary (no gate)
#   tool/coverage.sh 99         # also fail if total line coverage < 99%
#
# `// coverage:ignore-line` / `ignore-start` / `ignore-end` comments are
# honored. Set DART/FLUTTER to override the executables
# (e.g. `DART="fvm dart" FLUTTER="fvm flutter" tool/coverage.sh`).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DART="${DART:-dart}"
FLUTTER="${FLUTTER:-flutter}"
THRESHOLD="${1:-0}"
PKG_CONFIG="$ROOT/.dart_tool/package_config.json"
MERGED="$ROOT/coverage/lcov.info"

# Pure-Dart packages (run with `dart test --coverage-path`).
DART_PKGS="ai_sdk_dart ai_sdk_provider ai_sdk_openai ai_sdk_openai_compatible ai_sdk_anthropic ai_sdk_google ai_sdk_azure ai_sdk_cohere ai_sdk_groq ai_sdk_mistral ai_sdk_ollama ai_sdk_mcp"

# Flutter packages (run with `flutter test --coverage`).
FLUTTER_PKGS="ai_sdk_flutter_ui"

summarize() { # $1 = label, LCOV on stdin
  awk -F: -v label="$1" '
    /^LF:/{lf+=$2} /^LH:/{lh+=$2}
    END{ if (lf>0) printf "  %-26s %6.2f%%  (%d/%d)\n", label, 100*lh/lf, lh, lf;
         else { printf "  %-26s   no data\n", label; exit 1 } }'
}

mkdir -p "$ROOT/coverage"
rm -f "$MERGED"
for p in $FLUTTER_PKGS; do
  rm -f "$ROOT/packages/$p/coverage/lcov.info"
done
if [ ! -f "$PKG_CONFIG" ]; then
  echo "Missing $PKG_CONFIG. Run '$FLUTTER pub get' first."
  exit 1
fi

# One `dart test` process for all pure-Dart packages: a process per package
# spent most of its time on start-up. It runs from the repo root so tests that
# read repo-relative fixtures pass.
dart_test_dirs=""
for p in $DART_PKGS; do
  dart_test_dirs="$dart_test_dirs packages/$p/test/"
done
# shellcheck disable=SC2086
$DART test --reporter=failures-only --coverage-path="$MERGED" \
  --coverage-package="^(${DART_PKGS// /|})\$" $dart_test_dirs
if [ ! -f "$MERGED" ]; then
  echo "Missing Dart coverage output at $MERGED."
  exit 1
fi

for p in $FLUTTER_PKGS; do
  ( cd "$ROOT/packages/$p"; $FLUTTER test --no-pub --reporter=failures-only --coverage )
done

echo "== Coverage =="
for p in $DART_PKGS; do
  awk -v dir="/packages/$p/lib/" '/^SF:/{keep=index($0, dir)} keep' "$MERGED" | summarize "$p"
done
for p in $FLUTTER_PKGS; do
  flutter_lcov="$ROOT/packages/$p/coverage/lcov.info"
  if [ ! -f "$flutter_lcov" ]; then
    echo "Missing Flutter coverage output at $flutter_lcov."
    exit 1
  fi
  summarize "$p" < "$flutter_lcov"
  cat "$flutter_lcov" >> "$MERGED"
done

echo "-------------------------------------------------"
TOTAL_PCT="$(awk -F: '/^LF:/{lf+=$2} /^LH:/{lh+=$2} END{ if(lf>0) printf "%.2f", 100*lh/lf; else print "0" }' "$MERGED")"
TOTAL_RAW="$(awk -F: '/^LF:/{lf+=$2} /^LH:/{lh+=$2} END{ printf "%d/%d", lh, lf }' "$MERGED")"
printf "  %-26s %6s%%  (%s)\n" "TOTAL" "$TOTAL_PCT" "$TOTAL_RAW"

if [ "$THRESHOLD" != "0" ]; then
  if awk "BEGIN{exit !($TOTAL_PCT < $THRESHOLD)}"; then
    echo "FAIL: total coverage ${TOTAL_PCT}% is below threshold ${THRESHOLD}%."
    exit 1
  fi
  echo "OK: total coverage ${TOTAL_PCT}% meets threshold ${THRESHOLD}%."
fi
