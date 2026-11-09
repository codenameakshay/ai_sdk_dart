import 'dart:async';

import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:ai_sdk_openui/src/runtime/host_actions.dart' show actionBaseKey;
import 'package:test/test.dart';

final class _Spec implements ComponentSpec {
  const _Spec(this.typeName, this.props);
  @override
  final String typeName;
  @override
  String get description => '';
  @override
  final Map<String, Schema> props;
}

final _props = <String, Schema>{
  'value': S.any(),
  'action': actionSchema.optional(),
};

OpenUiSession _session(
  ActionHandler first,
  ActionHandler second, {
  String program = 'root = Out(1, Action([@ChargeA(), @ChargeB()]))',
}) {
  final library = OpenUiLibrary(
    root: _Spec('Out', _props),
    components: [_Spec('Out', _props)],
    actions: [
      ActionSpec('ChargeA', description: '', params: const {}, handler: first),
      ActionSpec('ChargeB', description: '', params: const {}, handler: second),
    ],
  );
  final session = OpenUiSession(library)..update(program, streaming: false);
  addTearDown(session.dispose);
  return session;
}

OpenUiAction _action(OpenUiSession session) =>
    session.root!.props.action('action')!;

Future<void> _click(OpenUiSession session, {String nodeId = 'button'}) =>
    session.run(_action(session), label: '', emit: (_) {}, nodeId: nodeId);

void main() {
  test('idempotency keys match cross-runtime Unicode and number vectors', () {
    final vectors = <(String, String, Map<String, Object?>)>[
      ('', 'Pay', {'value': -0.0}),
      ('scope-😀-λ', 'ÉPay', {'value': 1e-7}),
      ('', 'Pay', {'value': 1e-6}),
      ('', 'Pay', {'value': 1e20}),
      ('', 'Pay', {'value': 1e21}),
      ('', 'Pay', {'2': 'two', '10': 'ten', 'a': 1}),
    ];
    const expected = [
      'ce0006182fa6fae6',
      '73eb82705dfbfaf6',
      'b3cba461b09fa06f',
      '8e6185177555a3fd',
      '63f9190e27b4e294',
      'a9b684418820f40f',
    ];
    expect([
      for (final (scope, name, params) in vectors)
        actionBaseKey(scope, name, params),
    ], expected);
  });

  test(
    'a second tap cannot replay a synchronous prefix while step two is pending',
    () async {
      final firstCalls = <ActionInvocation>[];
      final secondCalls = <ActionInvocation>[];
      final secondGate = Completer<ActionResult>();
      final secondStarted = Completer<void>();
      final session = _session(
        (invocation) async {
          firstCalls.add(invocation);
          return const ActionSuccess();
        },
        (invocation) {
          secondCalls.add(invocation);
          if (!secondStarted.isCompleted) secondStarted.complete();
          return secondGate.future;
        },
      );

      final firstRun = _click(session);
      await secondStarted.future;
      final secondTap = _click(session);
      final prefixCallsWhilePending = firstCalls.length;
      final suffixCallsWhilePending = secondCalls.length;

      secondGate.complete(const ActionSuccess());
      await firstRun;
      await secondTap;
      expect(prefixCallsWhilePending, 1);
      expect(suffixCallsWhilePending, 1);
      expect(
        session.actionStatus(_action(session), nodeId: 'button')!.phase,
        ActionPhase.done,
      );
    },
  );

  test(
    'a pending run blocks a tap even if its parameters have changed',
    () async {
      final calls = <ActionInvocation>[];
      final gates = <Completer<ActionResult>>[];
      final library = OpenUiLibrary(
        root: _Spec('Out', _props),
        components: [_Spec('Out', _props)],
        actions: [
          ActionSpec(
            'Pay',
            description: '',
            params: {'quantity': S.number()},
            handler: (invocation) {
              calls.add(invocation);
              final gate = Completer<ActionResult>();
              gates.add(gate);
              return gate.future;
            },
          ),
        ],
      );
      final session = OpenUiSession(library)
        ..update(
          r'$quantity = 1'
          '\n'
          r'root = Out(1, @Pay($quantity))',
          streaming: false,
        );
      addTearDown(session.dispose);

      final observedStatuses = <ActionStatus>[];
      session.listen(() {
        observedStatuses.add(
          session.actionStatus(_action(session), nodeId: 'button')!,
        );
      });
      final firstRun = _click(session);
      session.field(r'$quantity', null).set(2);
      final pendingStatus = session.actionStatus(
        _action(session),
        nodeId: 'button',
      )!;
      final secondTap = _click(session);
      expect(calls, hasLength(1));
      expect(pendingStatus.phase, ActionPhase.pending);
      expect(pendingStatus.disabled, isTrue);
      for (final gate in gates) {
        gate.complete(const ActionSuccess());
      }
      await firstRun;
      expect(observedStatuses.last.phase, ActionPhase.idle);
      expect(observedStatuses.last.disabled, isFalse);

      final newParameterRun = _click(session);
      for (final gate in gates.skip(1)) {
        gate.complete(const ActionSuccess());
      }
      await newParameterRun;
      await secondTap;
      expect(calls, hasLength(2));
      expect(calls.map((call) => call.params), [
        {'quantity': 1},
        {'quantity': 2},
      ]);
    },
  );

  test('action status exposes a pending later step', () async {
    final gate = Completer<ActionResult>();
    final secondStarted = Completer<void>();
    final session = _session((_) async => const ActionSuccess(), (_) {
      if (!secondStarted.isCompleted) secondStarted.complete();
      return gate.future;
    });
    final running = _click(session);
    await secondStarted.future;
    final pendingStatus = session.actionStatus(
      _action(session),
      nodeId: 'button',
    )!;
    gate.complete(const ActionSuccess());
    await running;
    expect(pendingStatus.phase, ActionPhase.pending);
    expect(pendingStatus.disabled, isTrue);
  });
}
