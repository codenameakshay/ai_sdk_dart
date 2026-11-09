#!/usr/bin/env bash
#
# Creates a scratch Flutter app that depends on ai_sdk_openui and
# open_intelligent_ui_core from git at one commit, with no
# dependency_overrides, then runs `flutter pub get` and `flutter analyze`.
#
# Usage: tool/git_consumer_check.sh <repo-url> <commit-sha>
# Example: tool/git_consumer_check.sh "file://$PWD" "$(git rev-parse HEAD)"
set -euo pipefail

URL="$1"
REF="$2"
FLUTTER="${FLUTTER:-flutter}"
APP="$(mktemp -d)/git_consumer"

$FLUTTER create --no-pub --project-name git_consumer --platforms android,ios "$APP" >/dev/null
cd "$APP"
# Keep the lints the template's analysis_options.yaml includes.
LINTS="$(grep -m1 'flutter_lints:' pubspec.yaml)"
cat > pubspec.yaml <<EOF
name: git_consumer
publish_to: none
environment:
  sdk: ^3.11.1
dependencies:
  flutter: {sdk: flutter}
  ai_sdk_openui:
    git: {url: $URL, ref: $REF, path: packages/ai_sdk_openui}
  open_intelligent_ui_core:
    git: {url: $URL, ref: $REF, path: packages/open_intelligent_ui_core}
dev_dependencies:
  flutter_test: {sdk: flutter}
$LINTS
EOF
cat > lib/main.dart <<'EOF'
import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:flutter/widgets.dart';
import 'package:open_intelligent_ui_core/open_intelligent_ui_core.dart'
    show OpenUiView, intelligentUiFor, openUiCoreBuilders;

void main() => runApp(
  Directionality(
    textDirection: TextDirection.ltr,
    child: OpenUiView(
      session: OpenUiSession(intelligentUiFor(openUiCoreBuilders))
        ..update('root = Text("hi")', streaming: false),
      builders: openUiCoreBuilders,
    ),
  ),
);
EOF
rm -rf test
$FLUTTER pub get
$FLUTTER analyze --fatal-infos
