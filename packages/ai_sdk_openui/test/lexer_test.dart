import 'dart:convert';

import 'package:ai_sdk_openui/src/lang/ast.dart';
import 'package:ai_sdk_openui/src/lang/lexer.dart';
import 'package:test/test.dart';

/// Token kinds, with the value where there is one.
List<Object?> toks(String src) => [
  for (final t in tokenize(src)) t.v == null ? t.t : (t.t, t.v),
];

/// The value of the only token before eof.
Object? only(String src) {
  final tokens = tokenize(src);
  expect(tokens, hasLength(2), reason: src);
  return tokens.first.v;
}

/// An s-expression for [n].
String show(Ast n) => switch (n) {
  StrNode(:final value) => jsonEncode(value),
  NumNode(:final value) => '$value',
  BoolNode(:final value) => '$value',
  NullNode() => 'null',
  RefNode(:final name) => name,
  StateRefNode(:final name) => name,
  UnaryOpNode(:final op, :final operand) => '($op ${show(operand)})',
  BinOpNode(:final op, :final left, :final right) =>
    '(${show(left)} $op ${show(right)})',
  TernaryNode(:final condition, :final then, :final otherwise) =>
    '(${show(condition)} ? ${show(then)} : ${show(otherwise)})',
  MemberNode(:final object, :final field) => '${show(object)}.$field',
  IndexNode(:final object, :final index) => '${show(object)}[${show(index)}]',
  ArrNode(:final elements) => '[${elements.map(show).join(', ')}]',
  ObjNode(:final entries) =>
    '{${entries.map((e) => '${e.$1}: ${show(e.$2)}').join(', ')}}',
  CompNode(:final name, :final args) => '$name(${args.map(show).join(', ')})',
  AssignNode(:final target, :final value) => '$target = ${show(value)}',
  PlaceholderNode(:final name) => '?$name',
  RuntimeRefNode(:final name) => name,
};

String expr(String src) => show(parseExpression(tokenize(src)));

void main() {
  group('single-quoted strings', () {
    test('keep their text and end at the closing quote', () {
      expect(toks("'hi' 'yo'"), [(T.str, 'hi'), (T.str, 'yo'), T.eof]);
    });

    test(r"decode \n and \t, and take any other escaped character as is", () {
      expect(only(r"'a\nb\tc'"), 'a\nb\tc');
      expect(only(r"'it\'s'"), "it's");
      expect(only(r"'a\\b'"), r'a\b');
      expect(only(r"""'\q\"\0'"""), 'q"0');
    });

    test('a double quote needs no escape inside', () {
      expect(only("'say \"x\"'"), 'say "x"');
    });

    test('an unterminated string takes the rest of the input', () {
      expect(only("'abc"), 'abc');
    });

    test('a trailing backslash drops silently', () {
      expect(only(r"'ab\"), 'ab');
    });

    test('stay literal in an expression', () {
      expect(expr(r"'x\ny' + 'z'"), r'("x\ny" + "z")');
    });
  });

  group('double-quoted strings', () {
    test('decode JSON escapes', () {
      expect(only(r'"a\nbA\""'), 'a\nbA"');
    });

    test('an unterminated string is closed for decoding', () {
      expect(only('"abc'), 'abc');
    });

    test('an invalid escape falls back to the raw text between quotes', () {
      expect(only(r'"a\qb"'), r'a\qb');
    });
  });

  group('numbers', () {
    test('exponents scale the value', () {
      expect(only('1e3'), 1000);
      expect(only('1E3'), 1000);
      expect(only('1e+2'), 100);
      expect(only('5e-1'), 0.5);
      expect(only('2.5E-2'), 0.025);
    });

    test('an exponent with no digits is NaN, as +"1e" is in JavaScript', () {
      expect((only('1e') as num).isNaN, isTrue);
      expect((only('1E+') as num).isNaN, isTrue);
    });

    test('a dot needs a digit after it to join the number', () {
      expect(toks('1.'), [(T.num, 1), T.dot, T.eof]);
      expect(toks('1.5'), [(T.num, 1.5), T.eof]);
    });

    test('whole values lex as integers', () {
      expect(only('10'), isA<int>());
      expect(only('1e2'), isA<int>());
      expect(only('1.5'), isA<double>());
    });
  });

  group('negative numbers', () {
    test('a minus before a digit starts a literal at the start of input', () {
      expect(toks('-5'), [(T.num, -5), T.eof]);
      expect(toks('-1.5e2'), [(T.num, -150), T.eof]);
    });

    test('a minus after a value is the subtraction operator', () {
      expect(toks('a-1'), [(T.ident, 'a'), T.minus, (T.num, 1), T.eof]);
      expect(toks('3 -2'), [(T.num, 3), T.minus, (T.num, 2), T.eof]);
      expect(toks('(1)-2'), [
        T.lParen,
        (T.num, 1),
        T.rParen,
        T.minus,
        (T.num, 2),
        T.eof,
      ]);
      expect(toks(r'$n -1'), [(T.stateVar, r'$n'), T.minus, (T.num, 1), T.eof]);
      expect(toks('true -1'), [T.trueKw, T.minus, (T.num, 1), T.eof]);
      expect(toks('[1] -1'), [
        T.lBracket,
        (T.num, 1),
        T.rBracket,
        T.minus,
        (T.num, 1),
        T.eof,
      ]);
    });

    test('a minus after an operator, bracket or comma is a literal', () {
      expect(expr('3 - -2'), '(3 - -2)');
      expect(expr('[-1, -2.5]'), '[-1, -2.5]');
      expect(expr('Foo(-3)'), 'Foo(-3)');
      expect(expr('a * -2'), '(a * -2)');
      expect(expr('x ? -1 : -2'), '(x ? -1 : -2)');
    });

    test('a minus before a non-digit is always the operator', () {
      expect(toks('-x'), [T.minus, (T.ident, 'x'), T.eof]);
      expect(toks('- 5'), [T.minus, (T.num, 5), T.eof]);
      expect(expr('-x'), '(- x)');
    });

    test('a call result is subtracted from, not negated', () {
      expect(expr('@Sum([1]) -1'), '(Sum([1]) - 1)');
    });
  });

  group('operators and words', () {
    test('two-character operators', () {
      expect(toks('== != >= <= && ||'), [
        T.eqEq,
        T.notEq,
        T.greaterEq,
        T.lessEq,
        T.and,
        T.or,
        T.eof,
      ]);
    });

    test('a single & or | is the same operator', () {
      expect(toks('a & b | c'), [
        (T.ident, 'a'),
        T.and,
        (T.ident, 'b'),
        T.or,
        (T.ident, 'c'),
        T.eof,
      ]);
    });

    test('a lone = or ! or > or < is the short operator', () {
      expect(toks('= ! > <'), [T.equals, T.not, T.greater, T.less, T.eof]);
    });

    test('a capital starts a type, a lower case letter an identifier', () {
      expect(toks('Foo foo _x'), [
        (T.type, 'Foo'),
        (T.ident, 'foo'),
        (T.ident, '_x'),
        T.eof,
      ]);
    });

    test('keywords', () {
      expect(toks('true false null'), [T.trueKw, T.falseKw, T.nullKw, T.eof]);
      expect(toks('nullable'), [(T.ident, 'nullable'), T.eof]);
    });

    test(r'$ and @ need a letter after them; stray characters are skipped', () {
      expect(toks(r'$a1 @F'), [
        (T.stateVar, r'$a1'),
        (T.builtinCall, 'F'),
        T.eof,
      ]);
      expect(toks(r'$1 @1 ~ ;'), [(T.num, 1), (T.num, 1), T.eof]);
    });

    test('blanks are skipped; a newline is a token', () {
      expect(toks('a \t\r\n b'), [
        (T.ident, 'a'),
        T.newline,
        (T.ident, 'b'),
        T.eof,
      ]);
    });
  });

  group('the unary operators', () {
    test('! negates the operand that follows', () {
      expect(expr('!a'), '(! a)');
      expect(expr('!true'), '(! true)');
      expect(expr('!!a'), '(! (! a))');
    });

    test('! binds tighter than every binary operator', () {
      expect(expr('!a && b'), '((! a) && b)');
      expect(expr('!a == b'), '((! a) == b)');
      expect(expr('!a + b'), '((! a) + b)');
    });

    test('! binds looser than member access and indexing', () {
      expect(expr('!a.b'), '(! a.b)');
      expect(expr('!a[0]'), '(! a[0])');
    });

    test('- negates a non-literal and binds like !', () {
      expect(expr('-a * b'), '((- a) * b)');
      expect(expr('-a.b'), '(- a.b)');
    });
  });

  group('operator precedence', () {
    test('multiplication binds tighter than addition', () {
      expect(expr('1 + 2 * 3'), '(1 + (2 * 3))');
      expect(expr('1 * 2 + 3'), '((1 * 2) + 3)');
      expect(expr('8 % 3 * 2'), '((8 % 3) * 2)');
    });

    test('equal precedence associates to the left', () {
      expect(expr('1 - 2 - 3'), '((1 - 2) - 3)');
      expect(expr('8 / 4 / 2'), '((8 / 4) / 2)');
    });

    test('comparison binds tighter than equality', () {
      expect(expr('a < b == c > d'), '((a < b) == (c > d))');
      expect(expr('a >= b != c <= d'), '((a >= b) != (c <= d))');
    });

    test('&& binds tighter than ||', () {
      expect(expr('a || b && c'), '(a || (b && c))');
      expect(expr('a && b || c'), '((a && b) || c)');
    });

    test('arithmetic binds tighter than comparison, then logic', () {
      expect(expr('a + 1 > b * 2 && c'), '(((a + 1) > (b * 2)) && c)');
    });

    test('parentheses override precedence', () {
      expect(expr('(1 + 2) * 3'), '((1 + 2) * 3)');
    });

    test('a ternary takes the lowest precedence and nests to the right', () {
      expect(expr('a || b ? 1 : 2'), '((a || b) ? 1 : 2)');
      expect(expr('a ? b : c ? d : e'), '(a ? b : (c ? d : e))');
      expect(expr('a ? b ? 1 : 2 : 3'), '(a ? (b ? 1 : 2) : 3)');
    });

    test('member access and indexing bind tightest and chain', () {
      expect(expr('a.b.c'), 'a.b.c');
      expect(expr('a.b[0].c'), 'a.b[0].c');
      expect(expr('a.b + c[1]'), '(a.b + c[1])');
    });
  });

  group('member access', () {
    test('a number after the dot names the field with its JS string', () {
      expect(expr('a.2'), 'a.2');
      expect(expr('a.1.5'), 'a.1.5');
    });

    test('a \$var after the dot drops its sigil', () {
      expect(expr(r'a.$b'), 'a.b');
    });

    test('a type, string or identifier names the field as is', () {
      expect(expr('a.Foo'), 'a.Foo');
      expect(expr('a."x y"'), 'a.x y');
    });

    test('anything else names the field ?', () {
      expect(expr('a.(1)'), 'a.?');
    });
  });

  group('object keys', () {
    test('identifiers, strings, types and \$vars name the key', () {
      expect(
        expr(r"""{a: 1, "b c": 2, 'd': 3, E: 4, $f: 5}"""),
        '{a: 1, b c: 2, d: 3, E: 4, f: 5}',
      );
    });

    test('an integer key is its decimal string', () {
      expect(expr('{1: "a", 20: "b", -3: "c"}'), '{1: "a", 20: "b", -3: "c"}');
    });

    test('a fractional key keeps its fraction', () {
      expect(expr('{1.5: "a", 0.25: "b"}'), '{1.5: "a", 0.25: "b"}');
    });

    test(
      'a large whole key prints in full below 1e21, in exponent form after',
      () {
        expect(expr('{1e16: 1}'), '{10000000000000000: 1}');
        expect(expr('{1e20: 1}'), '{100000000000000000000: 1}');
        expect(expr('{1e21: 1}'), '{1e+21: 1}');
        expect(expr('{1.5e300: 1}'), '{1.5e+300: 1}');
      },
    );

    test('a key that is none of those becomes ?', () {
      expect(expr('{true: 1}'), '{?: 1}');
    });

    test('commas are optional and a missing colon is forgiven', () {
      expect(expr('{a 1 b: 2}'), '{a: 1, b: 2}');
    });
  });

  group('malformed input', () {
    test('an unclosed call, array or object ends at the input', () {
      expect(expr('Foo(1, [2, {a: 3'), 'Foo(1, [2, {a: 3}])');
    });

    test('a token that starts no expression is null', () {
      expect(expr(')'), 'null');
      expect(expr(''), 'null');
    });

    test('state assignment parses the whole right side', () {
      expect(expr(r'$n = 1 + 2'), r'$n = (1 + 2)');
    });

    test('@Name( is a call; a bare @Name is a reference', () {
      expect(expr('@Sum([1])'), 'Sum([1])');
      expect(expr('@Sum'), 'Sum');
    });

    test('a built-in type name is a reference unless it is Action', () {
      expect(expr('Action([1])'), 'Action([1])');
      expect(expr('Sum(1)'), 'Sum');
      expect(expr('Foo(1)'), 'Foo(1)');
    });
  });
}
