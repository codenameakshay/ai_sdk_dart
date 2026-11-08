import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:test/test.dart';

import 'support/bound_test_library.dart';

void main() {
  test('M3 same-name inner bound loop does not capture outer literals', () {
    final s = OpenUiSession(
      boundLibrary(),
      records: [
        BoundRecord('items', [
          {'price': 5},
        ]),
      ],
    );
    addTearDown(s.dispose);
    s.update(
      r'root = Out(@Each([{price: 999}], "it", @Each($items, "it", Out(1, it.price))))',
      streaming: false,
    );
    expect(s.errors, isEmpty);
    final outer = s.root!.props['value'] as List;
    final inner = outer.single as List;
    final value = inner.single;
    expect(value.props['amount'], 5);
  });

  for (final streaming in [false, true]) {
    test(
      'nested same-name loops preserve bound list and deferred action, streaming=$streaming',
      () async {
        final library = boundLibrary(
          actions: [
            ActionSpec(
              'Pay',
              description: '',
              params: {'id': S.string().boundOnly()},
            ),
          ],
        );
        final s = OpenUiSession(
          library,
          records: [
            BoundRecord('groups', [
              {
                'items': [
                  {'id': 'host'},
                ],
              },
            ]),
          ],
        );
        addTearDown(s.dispose);
        const program =
            r'root = Out(@Each($groups, "it", @Each(it.items, "it", Out(1, it.id, @Pay(it.id)))))';
        expect(library.parse(program, bound: {r'$groups'}).errors, isEmpty);
        s.update(program, streaming: streaming);
        final outer = s.root!.props['value'] as List;
        final inner = outer.single as List;
        final value = inner.single as OpenUiElement;
        expect(value.props['amount'], 'host');
        final events = <ActionEvent>[];
        await s.run(value.props.action('action'), label: '', emit: events.add);
        expect(events.single.type, 'Pay');
        expect(events.single.params, {'id': 'host'});
        if (streaming) s.update(program, streaming: false);
        expect(s.errors, isEmpty);
      },
    );
  }
}
