import 'dart:convert';

import 'package:ai_sdk_openui/src/lang/ast.dart';
import 'package:ai_sdk_openui/src/lang/js.dart';
import 'package:ai_sdk_openui/src/lang/lexer.dart';
import 'package:ai_sdk_openui/src/runtime/evaluator.dart';
import 'package:test/test.dart';

void main() {
  test('truthy follows JavaScript for numbers and strings', () {
    expect(Js.truthy(0), isFalse);
    expect(Js.truthy(-0.0), isFalse);
    expect(Js.truthy(double.nan), isFalse);
    expect(Js.truthy(0.5), isTrue);
    expect(Js.truthy(-3), isTrue);
    expect(Js.truthy(''), isFalse);
    expect(Js.truthy('0'), isTrue);
    expect(Js.truthy('false'), isTrue);
    expect(Js.truthy(null), isFalse);
    expect(Js.truthy(false), isFalse);
    expect(Js.truthy(<Object?>[]), isTrue);
    expect(Js.truthy(<String, Object?>{}), isTrue);
  });

  test('jsNumber reads values as JavaScript Number() does', () {
    expect(jsNumber('42'), 42);
    expect(jsNumber(' 0x10 '), 16);
    expect(jsNumber(true), 1);
    expect(jsNumber(null), 0);
    expect(jsNumber('abc').isNaN, isTrue);
  });

  group('Number(string)', () {
    test('does not treat next-line characters as numeric whitespace', () {
      expect(Js.number('\u00851\u0085').isNaN, true);
      expect(Js.number('\u0085').isNaN, true);
      expect(Js.number('\u00a01\ufeff'), 1);
    });

    test('parses hex, octal and binary literals', () {
      expect(Js.number('0x1f'), 31);
      expect(Js.number('0XFF'), 255);
      expect(Js.number('0o17'), 15);
      expect(Js.number('0b101'), 5);
    });

    test('rejects digits outside the radix and signed radix literals', () {
      expect(Js.number('0b12'), isNaN);
      expect(Js.number('0o9'), isNaN);
      expect(Js.number('-0x10'), isNaN);
      expect(Js.number('0x'), isNaN);
    });

    test('decimal forms', () {
      expect(Js.number(' 12 '), 12);
      expect(Js.number(''), 0);
      expect(Js.number('   '), 0);
      expect(Js.number('1e3'), 1000);
      expect(Js.number('.5'), 0.5);
      expect(Js.number('5.'), 5);
      expect(Js.number('+Infinity'), double.infinity);
      expect(Js.number('-Infinity'), double.negativeInfinity);
      expect(Js.number('infinity'), isNaN);
      expect(Js.number('1_000'), isNaN);
      expect(Js.number('abc'), isNaN);
    });
  });

  test('Number(value) for non-strings', () {
    expect(Js.number(null), 0);
    expect(Js.number(true), 1);
    expect(Js.number(false), 0);
    expect(Js.number(7), 7);
    expect(Js.number(<Object?>[]), 0);
    expect(Js.number(['5']), 5);
    expect(
      Js.number([
        <Object?>[7],
      ]),
      7,
    );
    expect(Js.number([1, 2]), isNaN);
    expect(Js.number(<String, Object?>{}), isNaN);
  });

  test('toNumber maps NaN to 0 and booleans to 1 or 0', () {
    expect(Js.toNumber('12'), 12);
    expect(Js.toNumber('abc'), 0);
    expect(Js.toNumber(double.nan), isNaN);
    expect(Js.toNumber(true), 1);
    expect(Js.toNumber(false), 0);
    expect(Js.toNumber(null), 0);
    expect(Js.toNumber(<Object?>[1]), 0);
  });

  group('String(value)', () {
    test('lists join with commas and null items are empty', () {
      expect(Js.string([1, null, 'a', true]), '1,,a,true');
      expect(
        Js.string([
          1,
          [2, 3],
        ]),
        '1,2,3',
      );
      expect(Js.string(<Object?>[]), '');
    });

    test('objects and numbers', () {
      expect(Js.string(<String, Object?>{'a': 1}), '[object Object]');
      expect(Js.string(null), 'null');
      expect(Js.string(-0.0), '0');
      expect(Js.string(4.0), '4');
      expect(Js.string(1.5), '1.5');
      expect(Js.string(double.nan), 'NaN');
      expect(Js.string(double.negativeInfinity), '-Infinity');
      expect(Js.string(1e21), '1e+21');
      expect(Js.string(1e-7), '1e-7');
    });

    test('jsString is the public form of String(value)', () {
      expect(jsString(4), '4');
      expect(jsString(2.5), '2.5');
      expect(jsString(['a', 1]), 'a,1');
    });

    test(
      'a large whole double prints its shortest digits, padded with zeros',
      () {
        expect(Js.string(1.2345678901234568e20), '123456789012345680000');
      },
    );
  });

  group('looseEquals (==)', () {
    test('null equals only null', () {
      expect(Js.looseEquals(null, null), isTrue);
      expect(Js.looseEquals(null, 0), isFalse);
      expect(Js.looseEquals('', null), isFalse);
      expect(Js.looseEquals(false, null), isFalse);
    });

    test('booleans compare as numbers', () {
      expect(Js.looseEquals(true, 1), isTrue);
      expect(Js.looseEquals(true, '1'), isTrue);
      expect(Js.looseEquals('0', false), isTrue);
      expect(Js.looseEquals(false, ''), isTrue);
      expect(Js.looseEquals(true, 2), isFalse);
      expect(Js.looseEquals('abc', true), isFalse);
      expect(Js.looseEquals(true, true), isTrue);
      expect(Js.looseEquals(true, false), isFalse);
    });

    test('numbers and strings compare numerically', () {
      expect(Js.looseEquals(1, '1'), isTrue);
      expect(Js.looseEquals('1.0', 1), isTrue);
      expect(Js.looseEquals(' 12 ', 12), isTrue);
      expect(Js.looseEquals(0, ''), isTrue);
      expect(Js.looseEquals('abc', 1), isFalse);
      expect(Js.looseEquals(double.nan, double.nan), isFalse);
    });

    test('lists and objects convert to strings against primitives', () {
      expect(Js.looseEquals([1, 2], '1,2'), isTrue);
      expect(Js.looseEquals('1,2', [1, 2]), isTrue);
      expect(Js.looseEquals([1], 1), isTrue);
      expect(Js.looseEquals(<Object?>[], 0), isTrue);
      expect(Js.looseEquals(<Object?>[], false), isTrue);
      expect(Js.looseEquals([0], false), isTrue);
      expect(Js.looseEquals(<String, Object?>{}, '[object Object]'), isTrue);
      expect(Js.looseEquals([2], 1), isFalse);
    });

    test('lists and objects otherwise compare by identity', () {
      final a = [1];
      expect(Js.looseEquals(a, a), isTrue);
      expect(Js.looseEquals([1], [1]), isFalse);
      expect(Js.looseEquals(<String, Object?>{}, <String, Object?>{}), isFalse);
      expect(Js.looseEquals(null, <Object?>[]), isFalse);
    });
  });

  test('strictEquals never coerces', () {
    expect(Js.strictEquals(1, '1'), isFalse);
    expect(Js.strictEquals(1, 1.0), isTrue);
    expect(Js.strictEquals(null, null), isTrue);
    expect(Js.strictEquals(null, false), isFalse);
    expect(Js.strictEquals(double.nan, double.nan), isFalse);
    expect(Js.strictEquals([1], [1]), isFalse);
  });

  test('sameValueZero treats NaN as equal and 0 as -0', () {
    expect(Js.sameValueZero(double.nan, double.nan), isTrue);
    expect(Js.sameValueZero(0, -0.0), isTrue);
    expect(Js.sameValueZero(1, 2), isFalse);
    expect(Js.sameValueZero(1, '1'), isFalse);
    expect(Js.sameValueZero(null, null), isTrue);
  });

  test('Object.is separates 0 from -0 and equates NaN', () {
    expect(Js.objectIs(double.nan, double.nan), isTrue);
    expect(Js.objectIs(0, -0.0), isFalse);
    expect(Js.objectIs(-0.0, -0.0), isTrue);
    expect(Js.objectIs(0, 0.0), isTrue);
    expect(Js.objectIs(1, 1), isTrue);
    expect(Js.objectIs(1, 2), isFalse);
    expect(Js.objectIs('a', 'a'), isTrue);
    expect(Js.objectIs(null, null), isTrue);
  });

  test('JSON.stringify writes non-finite numbers as null', () {
    expect(Js.stringify(double.nan), 'null');
    expect(Js.stringify(double.infinity), 'null');
    expect(
      Js.stringify([
        1.0,
        1.5,
        -0.0,
        double.nan,
        'a',
        null,
        true,
        {'k': double.negativeInfinity, 'n': 2.0},
      ]),
      '[1,1.5,0,null,"a",null,true,{"k":null,"n":2}]',
    );
    expect(Js.stringify(1e21), '1e+21');
    expect(Js.stringify(Object()), 'null');
  });

  test('JSON.stringify prints numbers as JavaScript does', () {
    expect(
      Js.stringify([
        3.0,
        -0.0,
        9007199254740992.0,
        1e21,
        123456789012345680000.0,
        0.1,
      ]),
      '[3,0,9007199254740992,1e+21,123456789012345680000,0.1]',
    );
  });

  test('JSON.stringify orders index keys in raw nested maps', () {
    expect(
      Js.stringify({
        'z': {'2': 'two', '1': 'one', 'a': true},
        '2': 2,
        '1': 1,
        '01': 'kept',
        '4294967295': 'not an index',
        '4294967294': 'last index',
      }),
      '{"1":1,"2":2,"4294967294":"last index",'
      '"z":{"1":"one","2":"two","a":true},'
      '"01":"kept","4294967295":"not an index"}',
    );
  });

  test('String(number) of an int past 2^53 prints the nearest double', () {
    expect(
      Js.numberToString(int.parse('9007199254740993')),
      '9007199254740992',
    );
  });

  test('JSON.stringify writes an AST node as lang-core\'s object', () {
    expect(
      Js.stringify(
        parseExpression(
          tokenize(
            r'@Foo(a.b, c[1], !d, e ? 1 : "s", [true, null], {k: $v}, $v = 2, -1)',
          ),
        ),
      ),
      r'{"k":"Comp","name":"Foo","args":[{"k":"Member","obj":{"k":"Ref","n":"a"},"field":"b"},{"k":"Index","obj":{"k":"Ref","n":"c"},"index":{"k":"Num","v":1}},{"k":"UnaryOp","op":"!","operand":{"k":"Ref","n":"d"}},{"k":"Ternary","cond":{"k":"Ref","n":"e"},"then":{"k":"Num","v":1},"else":{"k":"Str","v":"s"}},{"k":"Arr","els":[{"k":"Bool","v":true},{"k":"Null"}]},{"k":"Obj","entries":[["k",{"k":"StateRef","n":"$v"}]]},{"k":"Assign","target":"$v","value":{"k":"Num","v":2}},{"k":"Num","v":-1}],"fn":true}',
    );
  });

  test(
    'JSON.stringify writes refs, placeholders and bindings as lang-core does',
    () {
      expect(
        Js.stringify([
          const RuntimeRefNode('q', RuntimeRefType.query),
          const PlaceholderNode('x'),
          CompNode(
            'Count',
            const [ArrNode([])],
            mappedProps: const {'array': ArrNode([])},
          ),
          const ReactiveAssign(r'$x', StateRefNode(r'$value')),
          const ValueNode(1),
        ]),
        r'[{"k":"RuntimeRef","n":"q","refType":"query"},{"k":"Ph","n":"x"},'
        r'{"k":"Comp","name":"Count","args":[{"k":"Arr","els":[]}],"mappedProps":{"array":{"k":"Arr","els":[]}}},'
        r'{"__reactive":"assign","target":"$x","expr":{"k":"StateRef","n":"$value"}},'
        r'{"k":"Value","v":1}]',
      );
    },
  );

  group('JavaScript key order', () {
    test('an object lists array-index keys first, ascending', () {
      expect(
        Js.object(const [
          MapEntry('b', 1),
          MapEntry('1', 2),
          MapEntry('a', 3),
          MapEntry('0', 4),
          MapEntry('4294967295', 5),
          MapEntry('4294967294', 6),
          MapEntry('01', 7),
        ]).keys,
        ['0', '1', '4294967294', 'b', 'a', '4294967295', '01'],
      );
    });

    test('a repeated key keeps its first place and its last value', () {
      expect(
        Js.object(const [MapEntry('a', 1), MapEntry('b', 2), MapEntry('a', 3)]),
        {'a': 3, 'b': 2},
      );
    });

    test(
      'normalize orders nested maps and, for JSON, makes whole numbers ints',
      () {
        final out = Js.normalize({
          'b': 1.0,
          '1': [2.0, -0.0, 0.5],
        }, json: true);
        expect(jsonEncode(out), '{"1":[2,0,0.5],"b":1}');
      },
    );
  });

  test('typeof', () {
    expect(Js.typeOf(null), 'object');
    expect(Js.typeOf('a'), 'string');
    expect(Js.typeOf(1), 'number');
    expect(Js.typeOf(true), 'boolean');
    expect(Js.typeOf([1]), 'object');
  });
}
