import 'dart:async';

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

const _program = '\$n = 1\nroot = Out(\$n, Action([@Set(\$n, 2)]))';

final _payKeys = <String>[];

final _library = OpenUiLibrary(
  root: _Spec('Out', {'value': S.any(), 'action': actionSchema.optional()}),
  components: [
    _Spec('Out', {'value': S.any(), 'action': actionSchema.optional()}),
  ],
  functions: textFunctions,
  actions: [
    ActionSpec(
      'Pay',
      description: 'Pays',
      params: {'orderId': S.string()},
      handler: (invocation) async {
        _payKeys.add(invocation.idempotencyKey);
        return const ActionSuccess();
      },
    ),
  ],
);

Future<void> settle() => Future<void>.delayed(Duration.zero);

Future<void> press(OpenUiAnswers answers, String id) async {
  final session = answers.sessionOf(id)!;
  await session.run(
    session.root!.props.action('action'),
    label: 'Set',
    emit: (_) {},
  );
}

void main() {
  test('deltas build the same session as one full update', () {
    final deltas = OpenUiAnswers(library: _library);
    addTearDown(deltas.dispose);
    for (final delta in ['root = Out(', '3', ')']) {
      deltas.append('m1', delta);
    }
    deltas.finish('m1');

    final whole = OpenUiAnswers(library: _library);
    addTearDown(whole.dispose);
    whole.update('m1', 'root = Out(3)', streaming: false);

    expect(deltas.textOf('m1'), whole.textOf('m1'));
    expect(deltas.sessionOf('m1')!.root!.props['value'], 3);
    expect(
      deltas.sessionOf('m1')!.root!.props['value'],
      whole.sessionOf('m1')!.root!.props['value'],
    );
  });

  test('one session runs from the first delta to finish', () {
    final answers = OpenUiAnswers(library: _library);
    addTearDown(answers.dispose);

    final first = answers.append('m1', 'root = Out(');
    final second = answers.append('m1', '3)');

    expect(second, same(first));
    expect(answers.isStreaming('m1'), isTrue);

    final finished = answers.finish('m1');

    expect(finished, same(first));
    expect(answers.isStreaming('m1'), isFalse);
    expect(finished.root!.props['value'], 3);
  });

  test('one session per id: the same instance across updates', () {
    final answers = OpenUiAnswers(library: _library);
    addTearDown(answers.dispose);

    final first = answers.update('m1', 'root = Out(1)', streaming: true);

    expect(
      answers.update('m1', 'root = Out(12)', streaming: false),
      same(first),
    );
    expect(
      answers.update('m2', 'root = Out(2)', streaming: false),
      isNot(same(first)),
    );
  });

  test('a user change on a finished message is saved into its text', () async {
    final saved = <String, String>{};
    final answers = OpenUiAnswers(
      library: _library,
      onSave: (id, text) => saved[id] = text,
    );
    addTearDown(answers.dispose);
    answers.update('m1', _program, streaming: false);

    await press(answers, 'm1');
    await settle();

    final text = ']]>openui:content\n$_program\n]]>openui:context\n[{"\$n":2}]';
    expect(saved, {'m1': text});
    expect(answers.textOf('m1'), text);
  });

  test('a change while streaming is saved on finish', () async {
    final saved = <String, String>{};
    final answers = OpenUiAnswers(
      library: _library,
      onSave: (id, text) => saved[id] = text,
    );
    addTearDown(answers.dispose);
    answers.update('m1', _program, streaming: true);

    await press(answers, 'm1');
    await settle();
    expect(saved, isEmpty);

    answers.finish('m1');
    await settle();
    expect(saved, {
      'm1': ']]>openui:content\n$_program\n]]>openui:context\n[{"\$n":2}]',
    });
  });

  test('replay restores a saved message without saving it again', () async {
    final saved = <String, String>{};
    final answers = OpenUiAnswers(
      library: _library,
      onSave: (id, text) => saved[id] = text,
    );
    addTearDown(answers.dispose);
    answers.update('m1', _program, streaming: false);
    await press(answers, 'm1');
    await settle();
    final savedText = saved['m1']!;

    final replays = <String, String>{};
    final replay = OpenUiAnswers(
      library: _library,
      onSave: (id, text) => replays[id] = text,
    );
    addTearDown(replay.dispose);
    replay.update('m1', savedText, streaming: false);
    await settle();

    final session = replay.sessionOf('m1')!;
    expect(session.state, {r'$n': 2});
    expect(session.root!.props['value'], 2);
    expect(replays, isEmpty);
  });

  test('a patch merges into the finished program', () {
    final answers = OpenUiAnswers(library: _library);
    addTearDown(answers.dispose);
    answers.update('m1', 'root = Out(1)', streaming: false);

    answers.patch('m1', 'root = Out(2)');

    expect(answers.sessionOf('m1')!.root!.props['value'], 2);
    expect(answers.textOf('m1'), 'root = Out(2)');
  });

  test('a patch preserves the Cloud envelope and scripts', () {
    final answers = OpenUiAnswers(library: _library);
    addTearDown(answers.dispose);
    answers.update(
      'm1',
      ']]>openui:content?name=Answer\nroot = Out(1)\n'
          ']]>openui:scripts{"count":1}\n'
          '[{"name":"helper","code":"export default 1"}]\n]]>openui:end',
      streaming: false,
    );

    answers.patch('m1', 'root = Out(2)');

    expect(answers.sessionOf('m1')!.metadata.name, 'Answer');
    expect(
      answers.textOf('m1'),
      ']]>openui:content?name=Answer\nroot = Out(2)\n'
      ']]>openui:scripts{"count":1}\n'
      '[{"name":"helper","code":"export default 1"}]\n]]>openui:end',
    );
  });

  test('a patch keeps a script-backed Query live', () async {
    var calls = 0;
    final answers = OpenUiAnswers(
      library: _library,
      tools: [
        OpenUiTool(name: 't', call: (_) async => {'n': ++calls}),
      ],
    );
    addTearDown(answers.dispose);
    answers.update(
      'm1',
      ']]>openui:content?name=Answer\n'
          'root = Out(q.n)\nq = Query("t", {}, {n: 0})\n'
          ']]>openui:scripts{"count":1}\n'
          '[{"name":"t","code":"a"}]\n]]>openui:end',
      streaming: false,
    );
    await settle();
    expect(answers.sessionOf('m1')!.root!.props['value'], 1);

    answers.patch('m1', 'root = Out(q.n + 1)\nq = Query("t", {v: 2}, {n: 0})');
    await settle();

    expect(answers.sessionOf('m1')!.root!.props['value'], 3);
    expect(calls, 2);
    expect(answers.sessionOf('m1')!.metadata.name, 'Answer');
  });

  test('a patch preserves a legacy scripts bundle', () {
    final answers = OpenUiAnswers(library: _library);
    addTearDown(answers.dispose);
    const text =
        'root = Out(1)\n]]>openui:scripts {"count":1}\n'
        '[{"name":"helper","code":"export default 1"}]\n';
    answers.update('m1', text, streaming: false);

    answers.patch('m1', 'root = Out(2)');

    expect(
      answers.textOf('m1'),
      'root = Out(2)\n]]>openui:scripts {"count":1}\n'
      '[{"name":"helper","code":"export default 1"}]\n',
    );
  });

  test('a patch keeps the saved state of the message', () async {
    final answers = OpenUiAnswers(library: _library);
    addTearDown(answers.dispose);
    answers.update('m1', _program, streaming: false);
    await press(answers, 'm1');

    answers.patch('m1', 'root = Out(\$n, Action([@Set(\$n, 3)]))');

    expect(answers.sessionOf('m1')!.state, {r'$n': 2});
    expect(answers.sessionOf('m1')!.root!.props['value'], 2);
    expect(answers.textOf('m1'), contains(']]>openui:context\n[{"\$n":2}]'));
  });

  test('listen consumes a stream of events', () async {
    final answers = OpenUiAnswers(library: _library);
    addTearDown(answers.dispose);

    final subscription = answers.listen(
      Stream.fromIterable([
        const OpenUiTextDelta('m1', 'root = Out('),
        const OpenUiTextDelta('m1', '4)'),
        const OpenUiMessageDone('m1'),
        const OpenUiTextSnapshot('m2', 'root = Out(5)', streaming: false),
        const OpenUiPatch('m2', 'root = Out(6)'),
      ]),
    );
    await subscription.asFuture<void>();

    expect(answers.sessionOf('m1')!.root!.props['value'], 4);
    expect(answers.isStreaming('m1'), isFalse);
    expect(answers.sessionOf('m2')!.root!.props['value'], 6);
  });

  test('actions are keyed by message id', () async {
    _payKeys.clear();
    final answers = OpenUiAnswers(library: _library);
    addTearDown(answers.dispose);
    answers.update('msg-1', 'root = Out(1, @Pay("o-1"))', streaming: false);

    await press(answers, 'msg-1');

    expect(_payKeys, ['cc882598d3b427ba-1']);
  });

  test('actionScope is the message id', () {
    final answers = OpenUiAnswers(library: _library);
    addTearDown(answers.dispose);
    answers.update('msg-2', 'root = Out(1)', streaming: false);

    expect(answers.sessionOf('msg-2')!.actionScope, 'msg-2');
  });

  test('locale and records reach the session', () {
    final answers = OpenUiAnswers(
      library: _library,
      locale: 'de-DE',
      records: (id) => [
        BoundRecord('order', {'id': id}),
      ],
    );
    addTearDown(answers.dispose);

    answers.update('m1', 'root = Out(@Format(1234567.891))', streaming: false);
    answers.update('m2', r'root = Out($order.id)', streaming: false);

    expect(answers.sessionOf('m1')!.root!.props['value'], '1.234.567,89');
    expect(answers.sessionOf('m2')!.root!.props['value'], 'm2');
  });

  test('retain, remove and dispose release sessions', () {
    final answers = OpenUiAnswers(library: _library);
    final kept = answers.update('m2', 'root = Out(2)', streaming: false);
    final dropped = answers.update('m1', 'root = Out(1)', streaming: false);
    answers.update('m3', 'root = Out(3)', streaming: false);

    answers.retain(['m2', 'm3']);
    expect(answers.sessionOf('m1'), isNull);
    expect(answers.textOf('m1'), isNull);
    expect(answers.sessionOf('m2'), same(kept));

    dropped.update('root = Out(9)', streaming: false);
    expect(dropped.root!.props['value'], 1);

    answers.remove('m3');
    expect(answers.sessionOf('m3'), isNull);
    expect(answers.isStreaming('m3'), isFalse);

    answers.dispose();
    kept.update('root = Out(9)', streaming: false);
    expect(kept.root!.props['value'], 2);
    expect(
      () => answers.update('m4', 'root = Out(4)', streaming: false),
      throwsStateError,
    );
  });

  test('messageWithState keeps Cloud sections and replaces only context', () {
    const raw =
        ']]>openui:content?name=Form\n$_program\n'
        ']]>openui:scripts{"count":0}\n[]\n]]>openui:end';
    final text = '$raw\n]]>openui:context\n[{"\$name":"Bo"}]';

    expect(
      messageWithState(text, {r'$name': 'Cy'}),
      '$raw\n]]>openui:context\n[{"\$name":"Cy"}]',
    );
  });

  test('messageWithState keeps the sections after the context', () {
    const text =
        ']]>openui:content\nroot = Out(1)\n'
        ']]>openui:context\n[{"a":1}]\n]]>openui:end';

    expect(
      messageWithState(text, {'a': 2}),
      ']]>openui:content\nroot = Out(1)\n'
      ']]>openui:context\n[{"a":2}]\n]]>openui:end',
    );
  });

  test('messageWithState appends the context to a message without one', () {
    expect(
      messageWithState('root = Out(1)', {'a': 2}),
      ']]>openui:content\nroot = Out(1)\n]]>openui:context\n[{"a":2}]',
    );
  });

  test('messageState reads the first saved object of a context', () {
    expect(
      messageState([
        {'a': 1},
        2,
      ]),
      {'a': 1},
    );
    expect(messageState({'a': 1}), {'a': 1});
    expect(messageState('x'), const <String, Object?>{});
  });
}
