import 'dart:async';

import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:ai_sdk_openui/src/runtime/host_actions.dart'
    show actionBaseKey, actionStateKey;
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
  List<ActionSpec> actions, {
  String program = 'root = Out(1, Action([@ChargeA(), @ChargeB()]))',
  Map<String, Object?> initialState = const {},
  List<OpenUiTool> tools = const [],
  void Function(Map<String, Object?> state)? onStateUpdate,
}) {
  final library = OpenUiLibrary(
    root: _Spec('Out', _props),
    components: [_Spec('Out', _props)],
    actions: actions,
  );
  final session = OpenUiSession(
    library,
    initialState: initialState,
    tools: tools,
    onStateUpdate: onStateUpdate,
  )..update(program, streaming: false);
  addTearDown(session.dispose);
  return session;
}

OpenUiAction _action(OpenUiSession session) =>
    session.root!.props.action('action')!;

Future<void> _click(OpenUiSession session) =>
    session.run(_action(session), label: '', emit: (_) {}, nodeId: 'button');

void main() {
  test(
    'retry after second-step failure skips first and reuses second key',
    () async {
      final firstCalls = <ActionInvocation>[];
      final secondCalls = <ActionInvocation>[];
      var secondAttempt = 0;
      final actions = [
        ActionSpec(
          'ChargeA',
          description: '',
          params: const {},
          handler: (invocation) async {
            firstCalls.add(invocation);
            return const ActionSuccess();
          },
        ),
        ActionSpec(
          'ChargeB',
          description: '',
          params: const {},
          handler: (invocation) async {
            secondCalls.add(invocation);
            secondAttempt++;
            return secondAttempt == 1
                ? const ActionFailure('try again')
                : const ActionSuccess();
          },
        ),
      ];
      final session = _session(actions);
      await _click(session);
      final failedSecondKey = secondCalls.single.idempotencyKey;

      await _click(session);
      expect(firstCalls, hasLength(1));
      expect(secondCalls, hasLength(2));
      expect(secondCalls[1].idempotencyKey, failedSecondKey);
    },
  );

  test(
    'disableAfterSuccess on a prefix does not block retrying its failed suffix',
    () async {
      final firstCalls = <ActionInvocation>[];
      final secondCalls = <ActionInvocation>[];
      var secondAttempt = 0;
      final actions = [
        ActionSpec(
          'ChargeA',
          description: '',
          params: const {},
          disableAfterSuccess: true,
          handler: (invocation) async {
            firstCalls.add(invocation);
            return const ActionSuccess();
          },
        ),
        ActionSpec(
          'ChargeB',
          description: '',
          params: const {},
          handler: (invocation) async {
            secondCalls.add(invocation);
            secondAttempt++;
            return secondAttempt == 1
                ? const ActionFailure('try again')
                : const ActionSuccess();
          },
        ),
      ];
      final session = _session(actions);
      await _click(session);
      await _click(session);
      expect(firstCalls, hasLength(1));
      expect(secondCalls, hasLength(2));
      expect(secondCalls[1].idempotencyKey, secondCalls[0].idempotencyKey);
      expect(
        session.actionStatus(_action(session), nodeId: 'button')!.disabled,
        isTrue,
      );
      await _click(session);
      expect(firstCalls, hasLength(1));
      expect(secondCalls, hasLength(2));
    },
  );

  test(
    'restore can retry a later failed step without replaying its prefix',
    () async {
      final firstCalls = <ActionInvocation>[];
      final secondCalls = <ActionInvocation>[];
      var secondAttempt = 0;
      final actions = [
        ActionSpec(
          'ChargeA',
          description: '',
          params: const {},
          handler: (invocation) async {
            firstCalls.add(invocation);
            return const ActionSuccess();
          },
        ),
        ActionSpec(
          'ChargeB',
          description: '',
          params: const {},
          handler: (invocation) async {
            secondCalls.add(invocation);
            secondAttempt++;
            return secondAttempt == 1
                ? const ActionFailure('try again')
                : const ActionSuccess();
          },
        ),
      ];
      final firstSession = _session(actions);
      await _click(firstSession);
      final failedSecondKey = secondCalls.single.idempotencyKey;

      final restored = _session(actions, initialState: firstSession.state);
      await _click(restored);
      expect(firstCalls, hasLength(1));
      expect(secondCalls, hasLength(2));
      expect(secondCalls[1].idempotencyKey, failedSecondKey);
    },
  );

  test('duplicate identical steps resume at the failed occurrence', () async {
    final calls = <ActionInvocation>[];
    var attempt = 0;
    final session = _session([
      ActionSpec(
        'ChargeA',
        description: '',
        params: const {},
        handler: (invocation) async {
          calls.add(invocation);
          attempt++;
          return attempt == 2
              ? const ActionFailure('retry this occurrence')
              : const ActionSuccess();
        },
      ),
    ], program: 'root = Out(1, Action([@ChargeA(), @ChargeA()]))');

    await _click(session);
    expect(calls.map((call) => call.attempt), [1, 2]);
    final failedOccurrenceKey = calls.last.idempotencyKey;

    await _click(session);
    expect(calls, hasLength(3));
    expect(calls.last.attempt, 2);
    expect(calls.last.idempotencyKey, failedOccurrenceKey);
  });

  test('a restored pending duplicate step retries with the same key', () async {
    final calls = <ActionInvocation>[];
    var attempt = 0;
    Completer<ActionResult>? pending;
    final secondStarted = Completer<void>();
    final actions = [
      ActionSpec(
        'ChargeA',
        description: '',
        params: const {},
        handler: (invocation) {
          calls.add(invocation);
          attempt++;
          if (attempt == 1) return Future.value(const ActionSuccess());
          if (attempt == 2) {
            secondStarted.complete();
            pending = Completer<ActionResult>();
            return pending!.future;
          }
          return Future.value(const ActionSuccess());
        },
      ),
    ];
    final first = _session(
      actions,
      program: 'root = Out(1, Action([@ChargeA(), @ChargeA()]))',
    );
    final running = _click(first);
    await secondStarted.future;
    final savedWhilePending = first.state;
    expect(
      ((savedWhilePending[actionStateKey] as Map)['__plans'] as Map)
          .values
          .single,
      {'phase': 'pending', 'cursor': 1},
    );
    final pendingKey = calls.last.idempotencyKey;
    pending!.complete(const ActionSuccess());
    await running;

    final restored = _session(
      actions,
      program: 'root = Out(1, Action([@ChargeA(), @ChargeA()]))',
      initialState: savedWhilePending,
    );
    await _click(restored);
    expect(calls, hasLength(3));
    expect(calls.last.attempt, 2);
    expect(calls.last.idempotencyKey, pendingKey);
  });

  test(
    'a later deliberate run repeats a completed plan with fresh attempts',
    () async {
      final calls = <ActionInvocation>[];
      final actions = [
        for (final name in ['ChargeA', 'ChargeB'])
          ActionSpec(
            name,
            description: '',
            params: const {},
            handler: (invocation) async {
              calls.add(invocation);
              return const ActionSuccess();
            },
          ),
      ];
      final session = _session(actions);
      await _click(session);
      await _click(session);
      expect(calls.map((call) => call.name), [
        'ChargeA',
        'ChargeB',
        'ChargeA',
        'ChargeB',
      ]);
      expect(calls.map((call) => call.attempt), [1, 1, 2, 2]);
    },
  );

  test(
    'completion state snapshots already include the advanced cursor',
    () async {
      final snapshots = <Map<String, Object?>>[];
      final actions = [
        for (final name in ['ChargeA', 'ChargeB'])
          ActionSpec(
            name,
            description: '',
            params: const {},
            handler: (_) async => name == 'ChargeB'
                ? const ActionFailure('stop')
                : const ActionSuccess(),
          ),
      ];
      final session = _session(actions, onStateUpdate: snapshots.add);
      await _click(session);

      final base = actionBaseKey('', 'button', 'ChargeA', const {});
      final completion = snapshots.firstWhere((state) {
        final status = (state[actionStateKey] as Map)[base];
        return status is Map && status['phase'] == 'done';
      });
      final plans =
          (completion[actionStateKey] as Map)['__plans']
              as Map<String, Object?>;
      final cursor = (plans.values.single as Map)['cursor'];
      expect(cursor, 1);
    },
  );

  test('map key order does not change retry identity', () async {
    final firstCalls = <ActionInvocation>[];
    final secondCalls = <ActionInvocation>[];
    var secondAttempt = 0;
    final library = OpenUiLibrary(
      root: _Spec('Out', _props),
      components: [_Spec('Out', _props)],
      actions: [
        ActionSpec(
          'ChargeA',
          description: '',
          params: {'payload': S.any()},
          handler: (invocation) async {
            firstCalls.add(invocation);
            return const ActionSuccess();
          },
        ),
        ActionSpec(
          'ChargeB',
          description: '',
          params: const {},
          handler: (invocation) async {
            secondCalls.add(invocation);
            secondAttempt++;
            return secondAttempt == 1
                ? const ActionFailure('retry')
                : const ActionSuccess();
          },
        ),
      ],
    );
    const before =
        'root = Out(1, Action([@ChargeA({payload: {nested: {b: 2, a: 1}}}), @ChargeB()]))';
    const after =
        'root = Out(1, Action([@ChargeA({payload: {nested: {a: 1, b: 2}}}), @ChargeB()]))';
    final session = OpenUiSession(library)..update(before, streaming: false);
    addTearDown(session.dispose);
    await _click(session);
    final failedKey = secondCalls.single.idempotencyKey;

    session.update(after, streaming: false);
    await _click(session);
    expect(firstCalls, hasLength(1));
    expect(secondCalls, hasLength(2));
    expect(secondCalls[1].idempotencyKey, failedKey);
  });

  test('a failed Mutation resumes after the successful host prefix', () async {
    final firstCalls = <ActionInvocation>[];
    final secondCalls = <ActionInvocation>[];
    var mutationCalls = 0;
    final session = _session(
      [
        ActionSpec(
          'ChargeA',
          description: '',
          params: const {},
          handler: (invocation) async {
            firstCalls.add(invocation);
            return const ActionSuccess();
          },
        ),
        ActionSpec(
          'ChargeB',
          description: '',
          params: const {},
          handler: (invocation) async {
            secondCalls.add(invocation);
            return const ActionSuccess();
          },
        ),
      ],
      program:
          'root = Out(1, Action([@ChargeA(), @Run(m), @ChargeB()]))\n'
          'm = Mutation("save", {})\n'
          'q = Query("lookup", {})',
      tools: [
        OpenUiTool(
          name: 'save',
          call: (_) async {
            mutationCalls++;
            if (mutationCalls == 1) throw Exception('temporary failure');
            return 'saved';
          },
        ),
        OpenUiTool(
          name: 'lookup',
          call: (_) async => throw Exception('unrelated query failure'),
        ),
      ],
    );

    final queryFailure = Completer<void>();
    bool hasUnrelatedQueryFailure() => session.queryErrors.any(
      (error) => error.message.contains('unrelated query failure'),
    );
    final cancel = session.listen(() {
      if (hasUnrelatedQueryFailure() && !queryFailure.isCompleted) {
        queryFailure.complete();
      }
    });
    addTearDown(cancel);
    if (hasUnrelatedQueryFailure()) queryFailure.complete();
    await queryFailure.future.timeout(const Duration(seconds: 2));
    await _click(session);
    expect(
      session.actionStatus(_action(session), nodeId: 'button')!.message,
      contains('temporary failure'),
    );
    expect(firstCalls, hasLength(1));
    expect(mutationCalls, 1);
    expect(secondCalls, isEmpty);

    await _click(session);
    expect(firstCalls, hasLength(1));
    expect(mutationCalls, 2);
    expect(secondCalls, hasLength(1));
  });

  test('status reports failure in the later handled step', () async {
    final actions = [
      ActionSpec(
        'ChargeA',
        description: '',
        params: const {},
        handler: (_) async => const ActionSuccess(),
      ),
      ActionSpec(
        'ChargeB',
        description: '',
        params: const {},
        handler: (_) async => const ActionFailure('try again'),
      ),
    ];
    final session = _session(actions);
    await _click(session);
    expect(
      session.actionStatus(_action(session), nodeId: 'button')!.phase,
      ActionPhase.failed,
    );
  });
}
