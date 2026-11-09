import 'dart:convert';

import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:ai_sdk_openui/intelligent_ui.dart';
import 'package:test/test.dart';

void main() {
  test('a clean program passes with its stats', () {
    final report = intelligentUi.validate('root = Col([Title("Hi")])');
    expect(report.ok, isTrue);
    expect(report.issues, isEmpty);
    expect(report.toJson()['stats'], {'nodes': 2, 'depth': 2, 'statements': 1});
  });

  test('parse errors carry their statement', () {
    final report = intelligentUi.validate('root = Col([Title()])');
    expect(report.ok, isFalse);
    final issue = report.issues.first;
    expect(issue.code, 'missing-required');
    expect(issue.statementId, 'root');
    expect(issue.component, 'Title');
    expect(issue.path, '/text');
    expect(issue.isWarning, isFalse);
  });

  test('too many components fails', () {
    final report = intelligentUi.validate(
      'root = Col([Title("a"), Title("b")])',
      policy: const ValidationPolicy(maxNodes: 2),
    );
    expect(report.ok, isFalse);
    expect(report.issues, hasLength(1));
    final issue = report.issues.single;
    expect(issue.code, 'too-many-nodes');
    expect(issue.message, 'The program has 3 components; the limit is 2');
    expect(issue.statementId, 'root');
  });

  test('nesting past the limit fails at the deepest statement', () {
    final report = intelligentUi.validate(
      'root = Col([c])\nc = Card([t])\nt = Title("a")',
      policy: const ValidationPolicy(maxDepth: 2),
    );
    expect(report.ok, isFalse);
    expect(report.issues, hasLength(1));
    final issue = report.issues.single;
    expect(issue.code, 'too-deep');
    expect(issue.message, 'Component Title is nested 3 deep; the limit is 2');
    expect(issue.statementId, 't');
    expect(issue.component, 'Title');
    expect(issue.path, isNull);
  });

  test('a long string fails with its path', () {
    final report = intelligentUi.validate(
      'root = Col([t])\nt = Title("Hello world")',
      policy: const ValidationPolicy(maxStringLength: 5),
    );
    expect(report.ok, isFalse);
    expect(report.issues, hasLength(1));
    final issue = report.issues.single;
    expect(issue.code, 'string-too-long');
    expect(issue.message, 'A string of 11 characters is over the limit of 5');
    expect(issue.statementId, 't');
    expect(issue.component, 'Title');
    expect(issue.path, '/text');
  });

  test('a long string in a root expression is checked too', () {
    final report = intelligentUi.validate(
      r'$t = true'
      '\n'
      r'root = $t ? Col([Title("Hello world")]) : Col([])',
      policy: const ValidationPolicy(maxStringLength: 5),
    );
    expect(report.ok, isFalse);
    expect(report.issues.map((i) => i.code), contains('string-too-long'));
  });

  test('a string in a state initialiser is checked', () {
    final report = intelligentUi.validate(
      r'$name = "Hello world"'
      '\n'
      'root = Col([Title("a")])',
      policy: const ValidationPolicy(maxStringLength: 5),
    );
    expect(report.ok, isFalse);
    final issue = report.issues.single;
    expect(issue.code, 'string-too-long');
    expect(issue.statementId, r'$name');
    expect(issue.component, isNull);
  });

  test('a string inside an expression argument is checked', () {
    final report = intelligentUi.validate(
      r'root = Col([Text("n: " + "abcdefgh")])',
      policy: const ValidationPolicy(maxStringLength: 5),
    );
    expect(report.ok, isFalse);
    expect(report.issues.single.code, 'string-too-long');
  });

  test('unknown components warn by default and fail on request', () {
    final warned = intelligentUi.validate('root = Col([Foo("x")])');
    expect(warned.ok, isTrue);
    final warning = warned.issues.single;
    expect(warning.code, 'unknown-component');
    expect(warning.isWarning, isTrue);

    final failed = intelligentUi.validate(
      'root = Col([Foo("x")])',
      policy: const ValidationPolicy(
        unknownComponents: UnknownComponentPolicy.fail,
      ),
    );
    expect(failed.ok, isFalse);
    final error = failed.issues.single;
    expect(error.code, 'unknown-component');
    expect(error.isWarning, isFalse);
  });

  test('an action outside the allow list fails', () {
    final report = intelligentUi.validate(
      'root = Col([Button("Go", @OpenUrl("https://example.com"))])',
      policy: const ValidationPolicy(allowedActions: {'ToAssistant'}),
    );
    expect(report.ok, isFalse);
    expect(report.issues, hasLength(1));
    final issue = report.issues.single;
    expect(issue.code, 'action-not-allowed');
    expect(issue.message, 'Action @OpenUrl is not allowed');
    expect(issue.statementId, 'root');
    expect(issue.component, 'Button');
    expect(issue.path, '/children/0/action');
  });

  test('an allowed action passes', () {
    final report = intelligentUi.validate(
      'root = Col([Button("Go", @OpenUrl("https://example.com"))])',
      policy: const ValidationPolicy(allowedActions: {'OpenUrl'}),
    );
    expect(report.ok, isTrue);
  });

  test('a library action outside the allow list fails', () {
    final report = intelligentUi.validate(
      'root = Col([Button("Copy", @CopyToClipboard("hi"))])',
      policy: const ValidationPolicy(allowedActions: {'OpenUrl'}),
    );
    expect(report.ok, isFalse);
    expect(
      report.issues.single.message,
      'Action @CopyToClipboard is not allowed',
    );
  });

  test('strings inside operators, objects and member access are checked', () {
    for (final program in [
      'root = Col([Text(@Count({a: "abcdefgh"}))])',
      'root = Col([Text(!@Count("abcdefgh"))])',
      'root = Col([Text(@Count({a: "abcdefgh"}).a)])',
      'root = Col([Text(@Count(["abcdefgh"][0]))])',
      'root = Col([Text(@Count(["a"])[0] + "abcdefgh")])',
    ]) {
      final report = intelligentUi.validate(
        program,
        policy: const ValidationPolicy(maxStringLength: 5),
      );
      expect(
        report.issues.map((i) => i.code),
        contains('string-too-long'),
        reason: program,
      );
    }
  });

  test('a string inside an object in state is checked', () {
    final report = intelligentUi.validate(
      r'$cfg = {k: "abcdefgh"}'
      '\n'
      'root = Col([Title("a")])',
      policy: const ValidationPolicy(maxStringLength: 5),
    );
    expect(report.issues.map((i) => i.code), contains('string-too-long'));
  });

  test('a string assigned to state is checked', () {
    final report = intelligentUi.validate(
      r'$n = 0'
      '\n'
      r'root = Col([Button("Go", Action([$n = "abcdefgh"]))])',
      policy: const ValidationPolicy(maxStringLength: 5),
    );
    expect(report.issues.map((i) => i.code), contains('string-too-long'));
  });

  test('an action inside a function call argument is checked', () {
    final report = intelligentUi.validate(
      'root = Col([Button("Go", Action([@OpenUrl("https://example.com")]))])',
      policy: const ValidationPolicy(allowedActions: {'ToAssistant'}),
    );
    expect(report.ok, isFalse);
    expect(report.issues.single.code, 'action-not-allowed');
  });

  test('unresolved and orphaned names warn', () {
    final report = intelligentUi.validate(
      'root = Col([a, missing])\na = Title("a")\nb = Title("b")',
    );
    expect(report.ok, isTrue);
    final unresolved = report.issues.singleWhere((i) => i.code == 'unresolved');
    expect(unresolved.isWarning, isTrue);
    expect(unresolved.message, 'Reference "missing" is never defined');
    final orphaned = report.issues.singleWhere((i) => i.code == 'orphaned');
    expect(orphaned.isWarning, isTrue);
    expect(orphaned.statementId, 'b');
    expect(orphaned.message, 'Statement "b" is not reachable from root');
  });

  test('an unfinished program fails', () {
    final report = intelligentUi.validate('root = Col([Title("a"');
    expect(report.ok, isFalse);
    final issue = report.issues.singleWhere((i) => i.code == 'incomplete');
    expect(issue.message, 'The program ends inside an unfinished statement');
  });

  test('a bound variable is accepted when declared', () {
    final report = intelligentUi.validate(
      r'root = Col([Title($order.total)])',
      bound: {r'$order'},
    );
    expect(report.issues.where((i) => i.code == 'unresolved'), isEmpty);
  });

  test('a validation with no root reports no-root', () {
    final report = intelligentUi.validate('title = Title("x")');
    expect(report.ok, isFalse);
    expect(report.hasRoot, isFalse);
    expect(report.issues.map((i) => i.code), contains('no-root'));
  });

  test('an empty program is reported as incomplete', () {
    final report = intelligentUi.validate('');
    expect(report.ok, isFalse);
    expect(report.hasRoot, isFalse);
  });

  test('a root expression counts all of its components', () {
    final report = intelligentUi.validate(
      r'$t = true'
      '\n'
      r'root = $t ? Col([Title("a")]) : Col([Title("b")])',
    );
    expect(report.ok, isTrue);
    expect(report.hasRoot, isTrue);
    expect(report.nodes, 4);
  });

  test('a root expression is limited by depth', () {
    final report = intelligentUi.validate(
      r'$t = true'
      '\n'
      r'root = $t ? Col([Title("a")]) : Col([Title("b")])',
      policy: const ValidationPolicy(maxDepth: 1),
    );
    expect(report.ok, isFalse);
    expect(report.issues.single.code, 'too-deep');
  });

  test('an each loop counts its template once', () {
    final report = intelligentUi.validate(
      'root = Col(@Each([1, 2], "n", Text("" + n)))',
      policy: const ValidationPolicy(maxNodes: 2),
    );
    expect(report.ok, isTrue);
    expect(report.nodes, 2);
  });

  test('a program with a state object is walked', () {
    final report = intelligentUi.validate(
      r'$count = 0'
      '\n'
      r'root = Col([Text("n: " + $count), Button("+", @Set($count, $count + 1))])',
    );
    expect(report.ok, isTrue);
    expect(report.statements, 2);
  });

  test('a query and mutation statement are walked', () {
    final report = intelligentUi.validate(
      'data = Query("get_rows", {}, {rows: []})\n'
      'save = Mutation("save", {})\n'
      'root = Col([Text(@Count(data.rows)), Button("Save", @Run(save))])',
    );
    expect(report.ok, isTrue);
  });

  test('the report is JSON', () {
    final report = intelligentUi.validate('root = Col([Title()])');
    final text = report.toJsonString();
    expect(text, endsWith('\n'));
    expect(jsonDecode(text), report.toJson());
  });

  test('an issue serialises with its severity and omits empty fields', () {
    final report = intelligentUi.validate('root = Col([Foo("x")])');
    final json = report.issues.single.toJson();
    expect(json['severity'], 'warning');
    expect(json.containsKey('component'), isTrue);
    expect(json.containsKey('path'), isFalse);
  });

  test('a validation issue with no statement or component omits them', () {
    const issue = ValidationIssue(code: 'x', message: 'y');
    expect(issue.toJson(), {'code': 'x', 'severity': 'error', 'message': 'y'});
  });
}
