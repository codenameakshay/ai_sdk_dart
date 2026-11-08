// Usage: dart run tool/check_components.dart [ComponentName ...]
// Compares each named component's prompt signature and its JSON Schema
// `$def` with test/fixtures/spec.json. With no names, checks every component
// whose spec function is implemented. Exits 1 on any mismatch.
import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_openui/intelligent_ui.dart';
import 'package:ai_sdk_openui/src/spec/schema.dart';

void main(List<String> names) {
  final spec =
      jsonDecode(File('test/fixtures/spec.json').readAsStringSync())
          as Map<String, Object?>;
  final defs = (spec['schema'] as Map)[r'$defs'] as Map;
  final components = spec['components'] as Map;
  var failed = 0, checked = 0;
  for (final c in IuiComponent.values) {
    if (names.isNotEmpty && !names.contains(c.typeName)) continue;
    final Map<String, Schema> props;
    final String description;
    try {
      props = c.props;
      description = c.description;
    } on UnimplementedError {
      if (names.isNotEmpty) {
        stdout.writeln('TODO ${c.typeName}: not implemented');
        failed++;
      }
      continue;
    }
    checked++;
    final emitter = JsonSchemaEmitter(
      (name) => (defs[name] as Map).cast<String, Object?>(),
    );
    final def = emitter.emitObject(props);
    if (description.isNotEmpty) def['description'] = description;
    final want = components[c.typeName] as Map;
    final problems = [
      if (signature(c.typeName, props) != want['signature'])
        'signature\n    got:  ${signature(c.typeName, props)}\n    want: ${want['signature']}',
      if (description != want['description'])
        'description\n    got:  $description\n    want: ${want['description']}',
      if (jsonEncode(def) != jsonEncode(defs[c.typeName]))
        'json schema\n    got:  ${jsonEncode(def)}\n    want: ${jsonEncode(defs[c.typeName])}',
    ];
    if (problems.isEmpty) {
      stdout.writeln('ok   ${c.typeName}');
    } else {
      failed++;
      stdout.writeln('FAIL ${c.typeName}: ${problems.join('\n  ')}');
    }
  }
  stdout.writeln('$checked checked, $failed failing');
  exit(failed == 0 ? 0 : 1);
}
