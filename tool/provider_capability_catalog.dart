import 'dart:convert';
import 'dart:io';

const _defaultPath = 'docs/provider-capability-catalog.json';
const _maxAgeDays = 90;
const _requiredProviders = {
  'openai',
  'anthropic',
  'google',
  'azure',
  'cohere',
  'groq',
  'mistral',
  'ollama',
  'openai-compatible',
};

void main(List<String> args) {
  final command = args.isEmpty ? 'check' : args.first;
  if (command != 'check' && command != 'generate') {
    _fail('expected check or generate');
  }
  final path = args.length > 1 ? args[1] : _defaultPath;
  final file = File(path);
  if (!file.existsSync()) _fail('catalog not found: $path');
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map<String, dynamic>) _fail('catalog root must be an object');
  final records = decoded['records'];
  if (records is! List) _fail('catalog records must be an array');
  final generatedPath = decoded['generatedMarkdown'];
  if (generatedPath is! String || generatedPath.isEmpty) {
    _fail('catalog generatedMarkdown must name the generated output');
  }

  final errors = <String>[];
  final warnings = <String>[];
  final seen = <String>{};
  final providers = <String>{};
  final asOf = _asOf(args);
  if (decoded['schemaVersion'] != 1) errors.add('unsupported schemaVersion');
  for (var i = 0; i < records.length; i++) {
    final record = records[i];
    if (record is! Map<String, dynamic>) {
      errors.add('records[$i] must be an object');
      continue;
    }
    for (final key in [
      'provider',
      'modelId',
      'apiSurface',
      'feature',
      'scope',
      'lifecycle',
      'confidence',
      'source',
      'evidenceId',
      'evidenceRetrievedOn',
      'evidence',
    ]) {
      if (record[key] is! String || (record[key] as String).isEmpty) {
        errors.add('records[$i].$key must be a non-empty string');
      }
    }
    final provider = record['provider'];
    if (provider is String) providers.add(provider);
    final id =
        '${record['provider']}|${record['modelId']}|${record['apiSurface']}|${record['feature']}';
    if (!seen.add(id)) errors.add('duplicate record: $id');
    if (record['lifecycle'] is String &&
        !{'stable', 'preview', 'deprecated'}.contains(record['lifecycle'])) {
      errors.add('records[$i].lifecycle is invalid');
    }
    if (record['confidence'] is String &&
        !{'catalog', 'fixture', 'liveSmoke'}.contains(record['confidence'])) {
      errors.add('records[$i].confidence is invalid');
    }
    if (record['scope'] is String &&
        !{'model', 'protocol'}.contains(record['scope'])) {
      errors.add('records[$i].scope is invalid');
    }
    if (record['confidence'] == 'fixture') {
      final fixture = record['fixture'];
      if (fixture is! String || fixture.isEmpty) {
        errors.add('records[$i].fixture is required for fixture evidence');
      } else {
        final filePath = fixture.split(':').first;
        if (!File(filePath).existsSync()) {
          errors.add('records[$i].fixture path does not exist: $filePath');
        }
      }
    }
    final source = record['source'];
    if (source is String && Uri.tryParse(source)?.hasScheme != true) {
      errors.add('records[$i].source must be an absolute URI');
    }
    final date = record['evidenceRetrievedOn'];
    if (date is String) {
      final parsed = _isoDate(date);
      if (parsed == null) {
        errors.add('records[$i].evidenceRetrievedOn is not an ISO date');
      } else if (parsed.isAfter(asOf)) {
        errors.add('records[$i].evidenceRetrievedOn is in the future');
      } else if (asOf.difference(parsed).inDays > _maxAgeDays) {
        warnings.add('stale evidence: $id ($date)');
      }
    }
  }
  final missing = _requiredProviders.difference(providers);
  if (missing.isNotEmpty) {
    errors.add('missing providers: ${missing.join(', ')}');
  }
  if (errors.isNotEmpty) {
    for (final error in errors) {
      stderr.writeln('ERROR $error');
    }
    exitCode = 1;
  }
  for (final warning in warnings) {
    stderr.writeln('STALE $warning');
  }
  if (errors.isNotEmpty) return;
  if (warnings.isNotEmpty && args.contains('--fail-on-stale')) {
    _fail('catalog evidence exceeds the $_maxAgeDays-day freshness limit');
  }
  final generated = _render(records, path);
  if (command == 'generate') {
    stdout.write(generated);
  } else if (command == 'check') {
    final generatedFile = File(generatedPath);
    if (!generatedFile.existsSync()) {
      _fail('generated Markdown is missing: $generatedPath');
    }
    if (generatedFile.readAsStringSync() != generated) {
      _fail('generated Markdown is out of date: $generatedPath');
    }
    stdout.writeln(
      'catalog valid: ${records.length} records, ${providers.length} providers',
    );
  } else {
    _fail(
      'usage: dart run tool/provider_capability_catalog.dart [check|generate] [path] [--as-of=YYYY-MM-DD] [--fail-on-stale]',
    );
  }
}

DateTime? _isoDate(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return null;
  final date = DateTime.tryParse('${value}T00:00:00Z');
  if (date == null || date.toIso8601String().substring(0, 10) != value) {
    return null;
  }
  return date;
}

String _render(List<dynamic> records, String path) {
  final sorted = [...records]
    ..sort(
      (a, b) => '${a['provider']}|${a['modelId']}|${a['feature']}'.compareTo(
        '${b['provider']}|${b['modelId']}|${b['feature']}',
      ),
    );
  final out = StringBuffer()
    ..writeln('# Provider capability catalog')
    ..writeln()
    ..writeln('Generated from `$path`; model IDs remain advisory.')
    ..writeln();
  for (final record in sorted) {
    out.writeln(
      '- `${record['provider']}` `${record['modelId']}` '
      '${record['apiSurface']} (${record['scope']}): ${record['feature']} '
      '(${record['lifecycle']}, ${record['confidence']}) — '
      '[evidence](${record['source']})',
    );
  }
  return out.toString();
}

DateTime _asOf(List<String> args) {
  String? value;
  for (final arg in args) {
    if (arg.startsWith('--as-of=')) {
      value = arg.substring('--as-of='.length);
      break;
    }
  }
  return value == null
      ? DateTime.now().toUtc()
      : _isoDate(value) ?? _fail('as-of must be a valid YYYY-MM-DD date');
}

Never _fail(String message) {
  stderr.writeln('ERROR $message');
  exit(1);
}
