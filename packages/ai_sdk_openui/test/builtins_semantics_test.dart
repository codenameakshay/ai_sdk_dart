import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:test/test.dart';

import 'support/run.dart';

void main() {
  test('@Sort orders by a field length', () {
    expect(value('@Sort(["bb", "a", "ccc"], "length")'), ['a', 'bb', 'ccc']);
  });

  test('@Filter reads length on nested lists and strings', () {
    expect(value('@Filter([[1, 2], [3]], "length", ">", 1)'), [
      [1, 2],
    ]);
    expect(value('@Filter(["abc", "de"], "length", "==", 3)'), ['abc']);
  });

  test('@Sort follows a dot path into nested lists', () {
    expect(value('@Sort([{p: [5, 1]}, {p: [2, 9]}], "p.0")'), [
      {
        'p': [2, 9],
      },
      {
        'p': [5, 1],
      },
    ]);
  });

  test('@Round handles fractional and negative decimal places', () {
    expect(value('@Round(10, 0.5)'), closeTo(10.119288512538814, 1e-12));
    expect(value('@Round(1234, -2)'), 1200);
    expect(value('@Round(123.456, -1)'), 120);
    expect(value('@Round(1.005, 2)'), 1);
  });

  test('@Sort puts accented letters after their base letter', () {
    expect(value('@Sort(["f", "é", "e", "E", "É"], "")'), [
      'e',
      'E',
      'é',
      'É',
      'f',
    ]);
  });

  test('@Sort compares accented names by base letters first', () {
    expect(value('@Sort(["Zoe", "Émile", "adam"], "")'), [
      'adam',
      'Émile',
      'Zoe',
    ]);
    expect(value('@Sort(["résumé", "resume", "Resume"], "")'), [
      'resume',
      'Resume',
      'résumé',
    ]);
  });

  test('@Sort puts ASCII punctuation before digits and letters', () {
    expect(value('@Sort(["~x", "1", "a", "{"], "")'), ['{', '~x', '1', 'a']);
    expect(value('@Sort(["b", "B", "a"], "")'), ['a', 'b', 'B']);
  });

  test('@Each over component values yields the components', () {
    final items =
        run('@Each([x, y], "c", c)', 'x = Out(1)\ny = Out(2)').value as List;
    expect(items, hasLength(2));
    expect((items[0] as OpenUiElement).props['value'], 1);
    expect((items[1] as OpenUiElement).props['value'], 2);
  });
}
