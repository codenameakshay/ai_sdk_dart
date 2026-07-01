#!/usr/bin/env bash
#
# Runs tests with coverage across every package, merges the per-package LCOV
# into coverage/lcov.info, prints a per-package + total line-coverage summary,
# and (optionally) enforces a minimum total threshold.
#
# Usage:
#   tool/coverage.sh            # measure + print summary (no gate)
#   tool/coverage.sh 100        # also fail if total line coverage < 100%
#
# `// coverage:ignore-line` / `ignore-start` / `ignore-end` comments are
# honored via format_coverage --check-ignore. Set DART/FLUTTER to override the
# executables (e.g. `DART="fvm dart" FLUTTER="fvm flutter" tool/coverage.sh`).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DART="${DART:-dart}"
FLUTTER="${FLUTTER:-flutter}"
THRESHOLD="${1:-0}"
PKG_CONFIG="$ROOT/.dart_tool/package_config.json"
MERGED="$ROOT/coverage/lcov.info"

mkdir -p "$ROOT/coverage"
: > "$MERGED"

# Pure-Dart packages (run with `dart test --coverage`).
DART_PKGS="ai_sdk_dart ai_sdk_openai ai_sdk_openai_compatible ai_sdk_anthropic ai_sdk_google ai_sdk_azure ai_sdk_cohere ai_sdk_groq ai_sdk_mistral ai_sdk_ollama ai_sdk_mcp"

# Flutter packages (run with `flutter test --coverage`, which emits lcov directly).
FLUTTER_PKGS="ai_sdk_flutter_ui"

summarize() { # $1 = lcov file, $2 = label
  awk -F: -v label="$2" '
    /^LF:/{lf+=$2} /^LH:/{lh+=$2}
    END{ if (lf>0) printf "  %-26s %6.2f%%  (%d/%d)\n", label, 100*lh/lf, lh, lf;
         else printf "  %-26s   no data\n", label }' "$1"
}

echo "== Coverage =="
for p in $DART_PKGS; do
  [ -d "$ROOT/packages/$p/test" ] || continue
  cov="$ROOT/packages/$p/coverage"
  rm -rf "$cov"
  # Run from the repo root so tests that read repo-relative fixtures pass.
  $DART test --coverage="$cov" "packages/$p/test/" >/dev/null
  $DART pub global run coverage:format_coverage \
    --lcov --check-ignore --in="$cov" --out="$cov/lcov.info" \
    --report-on="packages/$p/lib" --packages="$PKG_CONFIG" >/dev/null
  summarize "$cov/lcov.info" "$p"
  cat "$cov/lcov.info" >> "$MERGED"
done

for p in $FLUTTER_PKGS; do
  [ -d "$ROOT/packages/$p/test" ] || continue
  ( cd "$ROOT/packages/$p"; $FLUTTER test --coverage >/dev/null )
  summarize "$ROOT/packages/$p/coverage/lcov.info" "$p"
  cat "$ROOT/packages/$p/coverage/lcov.info" >> "$MERGED"
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
