import 'dart:async';

import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:ai_sdk_openui/src/runtime/queries.dart';
import 'package:ai_sdk_openui/src/runtime/evaluator.dart';
import 'package:ai_sdk_openui/src/lang/ast.dart';
import 'package:test/test.dart';

final class _Out implements ComponentSpec {
  const _Out();
  @override
  String get typeName => 'Out';
  @override
  String get description => '';
  @override
  Map<String, Schema> get props => {
    'value': S.any().reactive(),
    'action': actionSchema.optional(),
  };
}

final _library = OpenUiLibrary(root: const _Out(), components: const [_Out()]);
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('a stored null is a cleared field, not its initial value', () {
    final session = OpenUiSession(_library);
    addTearDown(session.dispose);
    session.update('root = Out(1)', streaming: false);
    session.field('name', 'initial').set(null);
    session.field('name', 'initial', formName: 'form').set(null);
    expect(session.field('name', 'initial').value, isNull);
    expect(session.field('name', 'initial', formName: 'form').value, isNull);
  });

  test('numeric addition and subtraction round as JavaScript numbers', () {
    final context = EvaluationContext(
      getState: (_) => null,
      resolveRef: (_) => null,
    );
    expect(
      evaluate(
        const BinOpNode('+', NumNode(9007199254740991), NumNode(2)),
        context,
      ),
      9007199254740992,
    );
    expect(
      evaluate(
        const BinOpNode('-', NumNode(-9007199254740991), NumNode(2)),
        context,
      ),
      -9007199254740992,
    );
    expect(
      evaluate(const BinOpNode('+', StrNode('n='), NumNode(2)), context),
      'n=2',
    );
  });

  test('arithmetic preserves negative zero', () {
    final context = EvaluationContext(
      getState: (_) => null,
      resolveRef: (_) => null,
    );
    final negated =
        evaluate(const UnaryOpNode('-', NumNode(0)), context) as num;
    final multiplied =
        evaluate(const BinOpNode('*', NumNode(0), NumNode(-1)), context) as num;
    expect(negated.isNegative, isTrue);
    expect(multiplied.isNegative, isTrue);
    final remainder =
        evaluate(const BinOpNode('%', NumNode(-2), NumNode(2)), context) as num;
    expect(remainder.isNegative, isTrue);
  });

  test('a non-finite refresh interval cannot crash query reconciliation', () {
    final manager = QueryManager(null);
    addTearDown(manager.dispose);
    manager.evaluate([
      const QueryNode(
        statementId: 'q',
        toolName: 't',
        args: {},
        defaults: 'waiting',
        refreshSeconds: double.infinity,
      ),
    ]);
    expect(manager.result('q'), 'waiting');
    expect(manager.isLoading, isFalse);
  });

  test('disposing from a host event stops the remaining action steps', () async {
    final session = OpenUiSession(_library);
    addTearDown(session.dispose);
    session.update(
      'root = Out(1, Action([@ToAssistant("first"), @ToAssistant("second")]))',
      streaming: false,
    );
    final messages = <String>[];
    await session.run(
      session.root!.props.action('action'),
      label: '',
      emit: (event) {
        messages.add(event.humanFriendlyMessage);
        session.dispose();
      },
    );
    expect(messages, ['first']);
  });

  test('initialState seeds variables once, without undoing later edits', () {
    final session = OpenUiSession(_library, initialState: {r'$n': 4});
    addTearDown(session.dispose);
    session.update('root = Out(\$n)\n\$n = 1', streaming: true);
    session.field('', session.root!.props.binding('value')).set(9);
    session.update('root = Out(\$n)\n\$n = 2', streaming: false);
    expect(session.state[r'$n'], 9);
  });

  test('actions do not run while the answer streams', () async {
    final session = OpenUiSession(_library);
    addTearDown(session.dispose);
    session.update('root = Out(1, @ToAssistant("go"))', streaming: true);
    final events = <ActionEvent>[];
    await session.run(
      session.root!.props.action('action'),
      label: 'go',
      emit: events.add,
    );
    expect(events, isEmpty);
    session.update('root = Out(1, @ToAssistant("go"))', streaming: false);
    await session.run(
      session.root!.props.action('action'),
      label: 'go',
      emit: events.add,
    );
    expect(events.map((e) => e.humanFriendlyMessage), ['go']);
  });

  test(
    'a shared query still resolves after the initiating statement disappears',
    () async {
      final pending = Completer<Object?>();
      var calls = 0;
      final manager = QueryManager((_, _) {
        calls++;
        return pending.future;
      });
      addTearDown(manager.dispose);
      QueryNode node(String id) => QueryNode(
        statementId: id,
        toolName: 't',
        args: const {},
        defaults: 'waiting',
      );
      manager.evaluate([node('a'), node('b')]);
      manager.evaluate([node('b')]);
      expect(manager.isLoading, isTrue);
      pending.complete('answer');
      await _settle();
      expect(calls, 1);
      expect(manager.result('b'), 'answer');
      expect(manager.isLoading, isFalse);
    },
  );

  test(
    'a replaced mutation ignores the old tool response and halts its plan',
    () async {
      final pending = Completer<Object?>();
      final session = OpenUiSession(
        _library,
        tools: [
          OpenUiTool(name: 'a', call: (_) => pending.future),
          OpenUiTool(name: 'b', call: (_) async => 'new'),
        ],
      );
      addTearDown(session.dispose);
      session.update(
        'root = Out(m, Action([@Run(m), @ToAssistant("old")]))\nm = Mutation("a", {})',
        streaming: false,
      );
      final events = <ActionEvent>[];
      final running = session.run(
        session.root!.props.action('action'),
        label: '',
        emit: events.add,
      );
      session.update('root = Out(m)\nm = Mutation("b", {})', streaming: false);
      pending.complete('stale');
      await running;
      expect(session.root!.props['value'], {
        'status': 'idle',
        'data': null,
        'error': null,
      });
      expect(events, isEmpty);
    },
  );
}
