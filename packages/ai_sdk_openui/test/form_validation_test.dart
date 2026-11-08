import 'package:ai_sdk_openui/src/runtime/form_validation.dart';
import 'package:test/test.dart';

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

    test('ignores a rule type with no validator', () {
      expect(validate('x', [const ParsedRule('unknown')]), isNull);
    });
  });
}
