import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:test/test.dart';

final class _Spec implements ComponentSpec {
  const _Spec(this.typeName, this.props);
  @override
  final String typeName;
  @override
  String get description => '';
  @override
  final Map<String, Schema> props;
}

final _library = OpenUiLibrary(
  root: _Spec('Out', {'value': S.any()}),
  components: [
    _Spec('Out', {'value': S.any()}),
  ],
);

/// About 20 KB: a few `$state` declarations and rows of text and numbers.
String _answer() {
  final out = StringBuffer()
    ..writeln(r'$filter = "all"')
    ..writeln(r'$page = 1');
  final rows = <String>[];
  for (var i = 0; out.length < 20000; i++) {
    rows.add('row$i');
    out.writeln(
      'row$i = Out(["Payment $i", "Paid to a merchant for order $i, '
      'settled to the account ending 0$i after review", ${i * 125}, '
      r'$filter, $page, {status: "settled", note: "row '
      '$i'
      r'"}])',
    );
  }
  out.write('root = Out([${rows.join(', ')}])');
  return out.toString();
}

void main() {
  test(
    'a 20 KB answer streamed one character at a time finishes in seconds',
    () {
      final text = _answer();
      expect(text.length, greaterThan(20000));
      final answers = OpenUiAnswers(library: _library);
      addTearDown(answers.dispose);

      final watch = Stopwatch()..start();
      for (var i = 0; i < text.length; i++) {
        answers.append('m1', text[i]);
      }
      answers.finish('m1');

      // Re-parsing and re-stringifying the whole text on every delta took
      // about 15 s here; the bound leaves room for slower CI machines.
      expect(watch.elapsed, lessThan(const Duration(seconds: 8)));

      expect(answers.sessionOf('m1')!.errors, isEmpty);
      expect(answers.sessionOf('m1')!.state, {r'$filter': 'all', r'$page': 1});
    },
    testOn: 'vm',
  );
}
