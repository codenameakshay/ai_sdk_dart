import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:test/test.dart';

/// `Out(value, action)`: a value and an action, so a program can show a result and run steps.
final class _Out implements ComponentSpec {
  const _Out();
  @override
  String get typeName => 'Out';
  @override
  String get description => 'Test output';
  @override
  Map<String, Schema> get props => {
    'value': S.any(),
    'action': actionSchema.optional(),
  };
}

final OpenUiLibrary _library = OpenUiLibrary(
  root: const _Out(),
  components: const [_Out()],
  functions: [
    FunctionSpec(
      'Boom',
      description: 'Always throws',
      params: {'x': S.number()},
      fn: (_) => throw StateError('kaboom'),
    ),
  ],
);

Future<void> settle() => Future<void>.delayed(Duration.zero);

OpenUiSession open(
  String text, {
  bool streaming = false,
  List<OpenUiTool> tools = const [],
}) {
  final s = OpenUiSession(_library, tools: tools)
    ..update(text, streaming: streaming);
  addTearDown(s.dispose);
  return s;
}

Future<List<ActionEvent>> click(OpenUiSession s, {String label = ''}) async {
  final events = <ActionEvent>[];
  await s.run(s.root!.props.action('action'), label: label, emit: events.add);
  return events;
}

void main() {
  test('plain text streams and its actions run', () async {
    final s = open('root = Out(1, @ToAssistant("go"))', streaming: true);
    final events = await click(s);
    expect(events.single.humanFriendlyMessage, 'go');
    expect(s.isStreaming, isTrue);
  });

  test('a Cloud bundle blocks its actions until it settles', () async {
    const head = ']]>openui:content\nroot = Out(1, @ToAssistant("go"))';
    final s = open(head, streaming: true);
    expect(await click(s), isEmpty);

    s.update('$head\n]]>openui:end', streaming: true);
    expect(await click(s), isEmpty);

    s.update('$head\n]]>openui:end', streaming: false);
    expect((await click(s)).single.humanFriendlyMessage, 'go');
  });

  test('a streaming Query in a Cloud bundle reports loading', () {
    final bundle = open(
      ']]>openui:content\nroot = Out(q)\nq = Query("t", {}, {})',
      streaming: true,
    );
    expect(bundle.isQueryLoading, isTrue);

    final plain = open(
      'root = Out(q)\nq = Query("t", {}, {})',
      streaming: true,
    );
    expect(plain.isQueryLoading, isFalse);
  });

  test('a changed script revision refetches the Query that uses it', () async {
    var calls = 0;
    final tool = OpenUiTool(name: 't', call: (_) async => ++calls);
    String bundle(String code) =>
        ']]>openui:content\nroot = Out(q)\nq = Query("t", {}, {})\n'
        ']]>openui:scripts{"count":1}\n'
        '[{"name":"t","code":"$code"}]\n'
        ']]>openui:end';

    final s = OpenUiSession(_library, tools: [tool])
      ..update(bundle('a'), streaming: false);
    addTearDown(s.dispose);
    await settle();
    expect(calls, 1);

    s.update(bundle('b'), streaming: false);
    await settle();
    expect(calls, 2);
  });

  test('an invalid Cloud bundle keeps the root and blocks actions', () async {
    final s = open(
      ']]>openui:content\nroot = Out(1, @ToAssistant("go"))\n'
      ']]>openui:scripts\n[]',
    );
    expect(s.errors.first.toJson(), {
      'source': 'parser',
      'code': 'parse-failed',
      'message': 'Invalid scripts bundle',
    });
    expect(s.root!.props['value'], 1);
    expect(await click(s), isEmpty);
    expect(s.isStreaming, isTrue);
  });

  test('text that is not a program is a parse failure', () {
    final s = open('hello there');
    expect(s.errors.single.toJson(), {
      'source': 'parser',
      'code': 'parse-failed',
      'message': 'Response could not be parsed as valid openui-lang',
      'hint':
          'The entire response must be valid openui-lang code starting with root = Out(...)',
    });
    expect(open('').errors, isEmpty);
  });

  test('errors and issues are empty while the answer streams', () {
    final s = open('root = Nope()', streaming: true);
    expect(s.errors, isEmpty);
    expect(s.issues, isEmpty);

    s.update('root = Nope()', streaming: false);
    final error = s.errors.single;
    expect(error.code, OpenUiErrorCode.unknownComponent);
    expect(error.source, OpenUiErrorSource.parser);
    expect(error.statementId, 'root');
    expect(error.hint, 'Available components: Out');
  });

  test('onError reports each settled change once', () {
    final calls = <List<OpenUiError>>[];
    final s = OpenUiSession(_library, onError: calls.add);
    addTearDown(s.dispose);

    s.update('root = Out(1)', streaming: false);
    expect(calls, [[]]);

    s.update('root = Out(1)\n', streaming: true);
    expect(calls, [[], []]);

    s.update('root = Nope()', streaming: false);
    expect(calls, hasLength(3));
    expect(calls.last.single.code, OpenUiErrorCode.unknownComponent);

    s.update('root = Nope()', streaming: false);
    expect(calls, hasLength(3));
  });

  test(
    'onStateUpdate reports user and action changes, not the first load',
    () async {
      final states = <Map<String, Object?>>[];
      final s = OpenUiSession(_library, onStateUpdate: states.add);
      addTearDown(s.dispose);

      s.update(
        r'root = Out(1, @Set($n, 2))'
        '\n'
        r'$n = 1',
        streaming: false,
      );
      expect(states, isEmpty);

      await click(s);
      expect(states.single, {r'$n': 2});

      s.field('name', null).set('x');
      expect(states, hasLength(2));
      expect(states.last['name'], {'value': 'x'});
    },
  );

  test('setDefaultValue fills a missing field once, and only when settled', () {
    final s = open('root = Out(1)');
    s.setDefaultValue('city', 'Lisbon', componentType: 'Input');
    expect(s.state['city'], {'value': 'Lisbon', 'componentType': 'Input'});

    s.setDefaultValue('city', 'Porto', componentType: 'Input');
    expect(s.state['city'], {'value': 'Lisbon', 'componentType': 'Input'});

    s.setDefaultValue('zip', null);
    expect(s.state.containsKey('zip'), isFalse);

    final form = open('root = Out(1)');
    form.setDefaultValue(
      'city',
      'Lisbon',
      formName: 'f',
      componentType: 'Input',
    );
    expect(form.state['f'], {
      'city': {'value': 'Lisbon', 'componentType': 'Input'},
    });

    final streaming = open('root = Out(1)', streaming: true);
    streaming.setDefaultValue('city', 'Lisbon');
    expect(streaming.state.containsKey('city'), isFalse);
  });

  test(
    'a legacy open_url action sends its url and drops empty fields',
    () async {
      final s = open('root = Out(1, {type: "open_url", url: "", context: 0})');
      final events = await click(s);
      expect(events.single.type, 'open_url');
      expect(events.single.params, <String, Object?>{});
    },
  );

  test('a legacy action without a type continues the conversation', () async {
    final s = open('root = Out(1, {params: {a: 1}})');
    final events = await click(s, label: 'tap');
    expect(events.single.type, 'continue_conversation');
    expect(events.single.params, {'a': 1});
    expect(events.single.humanFriendlyMessage, 'tap');
  });

  test('a prop that throws reports the error through issues', () {
    final s = open('root = Out(@Boom(1))');
    expect(s.issues, [
      'Evaluating prop "value" on Out failed: @Boom threw: kaboom',
    ]);
  });

  test(
    'a component that fails to build is reported once through onError',
    () async {
      final reports = <List<Map<String, Object?>>>[];
      final s = OpenUiSession(
        _library,
        onError: (errors) => reports.add([for (final e in errors) e.toJson()]),
      );
      addTearDown(s.dispose);
      s.update('root = Out(1)', streaming: false);
      expect(reports, [<Map<String, Object?>>[]]);

      s.reportRenderError('Out', StateError('boom'));
      expect(reports, hasLength(1));
      await settle();
      expect(reports.last, [
        {
          'source': 'runtime',
          'code': 'render-error',
          'component': 'Out',
          'message': 'Component Out render failed: boom',
        },
      ]);

      s.reportRenderError('Out', StateError('boom'));
      await settle();
      expect(reports, hasLength(2));

      s.update('root = Out(2)', streaming: false);
      expect(reports, hasLength(3));
      expect(reports.last, isEmpty);

      s.update('root = Out(3)', streaming: true);
      expect(reports, hasLength(4));
      s.reportRenderError('Out', StateError('late'));
      await settle();
      s.update('root = Out(3)', streaming: false);
      expect(reports, hasLength(5));
      expect(reports.last, isEmpty);
    },
  );

  test(
    'onParseResult hears each new parse, not a repeat of the same program',
    () {
      final results = <ParseResult?>[];
      final s = OpenUiSession(_library, onParseResult: results.add);
      addTearDown(s.dispose);
      s.update('root = Out(1)', streaming: true);
      s.update('root = Out(1)\n]]', streaming: true);
      expect(results, hasLength(1));
      s.update('root = Out(1)', streaming: false);
      expect(results, hasLength(2));
      expect(results.last!.root!.typeName, 'Out');
    },
  );

  test('disposing from onParseResult stops initialization', () {
    late OpenUiSession session;
    final reports = <List<OpenUiError>>[];
    session = OpenUiSession(
      _library,
      onParseResult: (_) => session.dispose(),
      onError: reports.add,
    );
    addTearDown(session.dispose);
    session.update('root = Out(1)\n\$value = 2', streaming: false);
    expect(session.state, <String, Object?>{});
    expect(reports, <List<OpenUiError>>[]);
  });

  test(
    'swapped tools serve later calls; gaining or losing all tools refetches',
    () async {
      final s = open('root = Out(q)\nq = Query("t", {}, 0)');
      expect(s.root!.props['value'], 0);

      s.setTools([OpenUiTool(name: 't', call: (_) async => 'a')]);
      await settle();
      expect(s.root!.props['value'], 'a');

      s.setTools([OpenUiTool(name: 't', call: (_) async => 'b')]);
      expect(s.root!.props['value'], 'a');
      s.retryQueries();
      await settle();
      expect(s.root!.props['value'], 'b');

      s.setTools(const []);
      expect(s.root!.props['value'], 0);
    },
  );

  test('metadata names a framed response while it streams', () {
    final s = open(
      ']]>openui:content?name=Q3+report\nroot = Out(1)',
      streaming: true,
    );
    expect(s.metadata.name, 'Q3 report');
    expect(s.isGenerating, isTrue);
    s.update('root = Out(1)', streaming: false);
    expect(s.metadata.name, isNull);
    expect(s.isGenerating, isFalse);
  });

  test('a stored message renders its content', () {
    final s = open(
      buildMessage(content: 'root = Out("hi")', context: [{}], end: true),
    );
    expect(s.root!.props['value'], 'hi');
    expect(s.errors, isEmpty);
  });

  test(
    'a truncated default streams to the full statement without reporting state',
    () {
      final states = <Map<String, Object?>>[];
      final s = OpenUiSession(_library, onStateUpdate: states.add);
      addTearDown(s.dispose);
      s.update('root = Out(\$title)\n', streaming: true);
      s.update(
        'root = Out(\$title)\n\$title = "Quarterly rev',
        streaming: true,
      );
      s.update(
        'root = Out(\$title)\n\$title = "Quarterly revenue"\n',
        streaming: true,
      );
      expect(s.root!.props['value'], 'Quarterly revenue');
      expect(states, isEmpty);
    },
  );
}
