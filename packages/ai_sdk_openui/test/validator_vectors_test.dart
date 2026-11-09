// Reads the conformance files with dart:io, which the web platforms lack.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:ai_sdk_openui/src/lang/parser.dart';
import 'package:test/test.dart';

import 'support/validator_library.dart';

/// A file in this package's conformance/ directory, found from the package
/// or the repo root (CI runs both).
File _conformance(String name) => [
  File('conformance/$name'),
  File('packages/ai_sdk_openui/conformance/$name'),
].firstWhere((f) => f.existsSync(), orElse: () => File('conformance/$name'));

/// A report as the vectors state it: everything but the free-text messages.
Map<String, Object?> _contract(ValidationReport report) {
  final json = report.toJson();
  return {
    ...json,
    'issues': [
      for (final issue in json['issues']! as List)
        {...issue as Map<String, Object?>}..remove('message'),
    ],
  };
}

void main() {
  final file =
      jsonDecode(_conformance('vectors.json').readAsStringSync())
          as Map<String, Object?>;
  final specText = _conformance(
    file['validatorSpec']! as String,
  ).readAsStringSync();
  final spec = jsonDecode(specText) as Map<String, Object?>;
  final schema = CompiledSchema.fromJsonSchema(
    spec['schema']! as Map<String, Object?>,
  );
  final vectors = [
    for (final v in (file['vectors']! as List).cast<Map<String, Object?>>())
      if (v.containsKey('expectReport')) v,
  ];

  test('the validator spec is the canonical spec of its library', () {
    expect(specText, canonicalJson(validatorLibrary.toSpec()));
  });

  test('every report code has a vector', () {
    final codes = {
      for (final v in vectors)
        for (final i in (v['expectReport']! as Map)['issues'] as List)
          (i as Map)['code'],
    };
    expect(
      codes,
      containsAll([
        'bound-only',
        'unknown-component',
        'unknown-function',
        'action-not-allowed',
        'unknown-bound-path',
        'too-many-nodes',
        'too-deep',
        'string-too-long',
        'missing-required',
        'null-required',
        'excess-args',
        'type-mismatch',
        'inline-reserved',
        'no-root',
        'incomplete',
        'unresolved',
        'orphaned',
      ]),
    );
    expect(
      vectors.where((v) => (v['expectReport']! as Map)['ok'] == true),
      isNotEmpty,
      reason: 'a clean pass',
    );
  });

  for (final v in vectors) {
    test('${v['id']} gives the stated report', () {
      final report = validateProgram(
        v['program']! as String,
        schema,
        rootName: spec['root'] as String?,
        policy: ValidationPolicy.fromJson(
          (v['policy'] as Map?)?.cast<String, Object?>() ?? const {},
        ),
        boundNames: {...?(v['bound'] as List?)?.cast<String>()},
        boundSchemas: {
          ...?(v['boundSchemas'] as Map?)?.cast<String, Map<String, Object?>>(),
        },
      );
      expect(_contract(report), v['expectReport']);
    });
  }
}
