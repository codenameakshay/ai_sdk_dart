import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:test/test.dart';

import 'support/bound_test_library.dart';

void main() {
  for (final program in ['', r'root = Out($order.id)']) {
    test('M3 stale persisted bound key stays absent for "$program"', () {
      final s = OpenUiSession(
        boundLibrary(),
        records: [
          BoundRecord('order', {'id': 'host'}),
        ],
        initialState: const {
          r'$order': {'id': 'stale'},
        },
      );
      addTearDown(s.dispose);
      s.update(program, streaming: false);
      expect(s.state.containsKey(r'$order'), isFalse);
      if (program.isNotEmpty) expect(s.root!.props['value'], 'host');
    });
  }

  for (final formName in [null, r'$order']) {
    test('M3 named field cannot persist a bound record ($formName)', () {
      final s = OpenUiSession(
        boundLibrary(),
        records: [
          BoundRecord('order', {'id': 'host'}),
        ],
      );
      addTearDown(s.dispose);
      s.update('root = Out(1)', streaming: false);
      s.field(r'$order', null, formName: formName).set('forged');
      expect(s.state.containsKey(r'$order'), isFalse);
      s.field('ordinary', null).set('editable');
      expect(s.state['ordinary'], {'value': 'editable'});
    });
  }

  for (final formName in [null, r'$order']) {
    test('M3 default field cannot persist a bound record ($formName)', () {
      final s = OpenUiSession(
        boundLibrary(),
        records: [
          BoundRecord('order', {'id': 'host'}),
        ],
      );
      addTearDown(s.dispose);
      s.update('root = Out(1)', streaming: false);
      s.setDefaultValue(r'$order', 'forged', formName: formName);
      expect(s.state.containsKey(r'$order'), isFalse);
      s.setDefaultValue('ordinary', 'seed');
      expect(s.state['ordinary'], {'value': 'seed'});
    });
  }

  for (final expression in [r'$order', r'$order = $value']) {
    test('M3 two-way bound write is a no-op: $expression', () {
      final s = OpenUiSession(
        boundLibrary(),
        records: [BoundRecord('order', 'host')],
      );
      addTearDown(s.dispose);
      s.update('root = Out(1, null, null, $expression)', streaming: false);
      final field = s.field('input', s.root!.props['input']);
      expect(field.value, 'host');
      field.set('forged');
      expect(s.field('input', s.root!.props['input']).value, 'host');
      expect(s.state.containsKey(r'$order'), isFalse);
    });
  }
}
