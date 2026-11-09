import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:ai_sdk_openui/src/iui/functions/text.dart';
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

const _program =
    r'$n = 1'
    '\n'
    r'root = Out($n, Action([@Set($n, 2)]))';

final _library = OpenUiLibrary(
  root: _Spec('Out', {'value': S.any(), 'action': actionSchema.optional()}),
  components: [
    _Spec('Out', {'value': S.any(), 'action': actionSchema.optional()}),
  ],
  functions: textFunctions,
);

Future<void> settle() => Future<void>.delayed(Duration.zero);

Future<void> press(OpenUiAnswers answers) async {
  final session = answers.sessionOf('m1')!;
  await session.run(
    session.root!.props.action('action'),
    label: 'Set',
    emit: (_) {},
  );
}

void main() {
  test('replay keeps the saved message text verbatim', () {
    final answers = OpenUiAnswers(library: _library);
    addTearDown(answers.dispose);
    final text = messageWithState(_program, {r'$n': 7});

    answers.update('m1', text, streaming: false);

    expect(answers.textOf('m1'), text);
  });

  test('deltas complete a saved context without moving it into content', () {
    final answers = OpenUiAnswers(library: _library);
    addTearDown(answers.dispose);
    const prefix =
        ']]>openui:content\nroot = Out(1)\n'
        ']]>openui:context\n[{"\$n":';
    const suffix = '7}]';
    answers.update('m1', prefix, streaming: true);

    answers.append('m1', suffix);
    answers.finish('m1');

    expect(answers.textOf('m1'), '$prefix$suffix');
  });

  test(
    'saved context survives a later model snapshot for the same id',
    () async {
      final saved = <String, String>{};
      final answers = OpenUiAnswers(
        library: _library,
        onSave: (id, text) => saved[id] = text,
      );
      addTearDown(answers.dispose);
      answers.update('m1', _program, streaming: false);
      await press(answers);
      await settle();

      answers.update('m1', _program, streaming: false);

      expect(answers.sessionOf('m1')!.state, {r'$n': 2});
      expect(answers.textOf('m1'), contains(']]>openui:context\n[{"\$n":2}]'));
      expect(saved['m1'], answers.textOf('m1'));
    },
  );

  test('local saved state wins over a stale snapshot context', () async {
    final saved = <String, String>{};
    final answers = OpenUiAnswers(
      library: _library,
      onSave: (id, text) => saved[id] = text,
    );
    addTearDown(answers.dispose);
    answers.update('m1', _program, streaming: false);
    await press(answers);
    await settle();

    answers.update(
      'm1',
      messageWithState(_program, {r'$n': 1}),
      streaming: false,
    );

    expect(answers.sessionOf('m1')!.state, {r'$n': 2});
    expect(answers.textOf('m1'), contains(']]>openui:context\n[{"\$n":2}]'));
    expect(saved, hasLength(1));
  });

  test(
    'append after save appends to content before the saved context',
    () async {
      final answers = OpenUiAnswers(library: _library);
      addTearDown(answers.dispose);
      answers.update('m1', _program, streaming: false);
      await press(answers);
      await settle();

      answers.append('m1', '\nroot = Out(3)');
      answers.finish('m1');

      expect(
        answers.textOf('m1'),
        contains('root = Out(3)\n]]>openui:context'),
      );
      expect(answers.sessionOf('m1')!.state, {r'$n': 2});
    },
  );
}
