import 'dart:convert';

import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:ai_sdk_openui/intelligent_ui.dart';
import 'package:ai_sdk_openui/src/cli/openui_cli.dart';
import 'package:test/test.dart';

void main() {
  for (final (id, statement, root) in [
    (
      'data',
      'data = Query("q", {payload: "abcdefgh"}, {})',
      'root = Col([Text(@Count(data.rows))])',
    ),
    (
      'save',
      'save = Mutation("m", {payload: "abcdefgh"})',
      'root = Col([Button("Save", @Run(save))])',
    ),
  ]) {
    test('$id backend arguments obey string limits', () {
      final report = intelligentUi.validate(
        '$statement\n$root',
        policy: const ValidationPolicy(maxStringLength: 5),
      );
      expect(report.ok, isFalse);
      final issue = report.issues.singleWhere(
        (i) => i.code == 'string-too-long',
      );
      expect(issue.statementId, id);
    });
  }

  test('query arguments obey the built-in and library action allow list', () {
    final report = intelligentUi.validate(
      'data = Query("q", {a: @OpenUrl("x"), '
      'b: @CopyToClipboard("x")}, {})\n'
      'root = Col([Text(@Count(data.rows))])',
      policy: const ValidationPolicy(allowedActions: {}),
    );
    expect(report.ok, isFalse);
    final issues = report.issues
        .where((i) => i.code == 'action-not-allowed')
        .toList();
    expect(issues, hasLength(2));
    expect(issues.map((i) => i.statementId), everyElement('data'));
  });

  test('query argument components obey node and depth limits', () {
    final report = intelligentUi.validate(
      'data = Query("q", {ui: Card([Title("a")])}, {})\n'
      'root = Col([])',
      policy: const ValidationPolicy(maxNodes: 1, maxDepth: 1),
    );
    expect(report.ok, isFalse);
    expect(report.nodes, 3);
    expect(report.issues.map((i) => i.code), contains('too-many-nodes'));
    expect(
      report.issues
          .where((i) => i.code == 'too-deep')
          .map((i) => i.statementId),
      contains('data'),
    );
  });

  test(
    'CLI exits invalid when a query argument violates the string limit',
    () async {
      final output = StringBuffer();
      final errors = StringBuffer();
      final code = await runOpenUiCli(
        ['validate', 'spec.json', 'query.oui', '--max-string=5'],
        read: (path) async => switch (path) {
          'spec.json' => intelligentUi.toSpecJson(),
          'query.oui' =>
            'data = Query("q", {payload: "abcdefgh"}, {})\n'
                'root = Col([Text(@Count(data.rows))])',
          _ => throw StateError('Unexpected input $path'),
        },
        out: output.write,
        err: errors.write,
      );
      expect(code, 1);
      expect(errors.toString(), isEmpty);
      final report = jsonDecode(output.toString()) as Map<String, Object?>;
      expect(report['ok'], isFalse);
      expect(
        report['issues'],
        contains(containsPair('code', 'string-too-long')),
      );
    },
  );
}
