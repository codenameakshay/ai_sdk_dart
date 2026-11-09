import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:test/test.dart';

import 'support/bound_test_library.dart';

void main() {
  test('M3 withDefault preserves the bound-only prompt contract', () {
    final library = boundLibrary(
      functions: [
        FunctionSpec(
          'Secure',
          description: '',
          params: {'id': S.string().boundOnly().withDefault('host-default')},
          fn: (args) => args['id'],
        ),
      ],
    );
    final functionSchema =
        (library.toJsonSchema()['functions'] as Map)['Secure'];
    expect(
      functionSchema['params']['properties']['id']['x-openui-bound'],
      isTrue,
    );
    expect(
      (library.toSpec()['functions'] as Map)['Secure']['signature'],
      r'Secure(id?: $bound<string>)',
    );
  });
}
