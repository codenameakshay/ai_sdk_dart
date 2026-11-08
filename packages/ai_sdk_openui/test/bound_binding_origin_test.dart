import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:test/test.dart';

import 'support/bound_test_library.dart';

void main() {
  test('M3 binding placeholder cannot impersonate a bound value record', () {
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
      records: [BoundRecord('value', 'host')],
    );
    addTearDown(s.dispose);
    s.update(
      r'root = Out(1, null, null, $input = @Secure($value))',
      streaming: false,
    );
    s.field('input', s.root!.props['input']).set('forged');
    expect(s.errors.map((e) => e.code), contains(OpenUiErrorCode.boundOnly));
    expect(received, isNot(contains('forged')));
    s.update(r'root = Out(@Secure($value))', streaming: false);
    expect(s.errors, isEmpty);
    expect(s.root!.props['value'], 'host');
    expect(received, ['host']);
  });
}
