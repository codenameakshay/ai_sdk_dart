import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

late Directory temp;

void main() {
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('provider-catalog-test-');
  });

  tearDown(() => temp.delete(recursive: true));

  test('generates a missing view then validates it without drift', () async {
    final catalog = File('${temp.path}/catalog.json');
    final generated = File('${temp.path}/generated.md');
    final data =
        jsonDecode(
              File('docs/provider-capability-catalog.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    data['generatedMarkdown'] = generated.path;
    catalog.writeAsStringSync(jsonEncode(data));
    final result = await _command('generate', catalog.path);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    generated.writeAsStringSync(result.stdout as String);
    final check = await _command('check', catalog.path);
    expect(check.exitCode, 0, reason: check.stderr.toString());
  });

  test('rejects impossible calendar dates', () async {
    final result = await _run([_record(evidenceRetrievedOn: '2026-02-30')]);
    expect(result.stderr, contains('not an ISO date'));
  });

  test('malformed records produce diagnostics without a stack trace', () async {
    final catalog = File('${temp.path}/catalog.json')
      ..writeAsStringSync(
        jsonEncode({
          'schemaVersion': 1,
          'generatedMarkdown': '${temp.path}/generated.md',
          'records': [null],
        }),
      );
    final result = await _command('check', catalog.path);
    expect(result.stderr, contains('records[0] must be an object'));
    expect(result.stderr, isNot(contains('Unhandled exception')));
    expect(result.exitCode, isNonZero);
  });

  test('reports duplicate records', () async {
    final result = await _run([_record(), _record()]);
    expect(result.stderr, contains('duplicate record'));
    expect(result.exitCode, isNonZero);
  });

  test('reports missing fixture proof', () async {
    final result = await _run([
      _record(confidence: 'fixture', fixture: 'missing/test.dart:case'),
    ]);
    expect(result.stderr, contains('fixture path does not exist'));
    expect(result.exitCode, isNonZero);
  });

  test('reports future evidence dates', () async {
    final result = await _run([_record(evidenceRetrievedOn: '2026-09-24')]);
    expect(result.stderr, contains('in the future'));
    expect(result.exitCode, isNonZero);
  });

  test(
    'scheduled strict freshness fails an otherwise valid stale catalog',
    () async {
      final result = await Process.run(Platform.resolvedExecutable, [
        'tool/provider_capability_catalog.dart',
        'check',
        'docs/provider-capability-catalog.json',
        '--as-of=2027-01-01',
        '--fail-on-stale',
      ]);
      expect(result.stderr, contains('STALE'));
      expect(result.exitCode, isNonZero);
    },
  );

  test('reports stale evidence without network access', () async {
    final result = await _run([_record(evidenceRetrievedOn: '2026-01-01')]);
    expect(result.stderr, contains('STALE'));
  });
}

Map<String, dynamic> _record({
  String confidence = 'catalog',
  String evidenceRetrievedOn = '2026-09-23',
  String? fixture,
}) => {
  'provider': 'openai',
  'modelId': 'test-model',
  'apiSurface': 'responses',
  'scope': 'model',
  'feature': 'text-generation',
  'lifecycle': 'stable',
  'confidence': confidence,
  'fixture': ?fixture,
  'source': 'https://example.test/catalog',
  'evidenceId': 'test-evidence',
  'evidenceRetrievedOn': evidenceRetrievedOn,
  'evidence': 'test evidence',
};

Future<ProcessResult> _run(List<Map<String, dynamic>> records) async {
  final catalog = File('${temp.path}/catalog.json');
  await catalog.writeAsString(
    jsonEncode({
      'schemaVersion': 1,
      'generatedMarkdown': '${temp.path}/generated.md',
      'records': records,
    }),
  );
  return _command('check', catalog.path);
}

Future<ProcessResult> _command(String command, String path) =>
    Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/provider_capability_catalog.dart',
      command,
      path,
      '--as-of=2026-09-23',
    ], workingDirectory: Directory.current.path);
