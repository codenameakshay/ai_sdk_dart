import 'package:ai_sdk_openui/src/runtime/collation.dart';
import 'package:ai_sdk_openui/src/runtime/response_bundle.dart';
import 'package:test/test.dart';

import 'fixtures/collation_cases.dart';
import 'support/run.dart';

void main() {
  test('orders 4000 strings exactly as Node 26 localeCompare does', () {
    final order = [for (var i = 0; i < collationStrings.length; i++) i]
      ..sort((i, j) {
        final c = localeCompare(collationStrings[i], collationStrings[j]);
        return c != 0 ? c : i - j;
      });
    expect(order, collationOrder);
  });

  test('canonically equivalent strings compare equal', () {
    expect(localeCompare('ȩ́', 'ȩ́'), 0);
    expect(localeCompare('й̣', 'й̣'), 0);
    expect(localeCompare('豈', '豈'), 0);
    expect(localeCompare('a', 'a\u0000'), 0);
  });

  test('@Sort orders accents, ligatures, symbols and scripts as ICU', () {
    expect(
      value(
        '@Sort(["rèsume", "résumé", "st", "ß", "Æble", "Aeble", "ﬁ", "fj", "😀", "!", "가", "中", "丽"], "")',
      ),
      [
        '!',
        '😀',
        'Aeble',
        'Æble',
        'ﬁ',
        'fj',
        'résumé',
        'rèsume',
        'ß',
        'st',
        '가',
        '丽',
        '中',
      ],
    );
  });

  test('a scripts bundle revision lists scripts in localeCompare order', () {
    final bundle = parseResponseBundle(
      ']]>openui:content\nroot = A()\n'
      ']]>openui:scripts{"count":2}\n'
      '[{"name":"B","code":"2"},{"name":"a","code":"1"}]\n'
      ']]>openui:end',
      streaming: false,
    );
    expect(
      bundle.scriptRevision,
      '[{"name":"a","code":"1"},{"name":"B","code":"2"}]',
    );
  });
}
