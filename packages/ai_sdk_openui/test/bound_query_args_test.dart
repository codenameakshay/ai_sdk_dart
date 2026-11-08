import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:test/test.dart';

import 'support/bound_test_library.dart';

void main() {
  for (final statement in ['Query', 'Mutation']) {
    test(
      'streamed raw $statement retains bound-only errors after completion',
      () async {
        final received = <Object?>[];
        final s = OpenUiSession(
          boundLibrary(functions: [secureFunction(received)]),
          records: [
            BoundRecord('order', {'id': 'host'}),
          ],
          tools: [OpenUiTool(name: 'echo', call: (args) async => args)],
        );
        addTearDown(s.dispose);
        final program =
            'q = $statement("echo", {id: @Secure("forged")})\n'
            'root = Out(q, null, @Run(q))';
        s.update(program, streaming: true);
        s.update(program, streaming: false);
        await s.run(s.root!.props.action('action'), label: '', emit: (_) {});
        await Future<void>.delayed(Duration.zero);
        expect(
          s.errors.map((e) => e.code),
          contains(OpenUiErrorCode.boundOnly),
        );
        expect(received, isEmpty);
      },
    );
  }

  test('M3 Query cannot invoke a bound-only function with a literal', () async {
    final received = <Object?>[];
    final s = OpenUiSession(
      boundLibrary(
        functions: [
          FunctionSpec(
            'Secure',
            description: '',
            params: {'id': S.string().boundOnly()},
            fn: (args) {
              received.add(args['id']);
              return args['id'];
            },
          ),
        ],
      ),
      records: [
        BoundRecord('order', {'id': 'host'}),
      ],
      tools: [OpenUiTool(name: 'echo', call: (args) async => args)],
    );
    addTearDown(s.dispose);
    s.update(
      'q = Query("echo", {id: @Secure("forged")})\nroot = Out(q)',
      streaming: false,
    );
    await Future<void>.delayed(Duration.zero);
    expect(s.errors.map((e) => e.code), contains(OpenUiErrorCode.boundOnly));
    expect(received, isEmpty);
    s.update(
      r'q = Query("echo", {id: @Secure($order.id)})'
      '\nroot = Out(q)',
      streaming: false,
    );
    await Future<void>.delayed(Duration.zero);
    expect(s.errors, isEmpty);
    expect(received, ['host']);
    expect(s.root!.props['value'], {'id': 'host'});
  });

  for (final expression in ['"forged"', r'$order.id + "suffix"', r'$fake']) {
    test(
      'M3 Mutation rejects raw bound-only function arg $expression',
      () async {
        final received = <Object?>[];
        final calls = <Map<String, Object?>>[];
        final s = OpenUiSession(
          boundLibrary(functions: [secureFunction(received, optional: true)]),
          records: [
            BoundRecord('order', {'id': 'host'}),
          ],
          tools: [
            OpenUiTool(
              name: 'echo',
              call: (args) async {
                calls.add(args);
                return args;
              },
            ),
          ],
        );
        addTearDown(s.dispose);
        s.update(
          '\$fake = "forged"\nm = Mutation("echo", {id: @Secure($expression)})\n'
          'root = Out(1, null, @Run(m))',
          streaming: false,
        );
        await s.run(s.root!.props.action('action'), label: '', emit: (_) {});
        expect(
          s.errors.map((e) => e.code),
          contains(OpenUiErrorCode.boundOnly),
        );
        expect(received, isEmpty);
        s.update(
          r'm = Mutation("echo", {id: @Secure($order.id)})'
          '\n'
          'root = Out(1, null, @Run(m))',
          streaming: false,
        );
        await s.run(s.root!.props.action('action'), label: '', emit: (_) {});
        expect(s.errors, isEmpty);
        expect(received, ['host']);
        expect(calls.last, {'id': 'host'});
      },
    );

    for (final streaming in [false, true]) {
      test(
        'M3 bound-only prop/function/action reject $expression, streaming=$streaming',
        () async {
          final received = <Object?>[];
          final library = boundLibrary(
            functions: [secureFunction(received, optional: true)],
            actions: [
              ActionSpec(
                'Pay',
                description: '',
                params: {'id': S.string().boundOnly().optional()},
              ),
            ],
          );
          final s = OpenUiSession(
            library,
            records: [
              BoundRecord('order', {'id': 'host'}),
            ],
          );
          addTearDown(s.dispose);
          final program =
              '\$fake = "forged"\n'
              'root = Out(@Secure($expression), $expression, @Pay($expression))';
          expect(
            library.parse(program, bound: {r'$order'}).errors,
            hasLength(3),
          );
          s.update(program, streaming: streaming);
          expect(s.root!.props.has('amount'), isFalse);
          final events = <ActionEvent>[];
          await s.run(
            s.root!.props.action('action'),
            label: '',
            emit: events.add,
          );
          expect(received, isEmpty);
          expect(events, isEmpty);
          if (streaming) {
            expect(s.errors, isEmpty);
            s.update(program, streaming: false);
          }
          expect(
            s.errors.where((e) => e.code == OpenUiErrorCode.boundOnly),
            hasLength(3),
          );
          const valid =
              r'root = Out(@Secure($order.id), $order.id, @Pay($order.id))';
          expect(library.parse(valid, bound: {r'$order'}).errors, isEmpty);
          s.update(valid, streaming: false);
          expect(s.errors, isEmpty);
          expect(s.root!.props['value'], 'host');
          expect(s.root!.props['amount'], 'host');
          expect(received, ['host']);
          await s.run(
            s.root!.props.action('action'),
            label: '',
            emit: events.add,
          );
          expect(events.single.type, 'Pay');
          expect(events.single.params, {'id': 'host'});
        },
      );
    }
  }
}
