import 'package:ai_sdk_openui/src/runtime/form_validation.dart';
import 'package:test/test.dart';

final class _Upper extends ValidationMessages {
  const _Upper();
  @override
  String get fieldRequired => 'REQUIRED';
  @override
  String get optionRequired => 'PICK ONE';
  @override
  String get invalidEmail => 'EMAIL';
  @override
  String get invalidUrl => 'URL';
  @override
  String get notANumber => 'NUMBER';
  @override
  String atLeast(String limit) => '>= $limit';
  @override
  String atMost(String limit) => '<= $limit';
  @override
  String atLeastCharacters(String limit) => 'LEN >= $limit';
  @override
  String atMostCharacters(String limit) => 'LEN <= $limit';
  @override
  String get invalidFormat => 'FORMAT';
}

void main() {
  group('parseRules', () {
    test('keeps numeric arguments as numbers and skips non-string entries', () {
      expect(
        parseRules([
          'required',
          'min:8',
          'minLength:3',
          r'pattern:^[a-z]+:x$',
          'max:abc',
          5,
          'email',
        ]),
        [
          const ParsedRule('required'),
          const ParsedRule('min', 8),
          const ParsedRule('minLength', 3),
          const ParsedRule('pattern', r'^[a-z]+:x$'),
          const ParsedRule('max', 'abc'),
          const ParsedRule('email'),
        ],
      );
    });

    test('gives no rules for a value that is not a list', () {
      expect(parseRules('required'), isEmpty);
    });

    test('compares parsed rules by type and argument', () {
      final parsed = parseRules(['min:8']).single;
      expect(parsed == const ParsedRule('min', 8), isTrue);
      expect(parsed == const ParsedRule('min', 9), isFalse);
      expect({const ParsedRule('min', 8)}.contains(parsed), isTrue);
    });
  });

  group('parseStructuredRules', () {
    test('turns true into a bare rule and other values into arguments', () {
      expect(
        parseStructuredRules({
          'required': true,
          'minLength': 5,
          'email': false,
          'max': 100,
          'pattern': '^a',
          'x': null,
          'z': 0,
        }),
        [
          const ParsedRule('required'),
          const ParsedRule('minLength', 5),
          const ParsedRule('max', 100),
          const ParsedRule('pattern', '^a'),
          const ParsedRule('z', 0),
        ],
      );
    });

    test('gives no rules for a list', () {
      expect(parseStructuredRules(['required']), isEmpty);
    });
  });

  group('required', () {
    test('reports an empty value', () {
      for (final value in [
        '',
        [],
        {},
        {'value': ''},
      ]) {
        expect(
          validate(value, [const ParsedRule('required')]),
          'This field is required',
        );
      }
    });

    test('accepts whitespace as a value', () {
      expect(validate('  ', [const ParsedRule('required')]), isNull);
    });

    test('requires at least one true option in a map of booleans', () {
      expect(
        validate({'a': false, 'b': false}, [const ParsedRule('required')]),
        'At least one option is required',
      );
      expect(
        validate({'a': false, 'b': true}, [const ParsedRule('required')]),
        isNull,
      );
    });
  });

  group('email', () {
    test('accepts an address with a domain and reports the rest', () {
      expect(validate('a@b.co', [const ParsedRule('email')]), isNull);
      expect(
        validate('a@b', [const ParsedRule('email')]),
        'Please enter a valid email',
      );
      expect(
        validate(5, [const ParsedRule('email')]),
        'Please enter a valid email',
      );
    });
  });

  group('url', () {
    test('accepts absolute URLs of any scheme with a host or path', () {
      expect(validate('https://x.y', [const ParsedRule('url')]), isNull);
      expect(validate('mailto:a', [const ParsedRule('url')]), isNull);
    });

    test('rejects network ports outside the unsigned 16-bit range', () {
      expect(
        validate('https://example.com:65536', [const ParsedRule('url')]),
        'Please enter a valid URL',
      );
    });

    test('rejects file URLs with a port', () {
      expect(
        validate('file://host:80/path', [const ParsedRule('url')]),
        'Please enter a valid URL',
      );
    });

    test('rejects text that is not an absolute URL', () {
      for (final value in ['not a url', 'http://', 'https://x y.com']) {
        expect(
          validate(value, [const ParsedRule('url')]),
          'Please enter a valid URL',
        );
      }
    });

    test('rejects a host with a percent sign', () {
      expect(
        validate('https://a%20b.com', [const ParsedRule('url')]),
        'Please enter a valid URL',
      );
    });

    test('rejects a value that is not a string', () {
      expect(
        validate(5, [const ParsedRule('url')]),
        'Please enter a valid URL',
      );
    });
  });

  group('numeric', () {
    test('rejects next-line characters before a numeric value', () {
      expect(
        validate('\u00851', [const ParsedRule('numeric')]),
        'Must be a number',
      );
    });

    test('accepts numbers and numeric text', () {
      expect(validate('12abc', [const ParsedRule('numeric')]), isNull);
      expect(validate(3, [const ParsedRule('numeric')]), isNull);
      expect(validate('Infinity', [const ParsedRule('numeric')]), isNull);
      expect(validate('-Infinity', [const ParsedRule('numeric')]), isNull);
      expect(validate('-3.5e2', [const ParsedRule('numeric')]), isNull);
    });

    test('rejects text with no leading number', () {
      expect(
        validate('abc', [const ParsedRule('numeric')]),
        'Must be a number',
      );
      expect(validate(' ', [const ParsedRule('numeric')]), 'Must be a number');
      expect(
        validate(double.nan, [const ParsedRule('numeric')]),
        'Must be a number',
      );
    });
  });

  group('min and max', () {
    test('compares numeric text with the limit', () {
      expect(validate('7', [const ParsedRule('min', 8)]), 'Must be at least 8');
      expect(validate('9', [const ParsedRule('min', 8)]), isNull);
      expect(validate('x', [const ParsedRule('min', 8)]), isNull);
      expect(
        validate('7', [const ParsedRule('min', '8')]),
        'Must be at least 8',
      );
    });

    test('reports values above the maximum', () {
      expect(
        validate(101, [const ParsedRule('max', 100)]),
        'Must be no more than 100',
      );
      expect(
        validate(1.5, [const ParsedRule('max', 1)]),
        'Must be no more than 1',
      );
      expect(validate(1.5, [const ParsedRule('max', 2)]), isNull);
    });

    test('fails against a limit that is not a number', () {
      expect(
        validate(3, [const ParsedRule('min', 'abc')]),
        'Must be at least NaN',
      );
    });

    test('reads a value that is not a number as text', () {
      expect(validate(true, [const ParsedRule('min', 1)]), isNull);
    });

    test('passes an empty value', () {
      expect(validate('', [const ParsedRule('min', 8)]), isNull);
    });
  });

  group('minLength and maxLength', () {
    test('measures text only', () {
      expect(
        validate('ab', [const ParsedRule('minLength', 3)]),
        'Must be at least 3 characters',
      );
      expect(
        validate('abcd', [const ParsedRule('maxLength', 3)]),
        'Must be no more than 3 characters',
      );
      expect(validate(12345, [const ParsedRule('minLength', 30)]), isNull);
    });
  });

  group('pattern', () {
    test('reports text that does not match', () {
      expect(
        validate('ABC', [const ParsedRule('pattern', '^[a-z]+\$')]),
        'Invalid format',
      );
    });

    test('ignores a pattern that does not compile', () {
      expect(validate('abc', [const ParsedRule('pattern', '[(')]), isNull);
    });

    test('ignores a pattern argument that is not text', () {
      expect(validate('abc', [const ParsedRule('pattern', 3)]), isNull);
    });

    test('ignores a nested-quantifier pattern instead of backtracking', () {
      final watch = Stopwatch()..start();
      final error = validate('${'a' * 27}!', [
        const ParsedRule('pattern', r'^(a+)+$'),
      ]);

      expect(watch.elapsedMilliseconds, lessThan(500));
      expect(error, isNull);
    });

    test('ignores every quantified group that holds a quantifier', () {
      for (final pattern in [
        r'^(a*)*$',
        r'^(a?){25}a{25}$',
        r'^(?:a?)+$',
        r'(?:a+){2,}',
        r'((a+)b)+',
        r'(a{1,3})+',
        r'([a-z]+\d)*',
      ]) {
        expect(
          validate('!', [ParsedRule('pattern', pattern)]),
          isNull,
          reason: pattern,
        );
      }
    });

    test('ignores a repeated group whose alternatives can overlap', () {
      final watch = Stopwatch()..start();
      for (final pattern in [
        r'^(a|aa)+$',
        r'^(a|a)*$',
        r'^(?:ab|a)+$',
        r'^([a-z]|\d)+$',
        r'^((a|b)c|d)+$',
      ]) {
        expect(
          validate('${'a' * 40}!', [ParsedRule('pattern', pattern)]),
          isNull,
          reason: pattern,
        );
      }
      expect(watch.elapsedMilliseconds, lessThan(500));
    });

    test('ignores choices that repeat the same escaped literal', () {
      for (final pattern in [r'^(-|\-)+$', r'^(,|\,)+?$']) {
        expect(
          validate('---!', [ParsedRule('pattern', pattern)]),
          isNull,
          reason: pattern,
        );
      }
    });

    test('checks literal pipes and parentheses inside repeated groups', () {
      for (final pattern in [
        r'^([|])+$',
        r'^(a\|b)+$',
        r'^(\(|a)+$',
        r'^([()|])+$',
        r'^(\||a)+$',
      ]) {
        expect(
          validate('!', [ParsedRule('pattern', pattern)]),
          'Invalid format',
          reason: pattern,
        );
      }
    });

    test(
      'ignores overlapping choices through nested groups and assertions',
      () {
        for (final pattern in [
          r'^((a|aa))+$',
          r'^(?:(a|aa))+$',
          r'^(?=(a|aa)+$)a+$',
          r'^(?!(a|aa)+$)a+$',
          r'^(a|aa)+?$',
          r'^((a+?))+$',
        ]) {
          expect(
            validate('aaaa!', [ParsedRule('pattern', pattern)]),
            isNull,
            reason: pattern,
          );
        }
      },
    );

    test('ignores unbalanced groups without throwing', () {
      for (final pattern in [
        '(',
        ')',
        '(()',
        '())',
        '(?=',
        '([|])(',
        r'(a\',
        '[',
      ]) {
        expect(
          validate('!', [ParsedRule('pattern', pattern)]),
          isNull,
          reason: pattern,
        );
      }
    });

    test('still checks patterns without a nested quantifier', () {
      for (final pattern in [
        r'^(ab)+$',
        r'^(?:ab)+$',
        r'^\?+$',
        r'^[?]+$',
        r'^(a+)?$',
        r'^\(a+\)+$',
        r'^[(a+)]+$',
        r'^[\](+]+$',
        r'^(a|b)*$',
        r'^(?:-|\.)+$',
        r'^(ab|cd)$',
      ]) {
        expect(
          validate('!', [ParsedRule('pattern', pattern)]),
          'Invalid format',
          reason: pattern,
        );
      }
    });
  });

  group('validate', () {
    test('reports the first failing rule in order', () {
      expect(
        validate('', [const ParsedRule('nope'), const ParsedRule('required')]),
        'This field is required',
      );
      expect(
        validate('ab', [
          const ParsedRule('minLength', 3),
          const ParsedRule('required'),
        ]),
        'Must be at least 3 characters',
      );
    });

    test('uses a custom validator over the built-in one of the same type', () {
      expect(
        validate(
          'x',
          [const ParsedRule('required')],
          {'required': (_, _) => 'custom says no'},
        ),
        'custom says no',
      );
    });

    test('built-in rules speak the given messages', () {
      String? check(Object? value, String rule) =>
          validate(value, parseRules([rule]), null, const _Upper());

      expect(check('', 'required'), 'REQUIRED');
      expect(check({'a': false}, 'required'), 'PICK ONE');
      expect(check('x', 'email'), 'EMAIL');
      expect(check('x', 'url'), 'URL');
      expect(check('x', 'numeric'), 'NUMBER');
      expect(check('1', 'min:2'), '>= 2');
      expect(check('3', 'max:2'), '<= 2');
      expect(check('a', 'minLength:2'), 'LEN >= 2');
      expect(check('abc', 'maxLength:2'), 'LEN <= 2');
      expect(check('A', r'pattern:^[a-z]$'), 'FORMAT');
    });

    test('the default messages are English', () {
      const english = ValidationMessages();
      for (final (value, rule) in [
        ('', 'required'),
        ({'a': false}, 'required'),
        ('x', 'email'),
        ('x', 'url'),
        ('x', 'numeric'),
        ('1', 'min:2'),
        ('3', 'max:2'),
        ('a', 'minLength:2'),
        ('abc', 'maxLength:2'),
        ('A', r'pattern:^[a-z]$'),
      ]) {
        final rules = parseRules([rule]);
        expect(
          validate(value, rules, null, english),
          validate(value, rules),
          reason: rule,
        );
      }
    });

    test('a custom validator wins over the given messages', () {
      expect(
        validate(
          '',
          [const ParsedRule('required')],
          {'required': (_, _) => 'custom'},
          const _Upper(),
        ),
        'custom',
      );
    });

    test('a host-added validator still runs with messages', () {
      builtInValidators['even'] = (value, _) =>
          value is int && value.isEven ? null : 'odd';
      addTearDown(() => builtInValidators.remove('even'));

      expect(
        validate(3, [const ParsedRule('even')], null, const _Upper()),
        'odd',
      );
    });

    test('ignores a rule type with no validator', () {
      expect(validate('x', [const ParsedRule('unknown')]), isNull);
    });
  });
}
