@TestOn('linux')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';

import '../support/pump.dart';
import 'golden_programs.dart';

/// Whether this is the Flutter version pinned in `.fvmrc`. The goldens match
/// only that version: other versions draw some controls differently.
bool _onPinnedFlutter() {
  final root = Platform.environment['FLUTTER_ROOT'];
  final dir = (goldenFileComparator as LocalFileComparator).basedir;
  final fvmrc = File.fromUri(dir.resolve('../../../../.fvmrc'));
  if (root == null || !fvmrc.existsSync()) return true;
  Object? read(File f, String key) =>
      (jsonDecode(f.readAsStringSync()) as Map)[key];
  return read(fvmrc, 'flutter') ==
      read(File('$root/bin/cache/flutter.version.json'), 'frameworkVersion');
}

// Goldens are Linux-only: font rasterization differs per OS. Generate them on
// Linux with `fvm flutter test --update-goldens test/goldens`.
void main() {
  final skip = !_onPinnedFlutter();
  for (final brightness in Brightness.values) {
    group(brightness.name, () {
      for (final component in IuiComponent.values) {
        testWidgets('${component.typeName} ${brightness.name}', skip: skip, (
          tester,
        ) async {
          tester.view.physicalSize = const Size(420, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);

          Impure.now = () => DateTime.utc(2030, 5, 17, 12);
          Impure.useUtc();
          Impure.random = math.Random(7).nextDouble;
          addTearDown(Impure.reset);

          // Foundation debug variables must be restored inside the test body:
          // the framework checks them before tearDown callbacks run.
          final unsupportedOnLinux =
              component == IuiComponent.htmlView ||
              component == IuiComponent.youTube;
          if (unsupportedOnLinux) {
            debugDefaultTargetPlatformOverride = TargetPlatform.linux;
          }
          try {
            final program = goldenPrograms[component.typeName]!;
            await pumpProgram(
              tester,
              program,
              brightness: brightness,
              services: const OpenUiServices(),
            );
            if (component == IuiComponent.celebration) {
              await tester.pump(const Duration(seconds: 2));
            } else {
              await tester.pumpAndSettle(
                const Duration(milliseconds: 100),
                EnginePhase.sendSemanticsUpdate,
                const Duration(seconds: 10),
              );
            }
            expect(tester.takeException(), isNull);

            await expectLater(
              find.byType(OpenUiView),
              matchesGoldenFile('${brightness.name}/${component.typeName}.png'),
            );
          } finally {
            if (unsupportedOnLinux) debugDefaultTargetPlatformOverride = null;
          }
        });
      }
    });
  }
}
