import 'dart:convert';

import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:ai_sdk_openui/intelligent_ui.dart';
import 'package:ai_sdk_openui/src/cli/openui_cli.dart';
import 'package:test/test.dart';

final class _Out implements ComponentSpec {
  const _Out();
  @override
  String get typeName => 'Out';
  @override
  String get description => '';
  @override
  Map<String, Schema> get props => {
    'value': S.any(),
    'amount': S.any().boundOnly().optional(),
    'action': actionSchema.optional(),
  };
}

final class _Video implements ComponentSpec {
  const _Video();
  @override
  String get typeName => 'Video';
  @override
  String get description => 'A host video player.';
  @override
  Map<String, Schema> get props => {'src': S.string()};
}

final _pay = ActionSpec(
  'Pay',
  description: 'Pays an order',
  params: {'orderId': S.string()},
);

final _hostLibrary = OpenUiLibrary(
  root: const _Out(),
  components: const [_Out()],
  actions: [_pay],
);

final _extended = intelligentUi.extend(
  LibraryExtension(
    addComponents: [ComponentAddition(const _Video())],
    addActions: [_pay],
  ),
);

final files = <String, String>{
  'spec.json': intelligentUi.toSpecJson(),
  'ok.oui': 'root = Col([Title("Hi")])',
  'big.oui': 'root = Col([Title("a"), Title("b")])',
  'pay.oui': 'root = Col([Button("Pay", @Pay("o-1"))])',
  'host.oui': 'root = Col([Video("clip.mp4")])',
  'bound.oui': r'root = Out(1, $order.total)',
  'host.json': _extended.toSpecJson(),
  'hostlib.json': _hostLibrary.toSpecJson(),
  'schema.json': jsonEncode(intelligentUi.toJsonSchema()),
  'broken.json': 'not json',
};

Future<(int, String, String)> cli(List<String> args) async {
  final out = StringBuffer(), err = StringBuffer();
  final code = await runOpenUiCli(
    args,
    read: (p) async => files[p] ?? (throw StateError('missing $p')),
    out: out.write,
    err: err.writeln,
  );
  return (code, '$out', '$err');
}

void main() {
  test('a valid program exits 0 with the report', () async {
    final (code, out, _) = await cli(['validate', 'spec.json', 'ok.oui']);
    expect(code, 0);
    expect(
      out,
      intelligentUi.validate('root = Col([Title("Hi")])').toJsonString(),
    );
  });

  test('policy flags fail a program', () async {
    final (code, out, _) = await cli([
      'validate',
      'spec.json',
      'big.oui',
      '--max-nodes=2',
    ]);
    expect(code, 1);
    expect(jsonDecode(out)['issues'][0]['code'], 'too-many-nodes');
  });

  test('a host-extended spec round-trips', () async {
    final (code, out, _) = await cli([
      'validate',
      'host.json',
      'pay.oui',
      '--allow-actions=ToAssistant',
    ]);
    expect(code, 1);
    final issue = jsonDecode(out)['issues'][0] as Map<String, Object?>;
    expect(issue['code'], 'action-not-allowed');
    expect(issue['message'], 'Action @Pay is not allowed');

    final (allowed, _, _) = await cli(['validate', 'host.json', 'pay.oui']);
    expect(allowed, 0);
  });

  test('a host component from the extended spec is known', () async {
    final (known, _, _) = await cli(['validate', 'host.json', 'host.oui']);
    expect(known, 0);

    final (base, out, _) = await cli(['validate', 'spec.json', 'host.oui']);
    expect(base, 0);
    expect(jsonDecode(out)['issues'][0]['code'], 'unknown-component');
  });

  test('bound names come from --bound', () async {
    final (code, _, _) = await cli([
      'validate',
      'hostlib.json',
      'bound.oui',
      r'--bound=$order',
    ]);
    expect(code, 0);

    final (missing, out, _) = await cli([
      'validate',
      'hostlib.json',
      'bound.oui',
    ]);
    expect(missing, 1);
    final codes = [
      for (final i in jsonDecode(out)['issues'] as List) i['code'],
    ];
    expect(codes, contains('bound-only'));
  });

  test('bad input and usage are reported', () async {
    final (usage, _, err) = await cli(['validate', 'spec.json']);
    expect(usage, 64);
    expect(err, contains('Usage: openui validate'));

    final (missing, _, missingErr) = await cli([
      'validate',
      'nope.json',
      'ok.oui',
    ]);
    expect(missing, 2);
    expect(missingErr, contains('openui: Bad state: missing nope.json'));

    final (badNumber, _, _) = await cli([
      'validate',
      'spec.json',
      'ok.oui',
      '--max-nodes=x',
    ]);
    expect(badNumber, 64);

    final (all, _, _) = await cli([
      'validate',
      'spec.json',
      'ok.oui',
      '--unknown=fail',
      '--max-depth=9',
      '--max-string=99',
      '--root=Col',
    ]);
    expect(all, 0);
  });

  test('a malformed spec is an unreadable input', () async {
    final (code, _, err) = await cli(['validate', 'broken.json', 'ok.oui']);
    expect(code, 2);
    expect(err, startsWith('openui: '));
  });

  test('an unreadable program is an unreadable input', () async {
    final (code, _, _) = await cli(['validate', 'spec.json', 'nope.oui']);
    expect(code, 2);
  });

  test('--root names the root of a bare JSON Schema', () async {
    final (code, out, _) = await cli([
      'validate',
      'schema.json',
      'ok.oui',
      '--root=Col',
    ]);
    expect(code, 0);
    expect(jsonDecode(out)['ok'], isTrue);
  });

  test(
    'a bare JSON Schema with no root name still checks the program',
    () async {
      final (code, out, _) = await cli(['validate', 'schema.json', 'ok.oui']);
      expect(code, 0);
      expect(jsonDecode(out)['ok'], isTrue);
    },
  );

  test('an unknown flag is a usage error', () async {
    final (code, _, err) = await cli([
      'validate',
      'spec.json',
      'ok.oui',
      '--bogus=1',
    ]);
    expect(code, 64);
    expect(err, contains('Usage: openui validate'));
  });

  test('a flag without a value is a usage error', () async {
    final (code, _, _) = await cli([
      'validate',
      'spec.json',
      'ok.oui',
      '--root',
    ]);
    expect(code, 64);
  });

  test('an unknown policy value is a usage error', () async {
    final (code, _, _) = await cli([
      'validate',
      'spec.json',
      'ok.oui',
      '--unknown=maybe',
    ]);
    expect(code, 64);
  });

  test('a command other than validate is a usage error', () async {
    final (code, _, _) = await cli(['spec', 'spec.json', 'ok.oui']);
    expect(code, 64);
  });
}
