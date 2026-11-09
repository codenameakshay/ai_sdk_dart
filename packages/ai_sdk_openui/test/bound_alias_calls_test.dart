import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:test/test.dart';

import 'support/bound_test_library.dart';

void main() {
  for (final statement in ['Query', 'Mutation']) {
    test('$statement function arguments accept bound aliases', () async {
      final received = <Object?>[];
      final session = OpenUiSession(
        boundLibrary(functions: [secureFunction(received)]),
        records: [
          BoundRecord('order', {'id': 'host'}),
        ],
        tools: [OpenUiTool(name: 'echo', call: (args) async => args)],
      );
      addTearDown(session.dispose);
      session.update(
        'id = \$order.id\nq = $statement("echo", {id: @Secure(id)})\nroot = Out(q, null, @Run(q))',
        streaming: false,
      );
      if (statement == 'Mutation') {
        await session.run(
          session.root!.props.action('action'),
          label: '',
          emit: (_) {},
        );
      }
      await Future<void>.delayed(Duration.zero);
      expect(session.errors, isEmpty);
      expect(received, ['host']);
    });
  }
  for (final source in [r'$ids', '["forged"]']) {
    for (final declaration in ['"id"', 'id']) {
      test(
        'query loop $declaration uses $source rather than a shadowed alias',
        () async {
          final received = <Object?>[];
          final session = OpenUiSession(
            boundLibrary(functions: [secureFunction(received)]),
            records: [
              BoundRecord('order', {'id': 'host'}),
              BoundRecord('ids', ['item']),
            ],
            tools: [OpenUiTool(name: 'echo', call: (args) async => args)],
          );
          addTearDown(session.dispose);
          session.update(
            'id = \$order.id\nitems = $source\nq = Query("echo", {ids: @Each(items, $declaration, @Secure(id))})\nroot = Out(q)',
            streaming: false,
          );
          await Future<void>.delayed(Duration.zero);
          if (source == r'$ids') {
            expect(received, ['item']);
            expect(session.errors, isEmpty);
          } else {
            expect(received, isEmpty);
            expect(
              session.errors.map((e) => e.code),
              contains(OpenUiErrorCode.boundOnly),
            );
          }
        },
      );
    }
  }
}
