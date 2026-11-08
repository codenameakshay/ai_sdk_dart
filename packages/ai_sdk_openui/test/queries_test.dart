import 'dart:async';

import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:ai_sdk_openui/src/runtime/queries.dart';
import 'package:test/test.dart';

/// `Out(value, action)`: any value and an action, so a program can show a
/// statement's result and run steps.
final class _Out implements ComponentSpec {
  const _Out();
  @override
  String get typeName => 'Out';
  @override
  String get description => 'Test output';
  @override
  Map<String, Schema> get props => {
    'value': S.any(),
    'action': actionSchema.optional(),
    'alt': actionSchema.optional(),
  };
}

final OpenUiLibrary _library = OpenUiLibrary(
  root: const _Out(),
  components: const [_Out()],
);

Future<void> settle() => Future<void>.delayed(Duration.zero);

/// Polls until [done] holds; fails the test after two seconds.
Future<void> until(bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('condition not reached in 2s');
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

OpenUiSession open(String program, {List<OpenUiTool> tools = const []}) {
  final s = OpenUiSession(_library, tools: tools)
    ..update(program, streaming: false);
  addTearDown(s.dispose);
  return s;
}

Object? valueOf(OpenUiSession s) => s.root!.props['value'];

Future<void> click(
  OpenUiSession s, [
  void Function(ActionEvent event)? emit,
  String prop = 'action',
]) => s.run(s.root!.props.action(prop), label: '', emit: emit ?? (_) {});

/// A tool whose calls wait for the test to answer them.
final class _Gate {
  final List<Map<String, Object?>> calls = [];
  final List<Completer<Object?>> _pending = [];

  OpenUiTool tool(String name) => OpenUiTool(
    name: name,
    call: (args) {
      calls.add(args);
      final c = Completer<Object?>();
      _pending.add(c);
      return c.future;
    },
  );

  void answer(int call, Object? data) => _pending[call].complete(data);
  void fail(int call, Object error) => _pending[call].completeError(error);
}

void main() {
  group('ToolNotFoundError', () {
    test('names the tool and the tools that exist', () {
      expect(
        const ToolNotFoundError('nope', ['a', 'b']).toString(),
        '[openui] No handler for tool "nope". Available: a, b',
      );
    });

    test('says when no tool exists', () {
      expect(
        const ToolNotFoundError('nope').toString(),
        '[openui] No handler for tool "nope". Available: (none)',
      );
    });
  });

  group('Mutation', () {
    const program =
        'root = Out(m, Action([@Run(m), @ToAssistant("done")]))\n'
        'm = Mutation("save", {name: \$name})\n'
        '\$name = "Ana"';

    test(
      'is idle, then loading, then success with the tool data; the tool gets the evaluated args',
      () async {
        final gate = _Gate();
        final s = open(program, tools: [gate.tool('save')]);
        final events = <ActionEvent>[];
        expect(valueOf(s), {'status': 'idle'});

        final running = click(s, events.add);
        expect(valueOf(s), {'status': 'loading'});
        expect(events, isEmpty);

        gate.answer(0, {'id': 7});
        await running;
        expect(gate.calls, [
          {'name': 'Ana'},
        ]);
        expect(valueOf(s), {
          'status': 'success',
          'data': {'id': 7},
        });
        expect(s.issues, isEmpty);
        expect(events.single.humanFriendlyMessage, 'done');
      },
    );

    test(
      'a failure shows the error and stops the plan; the next run can succeed',
      () async {
        final gate = _Gate();
        final s = open(program, tools: [gate.tool('save')]);
        final events = <ActionEvent>[];

        final first = click(s, events.add);
        gate.fail(0, Exception('down'));
        await first;
        expect(valueOf(s), {'status': 'error', 'error': 'down'});
        expect(s.issues, ['Mutation "save" failed: down']);
        expect(events, isEmpty);

        final second = click(s, events.add);
        gate.answer(1, 'ok');
        await second;
        expect(valueOf(s), {'status': 'success', 'data': 'ok'});
        expect(s.issues, isEmpty);
        expect(events.single.humanFriendlyMessage, 'done');
      },
    );

    test('a tool the host does not have reports the tools it has', () async {
      final s = open(
        program,
        tools: [OpenUiTool(name: 'other', call: (_) async => 1)],
      );
      final events = <ActionEvent>[];
      await click(s, events.add);
      expect(valueOf(s), {
        'status': 'error',
        'error': '[openui] No handler for tool "save". Available: other',
      });
      expect(s.issues, ['Mutation tool "save" not found']);
      expect(events, isEmpty);
    });

    test('without any tools a run stops the plan and leaves it idle', () async {
      final s = open(program);
      final events = <ActionEvent>[];
      await click(s, events.add);
      expect(valueOf(s), {'status': 'idle'});
      expect(events, isEmpty);
    });

    test('a second run while it loads is ignored and halts its plan', () async {
      final gate = _Gate();
      final s = open(
        'root = Out(m, Action([@Run(m), @Set(\$n, \$n + 1)]))\n'
        'm = Mutation("save", {})\n'
        '\$n = 0',
        tools: [gate.tool('save')],
      );
      final first = click(s);
      await click(s);
      expect(gate.calls, hasLength(1));
      expect(s.state[r'$n'], 0);

      gate.answer(0, null);
      await first;
      expect(s.state[r'$n'], 1);
      expect(gate.calls, hasLength(1));
    });

    test(
      'disposing while it runs drops the result and the rest of the plan',
      () async {
        final gate = _Gate();
        final s = open(program, tools: [gate.tool('save')]);
        final events = <ActionEvent>[];
        final running = click(s, events.add);
        s.dispose();
        gate.answer(0, 'late');
        await running;
        expect(events, isEmpty);
      },
    );

    test('disposing on mutation loading prevents its tool call', () async {
      final calls = <String>[];
      final events = <ActionEvent>[];
      final s = open(
        program,
        tools: [
          OpenUiTool(
            name: 'save',
            call: (_) async {
              calls.add('save');
              return 'saved';
            },
          ),
        ],
      );
      s.listen(() {
        if ((valueOf(s) as Map)['status'] == 'loading') s.dispose();
      });
      await click(s, events.add);
      expect(calls, <String>[]);
      expect(events, <ActionEvent>[]);
    });

    test(
      'a new tool name resets the result to idle and clears the error',
      () async {
        final gate = _Gate();
        final s = open(
          'root = Out(m, @Run(m), @Set(\$tool, "b"))\n'
          'm = Mutation(\$tool, {})\n'
          '\$tool = "a"',
          tools: [gate.tool('a'), gate.tool('b')],
        );
        final running = click(s);
        gate.fail(0, Exception('down'));
        await running;
        expect(valueOf(s), {'status': 'error', 'error': 'down'});
        expect(s.issues, ['Mutation "a" failed: down']);

        await click(s, null, 'alt');
        expect(s.state[r'$tool'], 'b');
        expect(valueOf(s), {'status': 'idle', 'data': null, 'error': null});
        expect(s.issues, isEmpty);
      },
    );

    test('the same tool name keeps the result across re-evaluation', () async {
      final gate = _Gate();
      final s = open(
        'root = Out(m, @Run(m), @Set(\$x, 1))\n'
        'm = Mutation("a", {})\n'
        '\$x = 0',
        tools: [gate.tool('a')],
      );
      final running = click(s);
      gate.answer(0, 'kept');
      await running;
      await click(s, null, 'alt');
      expect(s.state[r'$x'], 1);
      expect(valueOf(s), {'status': 'success', 'data': 'kept'});
    });
  });

  group('Query', () {
    test('disposing on query loading prevents its tool call', () async {
      final calls = <String>[];
      final reports = <List<OpenUiError>>[];
      final s = OpenUiSession(
        _library,
        tools: [
          OpenUiTool(
            name: 't',
            call: (_) async {
              calls.add('t');
              return 1;
            },
          ),
        ],
        onError: reports.add,
      );
      addTearDown(s.dispose);
      s.listen(() {
        if (s.isQueryLoading) s.dispose();
      });
      s.update('root = Out(q)\nq = Query("t", {}, 0)', streaming: false);
      await settle();
      expect(calls, <String>[]);
      expect(reports, <List<OpenUiError>>[]);
    });

    test(
      'does not fetch again while its data is settled or its fetch is in flight',
      () async {
        final gate = _Gate();
        final s = open(
          'root = Out(q.n + \$x, @Set(\$x, \$x + 1))\n'
          'q = Query("t", {}, {n: 0})\n'
          '\$x = 0',
          tools: [gate.tool('t')],
        );
        expect(valueOf(s), 0);
        await click(s);
        expect(valueOf(s), 1);
        expect(gate.calls, hasLength(1));

        gate.answer(0, {'n': 10});
        await settle();
        expect(valueOf(s), 11);
        await click(s);
        expect(valueOf(s), 12);
        expect(gate.calls, hasLength(1));
      },
    );

    test(
      'an answer for args that changed since is dropped; the newest args win',
      () async {
        final gate = _Gate();
        final s = open(
          'root = Out(q, @Set(\$k, \$k + 1))\n'
          'q = Query("t", {k: \$k}, {n: 0})\n'
          '\$k = 1',
          tools: [gate.tool('t')],
        );
        await click(s);
        expect(gate.calls, [
          {'k': 1},
          {'k': 2},
        ]);

        gate.answer(0, {'n': 10});
        await settle();
        expect(valueOf(s), {'n': 0});
        expect(s.isQueryLoading, isTrue);

        gate.answer(1, {'n': 20});
        await settle();
        expect(valueOf(s), {'n': 20});
        expect(s.isQueryLoading, isFalse);
      },
    );

    test('shows the previous args data until the new data arrives', () async {
      final gate = _Gate();
      final s = open(
        'root = Out(q, @Set(\$k, \$k + 1))\n'
        'q = Query("t", {k: \$k}, {n: 0})\n'
        '\$k = 1',
        tools: [gate.tool('t')],
      );
      gate.answer(0, {'n': 10});
      await settle();
      expect(valueOf(s), {'n': 10});

      await click(s);
      expect(valueOf(s), {'n': 10});
      gate.answer(1, {'n': 20});
      await settle();
      expect(valueOf(s), {'n': 20});
    });

    test(
      '@Run refetches it, and queues one more fetch if one is in flight',
      () async {
        final gate = _Gate();
        final s = open(
          'root = Out(q.n, @Run(q))\n'
          'q = Query("t", {}, {n: 0})',
          tools: [gate.tool('t')],
        );
        await click(s);
        await click(s);
        expect(gate.calls, hasLength(1));

        gate.answer(0, {'n': 1});
        await settle();
        expect(gate.calls, hasLength(2));
        expect(valueOf(s), 1);

        gate.answer(1, {'n': 2});
        await settle();
        expect(valueOf(s), 2);
        await click(s);
        expect(gate.calls, hasLength(3));
        gate.answer(2, {'n': 3});
        await settle();
        expect(valueOf(s), 3);
      },
    );

    test('a query dropped from the program loses its cache', () async {
      final gate = _Gate();
      final s = open(
        'root = Out(q, @Set(\$k, \$k + 1))\n'
        'q = Query("t", {k: \$k}, {n: 0})\n'
        '\$k = 1',
        tools: [gate.tool('t')],
      );
      gate.answer(0, {'n': 10});
      await settle();
      await click(s);
      expect(gate.calls, [
        {'k': 1},
        {'k': 2},
      ]);

      s.update('root = Out(1)', streaming: false);
      s.update(
        'root = Out(q)\nq = Query("t", {k: 1}, {n: 0})',
        streaming: false,
      );
      expect(valueOf(s), {'n': 0});
      expect(gate.calls, hasLength(3));
      expect(gate.calls.last, {'k': 1});

      gate.answer(1, {'n': 20});
      gate.answer(2, {'n': 30});
      await settle();
      expect(valueOf(s), {'n': 30});
    });

    test(
      'a failure keeps the defaults; retryQueries fetches it again',
      () async {
        final gate = _Gate();
        final s = open(
          'root = Out(q)\nq = Query("t", {}, {n: 0})',
          tools: [gate.tool('t')],
        );
        gate.fail(0, Exception('boom'));
        await settle();
        expect(valueOf(s), {'n': 0});
        expect(s.issues, ['Query "t" failed: boom']);

        s.retryQueries();
        expect(s.isQueryLoading, isTrue);
        gate.answer(1, {'n': 5});
        await settle();
        expect(valueOf(s), {'n': 5});
        expect(s.issues, isEmpty);
        expect(gate.calls, hasLength(2));
      },
    );

    test(
      'retryQueries with nothing failed fetches every Query again',
      () async {
        final gate = _Gate();
        final s = open(
          'root = Out(q)\nq = Query("t", {}, {n: 0})',
          tools: [gate.tool('t')],
        );
        gate.answer(0, {'n': 1});
        await settle();
        s.retryQueries();
        expect(gate.calls, hasLength(2));
        gate.answer(1, {'n': 2});
        await settle();
        expect(valueOf(s), {'n': 2});
      },
    );

    test('retryQueries leaves a failed Mutation alone', () async {
      final gate = _Gate();
      final s = open(
        'root = Out(m, @Run(m))\nm = Mutation("t", {})',
        tools: [gate.tool('t')],
      );
      final running = click(s);
      gate.fail(0, Exception('no'));
      await running;
      s.retryQueries();
      await settle();
      expect(gate.calls, hasLength(1));
      expect(s.issues, ['Mutation "t" failed: no']);
    });

    test(
      'statements sharing a failed fetch report one error and retry it once',
      () async {
        final gate = _Gate();
        final s = open(
          'root = Out([a, b])\na = Query("t", {}, 0)\nb = Query("t", {}, 0)',
          tools: [gate.tool('t')],
        );
        expect(gate.calls, hasLength(1));
        gate.fail(0, Exception('boom'));
        await settle();
        expect(
          [for (final e in s.queryErrors) e.toJson()],
          [
            {
              'source': 'query',
              'code': 'tool-error',
              'message': 'Query "t" failed: boom',
              'statementId': 'a',
              'component': 'Query',
              'toolName': 't',
            },
          ],
        );

        s.retryQueries();
        expect(gate.calls, hasLength(2));
        gate.answer(1, 5);
        await settle();
        expect(valueOf(s), [5, 5]);
        expect(s.queryErrors, isEmpty);
        expect(gate.calls, hasLength(2));
      },
    );

    test(
      'args naming another statement read null, and every query is still fetched',
      () async {
        final gate = _Gate();
        open(
          'root = Out(b)\n'
          'a = Query("a", {}, {id: 3})\n'
          'b = Query("b", {from: a.id, other: missing}, {})',
          tools: [gate.tool('a'), gate.tool('b')],
        );
        await settle();
        expect(gate.calls, [
          {},
          {'from': null, 'other': null},
        ]);
      },
    );

    test(
      'refreshes on its interval while the previous fetch is not in flight',
      () async {
        final calls = <int>[];
        final s = open(
          'root = Out(q.n)\nq = Query("t", {}, {n: 0}, 0.01)',
          tools: [
            OpenUiTool(
              name: 't',
              call: (_) async {
                calls.add(calls.length + 1);
                return {'n': calls.length};
              },
            ),
          ],
        );
        await until(() => calls.length >= 3);
        expect(calls.take(3), [1, 2, 3]);
        await until(() => valueOf(s) == calls.length);

        s.update('root = Out(1)', streaming: false);
        final stopped = calls.length;
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(calls.length, stopped);
      },
    );

    test('a tick during a slow fetch does not start another', () async {
      final gate = _Gate();
      final s = open(
        'root = Out(q.n)\nq = Query("t", {}, {n: 0}, 0.01)',
        tools: [gate.tool('t')],
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(gate.calls, hasLength(1));

      gate.answer(0, {'n': 1});
      await until(() => gate.calls.length >= 2);
      expect(valueOf(s), 1);
      gate.answer(1, {'n': 2});
      s.dispose();
      final stopped = gate.calls.length;
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(gate.calls.length, stopped);
    });

    test('with no tools a refreshing query keeps its defaults', () async {
      final s = open('root = Out(q)\nq = Query("t", {}, {n: 0}, 0.01)');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(valueOf(s), {'n': 0});
      expect(s.issues, isEmpty);
    });
  });

  group('QueryManager', () {
    QueryNode node(String id, {Object? args = const {'k': 1}}) => QueryNode(
      statementId: id,
      toolName: 't',
      args: args,
      defaults: 'default',
    );

    test('invalidate with no ids fetches every query again', () async {
      final calls = <String>[];
      final manager =
          QueryManager((name, args) async {
            calls.add('$name${args['k']}');
            return calls.length;
          })..evaluateQueries([
            node('a'),
            node('b', args: {'k': 2}),
          ]);
      await settle();
      expect(calls, ['t1', 't2']);

      manager.invalidate();
      await settle();
      expect(calls, ['t1', 't2', 't1', 't2']);
      expect(manager.getResult('a'), 3);
      expect(manager.getResult('b'), 4);
    });

    test(
      'invalidate fetches a cache key that several statements share once',
      () async {
        var calls = 0;
        final manager = QueryManager((name, args) async => ++calls)
          ..evaluateQueries([node('a'), node('b')]);
        addTearDown(manager.dispose);
        await settle();
        expect(calls, 1);

        manager.invalidate();
        await settle();
        expect(calls, 2);
        expect(manager.getResult('a'), 2);
        expect(manager.getResult('b'), 2);
      },
    );

    test('invalidate skips ids it does not know', () async {
      var calls = 0;
      final manager = QueryManager((name, args) async => ++calls)
        ..evaluateQueries([node('a')]);
      await settle();
      manager.invalidate(['nope']);
      await settle();
      expect(calls, 1);
    });

    test(
      'invalidate does nothing without a tool caller or after dispose',
      () async {
        final bare = QueryManager(null)..evaluateQueries([node('a')]);
        bare.invalidate();
        expect(bare.getResult('a'), 'default');

        var calls = 0;
        final manager = QueryManager((name, args) async => ++calls)
          ..evaluateQueries([node('a')]);
        await settle();
        manager
          ..dispose()
          ..invalidate();
        await settle();
        expect(calls, 1);
      },
    );

    test('a listener hears every change until it is cancelled', () async {
      var heard = 0;
      final manager = QueryManager((name, args) async => 'data');
      final cancel = manager.subscribe(() => heard++);
      manager.evaluateQueries([node('a')]);
      await settle();
      expect(manager.getResult('a'), 'data');
      expect(heard, 2);

      cancel();
      manager.invalidate();
      await settle();
      expect(heard, 2);
    });
  });

  // Ported from lang-core 1.0.0 runtime/__tests__/queryManager.test.ts, with a 10 ms interval for 5 s.
  group('QueryManager refresh interval lifecycle', () {
    QueryNode node(String id, Object? refresh) => QueryNode(
      statementId: id,
      toolName: 'get_data',
      args: const {},
      defaults: const {},
      refreshInterval: refresh,
    );

    test(
      're-creates the refresh timer after dispose and re-evaluate',
      () async {
        var calls = 0;
        final manager = QueryManager((_, _) async {
          calls++;
          return {'ok': true};
        })..evaluateQueries([node('q1', 0.01)]);
        await settle();
        manager
          ..dispose()
          ..activate()
          ..evaluateQueries([node('q1', 0.01)]);
        await settle();
        final before = calls;
        await Future<void>.delayed(const Duration(milliseconds: 40));
        expect(calls, greaterThan(before));
        manager.dispose();
      },
    );

    test('clears the timer when the interval is removed', () async {
      var calls = 0;
      final manager = QueryManager((_, _) async {
        calls++;
        return {'ok': true};
      })..evaluateQueries([node('q1', 0.01)]);
      await settle();
      manager.evaluateQueries([node('q1', 0)]);
      await settle();
      final before = calls;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(calls, before);
      manager.dispose();
    });
  });
}
