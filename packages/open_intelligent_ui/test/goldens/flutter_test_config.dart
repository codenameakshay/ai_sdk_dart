import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the bundled Inter font under the name the umbrella package uses, and
/// allows a 0.5% pixel difference so goldens survive small rasterizer changes.
///
/// Paths resolve from this directory, because `make test` runs `flutter test`
/// from the repo root and a package run starts in the package.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dir = (goldenFileComparator as LocalFileComparator).basedir;
  Future<ByteData> font(String name) => File.fromUri(
    dir.resolve('../../assets/fonts/$name'),
  ).readAsBytes().then(ByteData.sublistView);
  await (FontLoader('packages/open_intelligent_ui/Inter')
        ..addFont(font('InterVariable.ttf'))
        ..addFont(font('InterVariable-Italic.ttf')))
      .load();
  goldenFileComparator = _TolerantComparator(
    dir.resolve('components_golden_test.dart'),
  );
  await testMain();
}

final class _TolerantComparator extends LocalFileComparator {
  _TolerantComparator(super.testFile);

  @override
  Future<bool> compare(Uint8List image, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      image,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= 0.005) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}
