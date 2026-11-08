import 'package:ai_sdk_openui/src/runtime/response_bundle.dart';
import 'package:test/test.dart';

const _scriptsJson =
    '[{"name":"b_tool","code":"x"},{"name":"a_tool","code":"y"}]';

void main() {
  group('parseResponseBundle', () {
    test('reads plain program text as not a bundle', () {
      final bundle = parseResponseBundle('root = A()', streaming: false);
      expect(bundle.isBundle, isFalse);
      expect(bundle.complete, isTrue);
      expect(bundle.program, 'root = A()');
    });

    test('reads a missing response as an empty program', () {
      final bundle = parseResponseBundle(null, streaming: false);
      expect(bundle.isBundle, isFalse);
      expect(bundle.program, '');
    });

    test('reads a framed response with its name', () {
      final bundle = parseResponseBundle(
        ']]>openui:content?name=Deck\nroot = A()',
        streaming: false,
      );
      expect(bundle.isBundle, isTrue);
      expect(bundle.complete, isTrue);
      expect(bundle.metadata, {'name': 'Deck'});
      expect(bundle.program, 'root = A()');
    });

    test('keeps a streamed framed response incomplete until it ends', () {
      final bundle = parseResponseBundle(
        ']]>openui:content?name=Deck\nroot = A()',
        streaming: true,
      );
      expect(bundle.isBundle, isTrue);
      expect(bundle.complete, isFalse);
    });

    test('treats an unfinished content marker as no bundle yet', () {
      final bundle = parseResponseBundle(
        ']]>openui:content?name=Deck',
        streaming: true,
      );
      expect(bundle.isBundle, isFalse);
      expect(bundle.program, '');
      expect(bundle.metadata, isEmpty);
    });

    test('keeps a streamed bundle incomplete when its end is held', () {
      final bundle = parseResponseBundle(
        ']]>openui:content\nroot = A()\n]]>openui:end',
        streaming: true,
      );
      expect(bundle.complete, isFalse);
      expect(bundle.isBundle, isTrue);
    });

    test('reads the scripts section and a revision of its code', () {
      final bundle = parseResponseBundle(
        ']]>openui:content\nroot = A()\n'
        ']]>openui:scripts{"count":2}\n$_scriptsJson\n'
        ']]>openui:end',
        streaming: false,
      );
      expect(bundle.program, 'root = A()');
      expect(bundle.scripts, {'b_tool', 'a_tool'});
      expect(bundle.complete, isTrue);
      expect(
        bundle.scriptRevision,
        '[{"name":"a_tool","code":"y"},{"name":"b_tool","code":"x"}]',
      );
    });

    test('reports a scripts section whose count does not match', () {
      final finished = parseResponseBundle(
        ']]>openui:content\nroot = A()\n'
        ']]>openui:scripts{"count":3}\n$_scriptsJson\n]]>openui:end',
        streaming: false,
      );
      expect(finished.error, 'Invalid scripts bundle');
      expect(finished.complete, isFalse);
      expect(finished.scripts, isEmpty);

      final streamed = parseResponseBundle(
        ']]>openui:content\nroot = A()\n'
        ']]>openui:scripts{"count":3}\n$_scriptsJson\n]]>openui:end',
        streaming: true,
      );
      expect(streamed.error, isNull);
      expect(streamed.complete, isFalse);
    });

    test('does not read markers inside strings or comments', () {
      final bundle = parseResponseBundle(
        ']]>openui:content\nroot = A("]]>x") # ]]> in comment\nq = B()',
        streaming: false,
      );
      expect(bundle.program, 'root = A("]]>x") # ]]> in comment\nq = B()');
      expect(bundle.error, isNull);
      expect(bundle.isBundle, isTrue);
    });

    test('does not end a string at an escaped quote', () {
      final bundle = parseResponseBundle(
        ']]>openui:content\nroot = A("a\\"]]>x")\n'
        ']]>openui:scripts{"count":0}\n[]',
        streaming: false,
      );
      expect(bundle.program, 'root = A("a\\"]]>x")');
      expect(bundle.error, isNull);
    });

    test('ends a marker scan at a line comment with no newline after it', () {
      final bundle = parseResponseBundle(
        ']]>openui:content\nroot = A() // ]]>x',
        streaming: false,
      );
      expect(bundle.program, 'root = A() // ]]>x');
      expect(bundle.error, isNull);
    });

    test('reads an end marker without content as a bundle', () {
      final bundle = parseResponseBundle(
        'root = A()\n]]>openui:end',
        streaming: false,
      );
      expect(bundle.isBundle, isTrue);
      expect(bundle.complete, isTrue);
      expect(bundle.program, 'root = A()');
    });

    test('reports a scripts marker with no header as invalid', () {
      final bundle = parseResponseBundle(
        ']]>openui:content\nroot = A()\n]]>openui:scripts\n[]',
        streaming: false,
      );
      expect(bundle.program, 'root = A()');
      expect(bundle.error, 'Invalid scripts bundle');
    });

    test(
      'reports a scripts payload with a repeated or unnamed entry as invalid',
      () {
        for (final payload in [
          '[{"name":"a","code":"x"},{"name":"a","code":"y"}]',
          '[{"name":"","code":"x"}]',
          '["a"]',
        ]) {
          final count = payload.split('"name"').length - 1;
          final bundle = parseResponseBundle(
            ']]>openui:content\nroot = A()\n'
            ']]>openui:scripts{"count":$count}\n$payload\n]]>openui:end',
            streaming: false,
          );
          expect(bundle.error, 'Invalid scripts bundle', reason: payload);
        }
      },
    );

    test('reports a scripts count that is not a safe integer as invalid', () {
      final bundle = parseResponseBundle(
        ']]>openui:content\nroot = A()\n'
        ']]>openui:scripts{"count":1.5}\n[]\n]]>openui:end',
        streaming: false,
      );
      expect(bundle.error, 'Invalid scripts bundle');
    });
  });
}
