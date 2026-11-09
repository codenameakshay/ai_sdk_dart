import 'dart:async';

import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:ai_sdk_openui/src/runtime/host_actions.dart';
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

final _outProps = <String, Schema>{
  'value': S.any(),
  'action': actionSchema.optional(),
};

const _payProgram = 'root = Out(1, @Pay("o-1"))';

/// `actionBaseKey('', 'Pay', {'orderId': 'o-1'})`: the JSON `["","","Pay",{"orderId":"o-1"}]`.
const _payBase = '3ad08ff935776d83';

final _calls = <ActionInvocation>[];
var _results = <ActionResult>[];
Completer<void>? _gate;
final _events = <ActionEvent>[];

ActionSpec _pay({
  String? confirm,
  bool disable = false,
  bool throws = false,
  Map<String, Schema>? params,
}) => ActionSpec(
  'Pay',
  description: 'Pays an order',
  params: params ?? {'orderId': S.string()},
  confirm: confirm,
  disableAfterSuccess: disable,
  handler: (i) async {
    _calls.add(i);
    await _gate?.future;
    if (throws) throw StateError('boom');
    return _results.isEmpty ? const ActionSuccess() : _results.removeAt(0);
  },
);

OpenUiSession _session(
  List<ActionSpec> actions,
  String program, {
  String scope = '',
  Map<String, Object?> state = const {},
  void Function(Map<String, Object?> state)? onStateUpdate,
}) {
  final library = OpenUiLibrary(
    root: _Spec('Out', _outProps),
    components: [_Spec('Out', _outProps)],
    actions: actions,
  );
  final s = OpenUiSession(
    library,
    actionScope: scope,
    initialState: state,
    onStateUpdate: onStateUpdate,
  )..update(program, streaming: false);
  addTearDown(s.dispose);
  return s;
}

OpenUiSession _open(
  ActionSpec spec, {
  String program = _payProgram,
  String scope = '',
  Map<String, Object?> state = const {},
  void Function(Map<String, Object?> state)? onStateUpdate,
}) => _session(
  [spec],
  program,
  scope: scope,
  state: state,
  onStateUpdate: onStateUpdate,
);

OpenUiAction? _action(OpenUiSession s) => s.root!.props.action('action');

ActionStatus _status(OpenUiSession s, {String nodeId = ''}) =>
    s.actionStatus(_action(s), nodeId: nodeId)!;

Future<void> _click(OpenUiSession s, {String nodeId = ''}) =>
    s.run(_action(s), label: '', emit: _events.add, nodeId: nodeId);

void main() {
  setUp(() {
    _calls.clear();
    _results = [];
    _gate = null;
    _events.clear();
  });

  group('handled actions', () {
    test('a handled action runs its handler with an idempotency key', () async {
      final s = _open(_pay());
      await _click(s);
      expect(_calls.single.params, {'orderId': 'o-1'});
      expect(_calls.single.idempotencyKey, '$_payBase-1');
      expect(_calls.single.attempt, 1);
      expect(_status(s).phase, ActionPhase.done);
      expect(_events, isEmpty);
    });

    test('a running action is pending and ignores another click', () async {
      _gate = Completer<void>();
      final s = _open(_pay());
      final running = _click(s);
      expect(_status(s).phase, ActionPhase.pending);
      expect(_status(s).disabled, isTrue);
      await _click(s);
      expect(_calls, hasLength(1));
      _gate!.complete();
      await running;
      expect(_status(s).phase, ActionPhase.done);
    });

    test('a failure keeps the key for the retry', () async {
      _results = [const ActionFailure('Card declined')];
      final s = _open(_pay());
      await _click(s);
      expect(_status(s).phase, ActionPhase.failed);
      expect(_status(s).message, 'Card declined');
      expect(_status(s).disabled, isFalse);
      await _click(s);
      expect(_calls[1].idempotencyKey, '$_payBase-1');
      expect(_status(s).phase, ActionPhase.done);
    });

    test('a repeat after success gets a new key', () async {
      final s = _open(_pay());
      await _click(s);
      await _click(s);
      expect(_calls.map((c) => c.idempotencyKey), [
        '$_payBase-1',
        '$_payBase-2',
      ]);
    });

    test('disableAfterSuccess stops repeats', () async {
      final s = _open(_pay(disable: true));
      await _click(s);
      await _click(s);
      expect(_calls, hasLength(1));
      expect(_status(s).disabled, isTrue);
    });

    test('a throwing handler fails with its message', () async {
      final s = _open(_pay(throws: true));
      await _click(s);
      expect(_status(s).phase, ActionPhase.failed);
      expect(_status(s).message, 'boom');
    });

    test('a confirm action waits for confirmation', () async {
      final s = _open(_pay(confirm: 'Pay this order?'));
      await _click(s);
      expect(_calls, isEmpty);
      expect(_status(s).confirm, 'Pay this order?');
      await s.run(_action(s), label: '', emit: _events.add, confirmed: true);
      expect(_calls, hasLength(1));
    });

    test('a failed action stops the plan', () async {
      final program =
          r'$paid = false'
          '\n'
          r'root = Out($paid, Action([@Pay("o-1"), @Set($paid, true)]))';
      _results = [const ActionFailure('no')];
      final s = _open(_pay(), program: program);
      await _click(s);
      expect(s.root!.props['value'], isFalse);
    });

    test('a successful action runs the rest of the plan', () async {
      final program =
          r'$paid = false'
          '\n'
          r'root = Out($paid, Action([@Pay("o-1"), @Set($paid, true)]))';
      final s = _open(_pay(), program: program);
      await _click(s);
      expect(s.root!.props['value'], isTrue);
    });

    test('a handler that finishes after dispose changes nothing', () async {
      _gate = Completer<void>();
      var stateUpdates = 0;
      var listenerCalls = 0;
      final s = _open(_pay(), onStateUpdate: (_) => stateUpdates++);
      s.listen(() => listenerCalls++);
      final running = _click(s);
      final stateUpdatesAtDispose = stateUpdates;
      final listenerCallsAtDispose = listenerCalls;
      s.dispose();
      final disposedState = s.state;
      _gate!.complete();
      await running;
      expect(_events, isEmpty);
      expect(stateUpdates, stateUpdatesAtDispose);
      expect(listenerCalls, listenerCallsAtDispose);
      expect(s.state, disposedState);
    });

    test('a failed handled step stops later host steps', () async {
      final s = _session([
        _pay(),
        ActionSpec('Ping', description: '', params: {}),
      ], 'root = Out(1, Action([@Pay("o-1"), @Ping()]))');
      _results = [const ActionFailure('no')];
      await _click(s);
      expect(_events, isEmpty);
    });

    test('the handler and the host see no statuses in form state', () async {
      final s = _session([
        _pay(),
        ActionSpec('Ping', description: '', params: {}),
      ], 'root = Out(1, Action([@Pay("o-1"), @Ping()]))');
      await _click(s);
      expect(_calls.single.formState, isEmpty);
      expect(_events.single.type, 'Ping');
      expect(_events.single.formState, isEmpty);
    });

    test('an action without a handler is still an event', () async {
      final s = _session([
        _pay(),
        ActionSpec('Ping', description: '', params: {}),
      ], 'root = Out(1, @Ping())');
      await s.run(_action(s), label: '', emit: _events.add);
      expect(_events.single.type, 'Ping');
      expect(s.actionStatus(_action(s)), isNull);
      expect(_calls, isEmpty);
    });
  });

  group('key identity', () {
    test('the scope is part of the key', () async {
      final s = _open(_pay(), scope: 'msg-1');
      await _click(s);
      expect(_calls.single.idempotencyKey, '52c26a82b68da5b0-1');
    });

    test('parameter order does not change the key', () async {
      final spec = _pay(params: {'orderId': S.string(), 'note': S.string()});
      final s = _open(spec, program: 'root = Out(1, @Pay("o-1", "x"))');
      await _click(s);
      expect(_calls.single.params, {'orderId': 'o-1', 'note': 'x'});
      expect(
        _calls.single.idempotencyKey,
        '${actionBaseKey('', 'Pay', {'note': 'x', 'orderId': 'o-1'})}-1',
      );
    });

    test('nested maps and lists in parameters are key-sorted', () {
      String key(Object? items) => actionBaseKey('', 'Pay', {'items': items});
      expect(
        key([
          {'b': 1, 'a': 2},
        ]),
        key([
          {'a': 2, 'b': 1},
        ]),
      );
      expect(
        key([
          {'a': 1},
        ]),
        isNot(
          key([
            {'a': 2},
          ]),
        ),
      );
    });

    test(
      'two nodes running the same action share its key and status',
      () async {
        final s = _open(_pay(disable: true));
        await _click(s, nodeId: 'list/children.0');
        expect(_status(s, nodeId: 'list/children.1').phase, ActionPhase.done);
        expect(_status(s, nodeId: 'list/children.1').disabled, isTrue);
        await _click(s, nodeId: 'list/children.1');
        expect(_calls.single.idempotencyKey, '$_payBase-1');
      },
    );

    test('another node waits while the same plan runs', () async {
      _gate = Completer<void>();
      final s = _open(_pay());
      final running = _click(s, nodeId: 'a');
      await _click(s, nodeId: 'b');
      expect(_status(s, nodeId: 'b').phase, ActionPhase.pending);
      _gate!.complete();
      await running;
      expect(_calls, hasLength(1));
      expect(_status(s, nodeId: 'b').phase, ActionPhase.done);
    });

    test('the same node retries a failed run with the same key', () async {
      _results = [const ActionFailure('Card declined')];
      final s = _open(_pay());
      await _click(s, nodeId: 'a');
      await _click(s, nodeId: 'a');
      expect(_calls[1].idempotencyKey, _calls[0].idempotencyKey);
    });
  });

  group('restore', () {
    test('statuses survive a restore', () async {
      final first = _open(_pay(disable: true));
      await _click(first);
      final firstActionState = first.state[r'__openui_actions'] as Map;
      expect(
        firstActionState,
        containsPair(_payBase, {'phase': 'done', 'attempt': 1}),
      );
      expect((firstActionState['__plans'] as Map).values.single, {
        'phase': 'done',
        'cursor': 1,
      });
      final second = _open(_pay(disable: true), state: first.state);
      expect(_status(second).phase, ActionPhase.done);
      expect(_status(second).disabled, isTrue);
      await _click(second);
      expect(_calls, hasLength(1));
    });

    test(
      'a run cut off by a restore reads as failed and retries with its key',
      () async {
        final s = _open(
          _pay(),
          state: {
            r'__openui_actions': {
              _payBase: {'phase': 'pending', 'attempt': 1},
            },
          },
        );
        expect(_status(s).phase, ActionPhase.failed);
        expect(_status(s).message, isNull);
        await _click(s);
        expect(_calls.single.idempotencyKey, '$_payBase-1');
      },
    );

    test('a failure is saved with its message', () async {
      _results = [const ActionFailure('Card declined')];
      final s = _open(_pay());
      await _click(s);
      final saved = s.state[r'__openui_actions'] as Map;
      expect(
        saved,
        containsPair(_payBase, {
          'phase': 'failed',
          'attempt': 1,
          'message': 'Card declined',
        }),
      );
      expect((saved['__plans'] as Map).values.single, {
        'phase': 'failed',
        'cursor': 0,
        'message': 'Card declined',
      });
    });

    test('a restored failure keeps its message', () async {
      final s = _open(
        _pay(),
        state: {
          r'__openui_actions': {
            _payBase: {
              'phase': 'failed',
              'attempt': 1,
              'message': 'Card declined',
            },
          },
        },
      );
      expect(_status(s).phase, ActionPhase.failed);
      expect(_status(s).message, 'Card declined');
    });

    test('state is unchanged until a handled action runs', () {
      final fresh = _open(_pay());
      expect(fresh.state.containsKey(r'__openui_actions'), isFalse);
      final junk = _open(
        _pay(),
        state: {
          r'__openui_actions': {
            'x': 1,
            'y': {'phase': 'nope', 'attempt': 1},
            'z': {'phase': 'idle', 'attempt': 1},
            'w': {'phase': 'done'},
          },
        },
      );
      expect(junk.state.containsKey(r'__openui_actions'), isFalse);
      expect(_status(junk).phase, ActionPhase.idle);
    });
  });
}
