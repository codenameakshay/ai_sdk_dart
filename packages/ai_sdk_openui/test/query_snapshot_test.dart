import 'dart:async';

import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:ai_sdk_openui/src/runtime/queries.dart';
import 'package:test/test.dart';

Future<void> settle() => Future<void>.delayed(Duration.zero);

/// Polls until [done] holds; fails the test after two seconds.
Future<void> until(bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('condition not reached in 2s');
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

QueryNode node(
  String id, {
  Object? args = const {},
  Object? refreshInterval,
  bool complete = true,
}) => QueryNode(
  statementId: id,
  toolName: 't',
  args: args,
  defaults: null,
  refreshInterval: refreshInterval,
  complete: complete,
);

/// The JSON of the one error a Query raises when its tool throws [error].
Future<Map<String, Object?>> failWith(Object error) async {
  final manager = QueryManager((_, _) async => throw error);
  addTearDown(manager.dispose);
  manager.evaluateQueries([node('a')]);
  await settle();
  return manager.getSnapshot().errors.single.toJson();
}

void main() {
  test('a pending Query reports loading until it answers', () async {
    final pending = <Completer<Object?>>[];
    final manager = QueryManager((_, _) {
      final c = Completer<Object?>();
      pending.add(c);
      return c.future;
    });
    addTearDown(manager.dispose);

    manager.evaluateQueries([node('a')]);
    expect(manager.isLoading('a'), isTrue);
    expect(manager.isAnyLoading(), isTrue);
    expect(manager.getSnapshot().loading, ['a']);
    expect(manager.getSnapshot().refetching, isEmpty);

    pending.single.complete('x');
    await settle();
    expect(manager.isLoading('a'), isFalse);
    expect(manager.getSnapshot().loading, isEmpty);
    expect(manager.getSnapshot().data, {'a': 'x'});

    manager.invalidate(['a']);
    expect(manager.getSnapshot().refetching, ['a']);
    expect(manager.isLoading('nope'), isFalse);
  });

  test('a string refresh interval refetches the Query', () async {
    var calls = 0;
    final manager = QueryManager((_, _) async => ++calls);
    addTearDown(manager.dispose);

    manager.evaluateQueries([node('a', refreshInterval: '0.01')]);
    await until(() => calls >= 3);
  });

  test('an empty map refresh interval never refetches', () async {
    var calls = 0;
    final manager = QueryManager((_, _) async => ++calls);
    addTearDown(manager.dispose);

    manager.evaluateQueries([node('a', refreshInterval: const {})]);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(calls, 1);
  });

  test('an incomplete Query is not fetched', () {
    var calls = 0;
    final manager = QueryManager((_, _) async => ++calls);
    addTearDown(manager.dispose);

    manager.evaluateQueries([node('a', complete: false)]);
    expect(calls, 0);
    expect(manager.getResult('a'), isNull);
  });

  test('an MCP tool error is reported as an mcp-error', () async {
    expect(await failWith(const McpToolError('bad')), {
      'source': 'query',
      'code': 'mcp-error',
      'message': 'Query "t" returned an error: bad',
      'statementId': 'a',
      'component': 'Query',
      'toolName': 't',
    });
  });

  test('a missing tool is reported with the tools that exist', () async {
    expect(await failWith(const ToolNotFoundError('t', ['x', 'y'])), {
      'source': 'query',
      'code': 'tool-not-found',
      'message': 'Query tool "t" not found',
      'statementId': 'a',
      'component': 'Query',
      'toolName': 't',
      'hint': 'Available tools: x, y',
    });
  });

  test('a missing tool with no tools has no hint', () async {
    expect(await failWith(const ToolNotFoundError('t')), {
      'source': 'query',
      'code': 'tool-not-found',
      'message': 'Query tool "t" not found',
      'statementId': 'a',
      'component': 'Query',
      'toolName': 't',
    });
  });

  test('any other error is reported as a tool-error', () async {
    expect(await failWith(Exception('down')), {
      'source': 'query',
      'code': 'tool-error',
      'message': 'Query "t" failed: down',
      'statementId': 'a',
      'component': 'Query',
      'toolName': 't',
    });
  });

  test('a failed Mutation keeps its error result and reports it', () async {
    final manager = QueryManager((_, _) async => throw Exception('down'));
    addTearDown(manager.dispose);
    manager.registerMutations({'m': 't'});
    expect(manager.getMutationResult('m'), {'status': 'idle'});
    expect(manager.getResult('m'), isNull);

    expect(await manager.fireMutation('m', {}), isFalse);
    expect(manager.getMutationResult('m'), {
      'status': 'error',
      'error': 'down',
    });
    expect(manager.getSnapshot().errors.single.toJson(), {
      'source': 'mutation',
      'code': 'tool-error',
      'message': 'Mutation "t" failed: down',
      'statementId': 'm',
      'component': 'Mutation',
      'toolName': 't',
    });
  });

  test('a successful Mutation refetches the Queries it names', () async {
    var queryCalls = 0;
    final manager = QueryManager((name, _) async {
      if (name == 'save') return 'ok';
      return ++queryCalls;
    });
    addTearDown(manager.dispose);
    manager.registerMutations({'m': 'save'});
    manager.evaluateQueries([node('a')]);
    await settle();
    expect(queryCalls, 1);

    expect(await manager.fireMutation('m', {}, ['a']), isTrue);
    await settle();
    expect(queryCalls, 2);
  });

  test('a disposed manager fetches again once activated', () async {
    var calls = 0;
    final manager = QueryManager((_, _) async => ++calls);
    addTearDown(manager.dispose);
    manager.evaluateQueries([node('a')]);
    await settle();
    expect(calls, 1);

    manager.dispose();
    manager.evaluateQueries([
      node('a', args: {'k': 2}),
    ]);
    await settle();
    expect(calls, 1);

    manager.activate();
    manager.evaluateQueries([
      node('a', args: {'k': 2}),
    ]);
    await settle();
    expect(calls, 2);
  });
}
