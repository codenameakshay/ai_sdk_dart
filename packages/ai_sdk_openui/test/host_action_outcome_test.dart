import 'dart:async';

import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:ai_sdk_openui/src/runtime/host_actions.dart'
    show actionStateKey;
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

const _pay = 'root = Out(1, @Pay("o-1"))';

void main() {
  late List<ActionInvocation> pays;
  late List<ActionInvocation> notes;
  late List<ActionEvent> events;
  late Completer<ActionResult> payResult;
  late List<ActionResult> noteResults;

  setUp(() {
    pays = [];
    notes = [];
    events = [];
    payResult = Completer();
    noteResults = [];
  });

  OpenUiSession open(
    String program, {
    Map<String, Object?> state = const {},
    Future<ActionResult> Function(ActionInvocation invocation)? resolve,
  }) {
    final library = OpenUiLibrary(
      root: _Spec('Out', _props),
      components: [_Spec('Out', _props)],
      actions: [
        ActionSpec(
          'Pay',
          description: '',
          params: {'orderId': S.string()},
          disableAfterSuccess: true,
          handler: (i) {
            pays.add(i);
            return payResult.future;
          },
        ),
        ActionSpec(
          'Note',
          description: '',
          params: const {},
          handler: (i) async {
            notes.add(i);
            return noteResults.isEmpty
                ? const ActionSuccess()
                : noteResults.removeAt(0);
          },
        ),
      ],
    );
    final session = OpenUiSession(
      library,
      initialState: state,
      resolveAction: resolve,
    )..update(program, streaming: false);
    addTearDown(session.dispose);
    return session;
  }

  OpenUiAction action(OpenUiSession s) => s.root!.props.action('action')!;
  ActionStatus status(OpenUiSession s) =>
      s.actionStatus(action(s), nodeId: 'button')!;
  Future<void> click(OpenUiSession s) =>
      s.run(action(s), label: '', emit: events.add, nodeId: 'button');

  /// The state saved while the first Pay is still running.
  Future<Map<String, Object?>> savedWhilePaying(String program) async {
    final first = open(program);
    unawaited(click(first));
    await pumpEventQueue();
    expect(status(first).phase, ActionPhase.pending);
    return first.state;
  }

  group('a write cut off by a restore', () {
    test(
      'is unknown and not retryable until the resolver settles it',
      () async {
        final saved = await savedWhilePaying(_pay);
        final key = pays.single.idempotencyKey;
        final resolved = Completer<ActionResult>();
        final asked = <ActionInvocation>[];
        final s = open(
          _pay,
          state: saved,
          resolve: (i) {
            asked.add(i);
            return resolved.future;
          },
        );
        expect(asked.single.idempotencyKey, key);
        expect(asked.single.name, 'Pay');
        expect(asked.single.params, {'orderId': 'o-1'});
        expect(status(s).phase, ActionPhase.unknown);
        expect(status(s).disabled, isTrue);
        expect(status(s).idempotencyKey, key);
        expect(
          ((s.state[actionStateKey] as Map).values.first as Map)['phase'],
          'unknown',
        );
        await click(s);
        expect(pays, hasLength(1));

        resolved.complete(const ActionSuccess({'recordId': 'e-9'}));
        await pumpEventQueue();
        expect(status(s).phase, ActionPhase.done);
        expect(status(s).disabled, isTrue);
        await click(s);
        expect(pays, hasLength(1));
      },
    );

    test('restores as unknown again if saved while being resolved', () async {
      final saved = await savedWhilePaying(_pay);
      final resolving = open(
        _pay,
        state: saved,
        resolve: (_) => Completer<ActionResult>().future,
      );
      final asked = <ActionInvocation>[];
      final s = open(
        _pay,
        state: resolving.state,
        resolve: (i) async {
          asked.add(i);
          return const ActionFailure('declined');
        },
      );
      expect(asked.single.name, 'Pay');
      await pumpEventQueue();
      expect(status(s).phase, ActionPhase.failed);
      expect(status(s).message, 'declined');
    });

    test(
      'a resolver that throws fails it, and a retry sends its key',
      () async {
        final saved = await savedWhilePaying(_pay);
        final key = pays.single.idempotencyKey;
        final s = open(
          _pay,
          state: saved,
          resolve: (_) async => throw StateError('offline'),
        );
        await pumpEventQueue();
        expect(status(s).phase, ActionPhase.failed);
        expect(status(s).message, 'offline');
        payResult = Completer()..complete(const ActionSuccess());
        await click(s);
        expect(pays.last.idempotencyKey, key);
      },
    );

    test('resumes the plan after the step the resolver settled', () async {
      const program = 'root = Out(1, Action([@Pay("o-1"), @Note()]))';
      final saved = await savedWhilePaying(program);
      final s = open(
        program,
        state: saved,
        resolve: (_) async => const ActionSuccess({'recordId': 'e-9'}),
      );
      await pumpEventQueue();
      expect(status(s).phase, ActionPhase.failed);
      await click(s);
      expect(pays, hasLength(1));
      expect(notes.single.results, {
        'Pay': {'recordId': 'e-9'},
      });
      expect(status(s).phase, ActionPhase.done);
    });

    test('a plan cut off at a step without a key restores as failed', () async {
      payResult.complete(const ActionSuccess());
      const program =
          'root = Out(1, Action([@Pay("o-1"), @ToAssistant("Hi")]))';
      final first = open(program);
      await click(first);
      final actions = {...first.state[actionStateKey]! as Map};
      final plans = actions['__plans'] as Map;
      actions['__plans'] = {
        plans.keys.single: {'phase': 'pending', 'cursor': 1},
      };
      var asked = 0;
      final s = open(
        program,
        state: {...first.state, actionStateKey: actions},
        resolve: (_) async {
          asked++;
          return const ActionSuccess();
        },
      );
      expect(asked, 0);
      expect(status(s).phase, ActionPhase.failed);
    });

    test('is asked about once when the same state is restored again', () async {
      final saved = await savedWhilePaying(_pay);
      var asked = 0;
      final s = open(
        _pay,
        state: saved,
        resolve: (_) {
          asked++;
          return Completer<ActionResult>().future;
        },
      );
      s.update(_pay, streaming: false, restoredState: saved);
      expect(asked, 1);
      expect(status(s).phase, ActionPhase.unknown);
    });

    test('a resolver is not asked about a session that is disposed', () async {
      final saved = await savedWhilePaying(_pay);
      final resolved = Completer<ActionResult>();
      final s = open(_pay, state: saved, resolve: (_) => resolved.future);
      s.dispose();
      resolved.complete(const ActionSuccess());
      await pumpEventQueue();
      expect(
        ((s.state[actionStateKey] as Map).values.first as Map)['phase'],
        'unknown',
      );
    });
  });

  group('a success payload', () {
    test('is saved with the state and restored', () async {
      payResult.complete(const ActionSuccess({'recordId': 'e-9'}));
      final first = open(_pay);
      await click(first);
      final saved = first.state;
      expect(
        (saved[actionStateKey] as Map).values.first,
        containsPair('data', {'recordId': 'e-9'}),
      );
      final restored = open(_pay, state: saved);
      expect(restored.state[actionStateKey], saved[actionStateKey]);
    });

    test('reaches later steps of the same plan', () async {
      payResult.complete(const ActionSuccess({'recordId': 'e-9'}));
      final s = open(
        'root = Out(1, Action([@Pay("o-1"), @Note(), @ToAssistant("Done")]))',
      );
      await click(s);
      expect(pays.single.results, isEmpty);
      expect(notes.single.results, {
        'Pay': {'recordId': 'e-9'},
      });
      expect(events.single.results, {
        'Pay': {'recordId': 'e-9'},
      });
    });

    test('reaches a step that runs after a restore', () async {
      payResult.complete(const ActionSuccess({'recordId': 'e-9'}));
      noteResults = [const ActionFailure('busy')];
      const program = 'root = Out(1, Action([@Pay("o-1"), @Note()]))';
      final first = open(program);
      await click(first);
      final s = open(program, state: first.state);
      await click(s);
      expect(notes.last.results, {
        'Pay': {'recordId': 'e-9'},
      });
    });
  });
}
