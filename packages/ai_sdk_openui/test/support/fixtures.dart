import 'dart:io';

/// A file in test/fixtures, found from the package or the repo root.
File fixtureFile(String name) => [
  File('test/fixtures/$name'),
  File('packages/ai_sdk_openui/test/fixtures/$name'),
].firstWhere((f) => f.existsSync(), orElse: () => File('test/fixtures/$name'));

String fixture(String name) => fixtureFile(name).readAsStringSync();
