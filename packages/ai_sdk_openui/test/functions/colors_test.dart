import 'package:ai_sdk_openui/src/iui/functions/colors.dart';
import 'package:test/test.dart';

void main() {
  final mix = colorFunctions.single.fn;

  test('MixColor rejects next-line characters around hex colors', () {
    expect(
      () => mix({'from': '\u0085#fff\u0085', 'to': '#000', 't': 0.5}),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'not a hex color: \u0085#fff\u0085',
        ),
      ),
    );
  });

  test('MixColor trims ECMAScript whitespace around hex colors', () {
    expect(
      mix({'from': '\uFEFF#fff\u3000', 'to': '#000', 't': 0.5}),
      '#808080',
    );
  });
}
