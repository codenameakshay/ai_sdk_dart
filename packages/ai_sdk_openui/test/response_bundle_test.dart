import 'dart:convert';

import 'package:ai_sdk_openui/src/runtime/response_bundle.dart';
import 'package:test/test.dart';

const _scriptsJson =
    '[{"name":"b_tool","code":"x"},{"name":"a_tool","code":"y"}]';

final _fence = '`' * 3;
final _program = '${_fence}openui-lang\nroot = Text("Hello")\n$_fence\n';
final _body = _program.trimRight();
const _script = {
  'name': 'sales_total',
  'code': 'async ({ tools }) => tools.get_sales({})',
};

String _scriptsSection(Object? values, [Object? count = 1]) =>
    ']]>openui:scripts ${jsonEncode({'count': count})}\n${jsonEncode(values)}\n';

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
      expect(bundle.metadata.name, 'Deck');
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
      expect(bundle.metadata.name, isNull);
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

    test('leaves an unframed response as it is, streaming or not', () {
      for (final response in [
        null,
        '',
        '  \n',
        'root = Text("Hello")',
        _program,
      ]) {
        for (final streaming in [false, true]) {
          final b = parseResponseBundle(response, streaming: streaming);
          final reason = '$response $streaming';
          expect(b.program, response ?? '', reason: reason);
          expect(b.metadata.name, isNull, reason: reason);
          expect(b.scripts, isEmpty, reason: reason);
          expect(b.complete, isTrue, reason: reason);
          expect(b.isBundle, isFalse, reason: reason);
          expect(b.error, isNull, reason: reason);
        }
      }
    });

    test('decodes the name and separates the program from its envelope', () {
      final b = parseResponseBundle(
        ' \n]]>openui:content?v=2&name=Sales+%26+Growth+%E2%82%AC\n'
        '$_program]]>openui:end\n',
        streaming: false,
      );
      expect(b.program, _body);
      expect(b.metadata.name, 'Sales & Growth €');
      expect(b.scripts, isEmpty);
      expect(b.complete, isTrue);
      expect(b.isBundle, isTrue);
      expect(b.error, isNull);
    });

    test('reads Windows line endings', () {
      final b = parseResponseBundle(
        ']]>openui:content?name=Sales\r\n'
        '${_program.replaceAll('\n', '\r\n')}'
        '${_scriptsSection([_script]).replaceAll('\n', '\r\n')}'
        ']]>openui:end\r\n',
        streaming: false,
      );
      expect(b.program, _body.replaceAll('\n', '\r\n'));
      expect(b.metadata.name, 'Sales');
      expect(b.scripts, {'sales_total'});
      expect(b.complete, isTrue);
      expect(b.error, isNull);
    });

    test('uses the latest content section without its old scripts or name', () {
      final previous =
          ']]>openui:content?name=Previous\n$_program'
          '${_scriptsSection([_script])}]]>openui:end\n';
      final b = parseResponseBundle(
        '$previous]]>openui:content\nroot = Text("Updated")\n]]>openui:end',
        streaming: false,
      );
      expect(b.program, 'root = Text("Updated")');
      expect(b.metadata.name, isNull);
      expect(b.scripts, isEmpty);
      expect(b.scriptRevision, isNull);
      expect(b.complete, isTrue);
      expect(b.isBundle, isTrue);
      expect(b.error, isNull);
    });

    test('accepts an explicitly empty scripts section', () {
      final b = parseResponseBundle(
        ']]>openui:content\n$_program${_scriptsSection([], 0)}]]>openui:end',
        streaming: false,
      );
      expect(b.scripts, isEmpty);
      expect(b.complete, isTrue);
      expect(b.error, isNull);
    });

    test('reads a legacy scripts bundle with or without an end line', () {
      for (final end in ['', ']]>openui:end']) {
        final b = parseResponseBundle(
          '$_program${_scriptsSection([_script])}$end',
          streaming: false,
        );
        expect(b.program, _body, reason: end);
        expect(b.isBundle, isTrue, reason: end);
        expect(b.scripts, {'sales_total'}, reason: end);
        expect(b.complete, isTrue, reason: end);
        expect(b.error, isNull, reason: end);
      }
    });

    test('rejects every invalid scripts payload once streaming finishes', () {
      final cases = <String, (Object?, Object?)>{
        'non-array payload': (<String, Object?>{}, 1),
        'null payload': (null, 1),
        'mismatched count': ([_script], 2),
        'string count': ([_script], '1'),
        'fractional count': ([_script], 1.5),
        'negative count': (<Object?>[], -1),
        'null entry': ([null], 1),
        'missing name': (
          [
            {'code': 'async () => null'},
          ],
          1,
        ),
        'empty name': (
          [
            {..._script, 'name': ''},
          ],
          1,
        ),
        'non-string name': (
          [
            {..._script, 'name': 42},
          ],
          1,
        ),
        'missing code': (
          [
            {'name': 'sales_total'},
          ],
          1,
        ),
        'non-string code': (
          [
            {..._script, 'code': 42},
          ],
          1,
        ),
        'duplicate names': ([_script, _script], 2),
      };
      for (final MapEntry(key: label, value: (values, count))
          in cases.entries) {
        final response =
            ']]>openui:content\n$_program'
            '${_scriptsSection(values, count)}]]>openui:end';
        final finished = parseResponseBundle(response, streaming: false);
        expect(finished.program, _body, reason: label);
        expect(finished.complete, isFalse, reason: label);
        expect(finished.error, 'Invalid scripts bundle', reason: label);
        final streamed = parseResponseBundle(response, streaming: true);
        expect(streamed.program, _body, reason: label);
        expect(streamed.complete, isFalse, reason: label);
        expect(streamed.error, isNull, reason: label);
      }
    });

    test('rejects malformed scripts JSON', () {
      for (final section in [
        ']]>openui:scripts {invalid}\n[]\n',
        ']]>openui:scripts {"count":1}\n[{"name":\n',
      ]) {
        final b = parseResponseBundle(
          ']]>openui:content\n$_program$section]]>openui:end',
          streaming: false,
        );
        expect(b.program, _body, reason: section);
        expect(b.complete, isFalse, reason: section);
        expect(b.error, 'Invalid scripts bundle', reason: section);
      }
    });

    test(
      'shows the program progressively and never errors while streaming',
      () {
        const header = ']]>openui:content?name=Sales\n';
        final response =
            '$header$_program${_scriptsSection([_script])}]]>openui:end';
        for (var length = 1; length <= response.length; length++) {
          final b = parseResponseBundle(
            response.substring(0, length),
            streaming: true,
          );
          final reason = 'prefix length $length';
          expect(b.error, isNull, reason: reason);
          expect(b.isBundle, length >= header.length, reason: reason);
          if (b.isBundle) expect(b.complete, isFalse, reason: reason);
          final visible = (length - header.length).clamp(0, _program.length);
          expect(
            b.program.trimRight(),
            _program.substring(0, visible).trimRight(),
            reason: reason,
          );
        }
        final done = parseResponseBundle(response, streaming: false);
        expect(done.complete, isTrue);
        expect(done.error, isNull);
      },
    );

    test('holds back an unfinished header while streaming', () {
      for (final response in [']]', ']]>openui:content?name=Sales']) {
        final b = parseResponseBundle(response, streaming: true);
        expect(b.program, '', reason: response);
        expect(b.error, isNull, reason: response);
      }
    });

    test('reads a header without a body as an empty named program', () {
      final b = parseResponseBundle(
        ']]>openui:content?name=Sales',
        streaming: false,
      );
      expect(b.program, '');
      expect(b.metadata.name, 'Sales');
      expect(b.complete, isTrue);
      expect(b.error, isNull);
    });

    test(
      'renders a stored message without an end line, but waits for it while streaming',
      () {
        for (final tail in [
          '',
          _scriptsSection([_script]),
          ']]>openui:unknown',
        ]) {
          final response = ']]>openui:content\n$_program$tail';
          final finished = parseResponseBundle(response, streaming: false);
          expect(
            finished.program,
            tail.isEmpty ? _program : _body,
            reason: tail,
          );
          expect(finished.complete, isTrue, reason: tail);
          expect(finished.error, isNull, reason: tail);
          expect(
            parseResponseBundle(response, streaming: true).complete,
            isFalse,
            reason: tail,
          );
        }
      },
    );

    test('rejects a scripts line without its JSON', () {
      final b = parseResponseBundle(
        ']]>openui:content\n$_program]]>openui:scripts',
        streaming: false,
      );
      expect(b.program, _body);
      expect(b.complete, isFalse);
      expect(b.error, 'Invalid scripts bundle');
    });

    test('keeps markers inside strings and comments, framed or not', () {
      for (final content in [
        'root = Text("]]>openui:scripts")\n',
        "root = Text(']]>openui:end')\n",
        'root = Text("An escaped quote: \\" and marker: ]]>openui:end")\n',
        'root = Text("A trailing backslash: \\\\")\n',
        '// Ignore "]]>openui:scripts\nroot = Text("Hello")\n',
        '# Ignore \' ]]>openui:end\nroot = Text("Hello")\n',
      ]) {
        final plain = parseResponseBundle(content, streaming: false);
        expect(plain.program, content, reason: content);
        expect(plain.isBundle, isFalse, reason: content);
        expect(plain.error, isNull, reason: content);
        final framed = parseResponseBundle(
          ']]>openui:content\n$content]]>openui:end',
          streaming: false,
        );
        expect(framed.program, content.trimRight(), reason: content);
        expect(framed.complete, isTrue, reason: content);
        expect(framed.error, isNull, reason: content);
      }
    });

    test('does not end the scripts payload at marker text in script code', () {
      const code =
          r'async () => "Escaped quote: \"; ]]>openui:end; ]]>openui:scripts"';
      final section = _scriptsSection([
        {..._script, 'code': code},
      ]);
      final b = parseResponseBundle(
        ']]>openui:content\n$_program$section]]>openui:end',
        streaming: false,
      );
      expect(b.program, _body);
      expect(b.scripts, {'sales_total'});
      expect(b.complete, isTrue);
      expect(b.error, isNull);
    });

    test(
      'reads a content line that starts mid-line after a cut-off attempt',
      () {
        const header = ']]>openui:content?v=2';
        final b = parseResponseBundle(
          '$header\nroot = Text("Broken$header\n$_program'
          '${_scriptsSection([_script])}]]>openui:end',
          streaming: false,
        );
        expect(b.program, _body);
        expect(b.scripts, {'sales_total'});
        expect(b.complete, isTrue);
      },
    );
  });
}
