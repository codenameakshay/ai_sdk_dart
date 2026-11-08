import 'package:ai_sdk_openui/src/lang/js.dart';
import 'package:ai_sdk_openui/src/lang/lexer.dart';
import 'package:test/test.dart';

void main() {
  test('numeric literals preserve negative zero', () {
    expect((tokenize('-0').first.v as num).isNegative, true);
    expect((tokenize('-0.0').first.v as num).isNegative, true);
    expect((tokenize('-0e2').first.v as num).isNegative, true);
    expect((tokenize('0').first.v as num).isNegative, false);
  });

  test('Number converts arrays through their comma-joined string', () {
    expect(Js.number([true]), isNaN);
    expect(Js.number([false]), isNaN);
    expect(
      Js.number([
        [true],
      ]),
      isNaN,
    );
    expect(Js.number([null]), 0);
    expect(
      Js.number([
        ['12'],
      ]),
      12,
    );
    expect(Js.number([1, 2]), isNaN);
  });

  test('Number accepts radix literals larger than a Dart int', () {
    expect(Js.number('0xffffffffffffffff'), 18446744073709552000.0);
    expect(Js.number('0x10000000000000000'), 18446744073709552000.0);
    expect(
      Js.number(
        '0b11111111111111111111111111111111111111111111111111111111111111111111111111111111',
      ),
      1.2089258196146292e24,
    );
    expect(Js.looseEquals(18446744073709552000.0, '0xffffffffffffffff'), true);
    expect(Js.toNumber('0x10000000000000000'), 18446744073709552000.0);
  });
}
