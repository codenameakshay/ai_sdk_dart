import 'dart:async';

import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:ai_sdk_openui/intelligent_ui.dart';
import 'package:test/test.dart';

OpenUiSession session(
  String program, {
  List<OpenUiTool> tools = const [],
  Map<String, Object?> state = const {},
}) {
  final s = OpenUiSession(intelligentUi, tools: tools, initialState: state)
    ..update(program, streaming: false);
  addTearDown(s.dispose);
  return s;
}

OpenUiElement child(OpenUiElement e, [int i = 0]) =>
    e.props.elements('children')[i];

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('streaming', () {
    test('a reference not defined yet renders nothing until it streams in', () {
      final s = OpenUiSession(intelligentUi);
      addTearDown(s.dispose);
      s.update(
        'root = Col([title, body])\ntitle = Title("Hi")',
        streaming: true,
      );
      expect(s.root!.props.elements('children').map((e) => e.typeName), [
        'Title',
      ]);
      s.update(
        'root = Col([title, body])\ntitle = Title("Hi")\nbody = Text("There")',
        streaming: false,
      );
      expect(s.root!.props.elements('children').map((e) => e.typeName), [
        'Title',
        'Text',
      ]);
    });

    test('a half-written string still renders, then completes', () {
      final s = OpenUiSession(intelligentUi);
      addTearDown(s.dispose);
      s.update('root = Col([Title("Lis', streaming: true);
      expect(child(s.root!).props.string('text'), 'Lis');
      s.update('root = Col([Title("Lisbon")])', streaming: false);
      expect(child(s.root!).props.string('text'), 'Lisbon');
    });

    test('a ternary picks between components by state', () {
      final s = session(
        r'root = Col([Checkbox($on, "On"), $on ? Badge("yes") : Text("no")])'
        '\n'
        r'$on = false',
      );
      expect(child(s.root!, 1).typeName, 'Text');
      s.field('', child(s.root!).props['checked']).set(true);
      expect(child(s.root!, 1).typeName, 'Badge');
    });
  });

  group('state', () {
    test(r'a $binding input writes its variable through the field', () {
      final s = session(
        r'root = Col([Input($name), Text("Hi " + $name)])'
        '\n'
        r'$name = "Ana"',
      );
      final input = child(s.root!);
      final field = s.field('n', input.props['value']);
      expect(field.value, 'Ana');
      field.set('Bo');
      expect(s.state[r'$name'], 'Bo');
      expect(child(s.root!, 1).props['text'], 'Hi Bo');
    });

    test(
      'untouched variables follow new defaults while streaming; touched ones stay',
      () {
        final s = OpenUiSession(intelligentUi);
        addTearDown(s.dispose);
        const program = r'root = Col([Input($a), Input($b)])';
        s.update('$program\n\$a = "1"\n\$b = "1"', streaming: true);
        s.field('', child(s.root!, 1).props['value']).set('typed');
        s.update('$program\n\$a = "2"\n\$b = "2"', streaming: false);
        expect(s.state[r'$a'], '2');
        expect(s.state[r'$b'], 'typed');
      },
    );

    test('@Reset restores declared defaults', () async {
      final s = session(
        r'root = Col([b])'
        '\n'
        r'b = Button("go", Action([@Set($n, 5), @Reset($n)]))'
        '\n'
        r'$n = 1',
      );
      final action = child(s.root!).props.action('action');
      await s.run(action, label: 'go', emit: (_) {});
      expect(s.state[r'$n'], 1);
    });

    test('initial state restores a saved page', () {
      final s = session(
        r'root = Col([Text("n=" + $n)])'
        '\n'
        r'$n = 1',
        state: {r'$n': 7},
      );
      expect(child(s.root!).props['text'], 'n=7');
    });
  });

  group('actions', () {
    test('@Each captures the loop item in deferred @Set steps', () async {
      final s = session(
        r'root = Col(@Each(["a", "b"], "x", Button(x, @Set($pick, x))))'
        '\n'
        r'$pick = ""',
      );
      await s.run(
        child(s.root!, 1).props.action('action'),
        label: 'b',
        emit: (_) {},
      );
      expect(s.state[r'$pick'], 'b');
    });

    test(
      'a Button without an action sends its label to the assistant',
      () async {
        final s = session('root = Col([Button("Tell me more")])');
        final events = <ActionEvent>[];
        await s.run(
          child(s.root!).props.action('action'),
          label: 'Tell me more',
          emit: events.add,
        );
        expect(events.single.type, ActionEvent.continueConversation);
        expect(events.single.humanFriendlyMessage, 'Tell me more');
      },
    );

    test(
      '@ToAssistant inside a Form carries the form fields and its context',
      () async {
        final s = session(
          'root = Col([f])\nf = Form([Input("", "Name"), b])\n'
          'b = Button("Send", @ToAssistant("Help me", {id: 4}))',
        );
        final form = child(s.root!);
        final input = form.props.elements('children')[0];
        s
            .field(
              'Name',
              input.props['value'],
              formName: 'f',
              componentType: 'Input',
            )
            .set('Ana');
        final events = <ActionEvent>[];
        await s.run(
          form.props.elements('children')[1].props.action('action'),
          label: 'Send',
          formName: 'f',
          emit: events.add,
        );
        expect(events.single.humanFriendlyMessage, 'Help me');
        expect(events.single.params, {
          'context': {'id': 4},
        });
        expect(events.single.formName, 'f');
        expect(events.single.formState, {
          'f': {
            'Name': {'value': 'Ana', 'componentType': 'Input'},
          },
        });
      },
    );

    test(
      'steps run in order; library action params are read at render time, @Set values at click time',
      () async {
        final s = session(
          r'root = Col([b])'
          '\n'
          r'b = Button("go", Action([@Set($n, $n + 1), @CopyToClipboard("n=" + $n), @OpenUrl("https://x.org")]))'
          '\n'
          r'$n = 1',
        );
        final events = <ActionEvent>[];
        await s.run(
          child(s.root!).props.action('action'),
          label: 'go',
          emit: events.add,
        );
        expect(s.state[r'$n'], 2);
        expect(
          [for (final e in events) e.type],
          ['CopyToClipboard', ActionEvent.openUrl],
        );
        expect(events[0].params, {'text': 'n=1'});
        expect(events[1].params, {'url': 'https://x.org'});
      },
    );

    test('a legacy action object becomes an event with its params', () async {
      final s = session(
        'root = Col([Button("go", {type: "open_url", url: "https://x.org"})])',
      );
      final events = <ActionEvent>[];
      await s.run(
        child(s.root!).props.action('action'),
        label: 'go',
        emit: events.add,
      );
      expect(events.single.type, 'open_url');
      expect(events.single.params, {'url': 'https://x.org'});
    });
  });

  group('queries', () {
    test(
      'a Query shows its defaults, then the tool data, and refetches when its args change',
      () async {
        final calls = <Map<String, Object?>>[];
        final tool = OpenUiTool(
          name: 'count',
          call: (args) async {
            calls.add(args);
            return {'n': (args['k'] as num) * 10};
          },
        );
        final s = session(
          r'root = Col([Text("n=" + q.n), Input($k)])'
          '\n'
          r'q = Query("count", {k: $k}, {n: 0})'
          '\n'
          r'$k = 1',
          tools: [tool],
        );
        expect(child(s.root!).props['text'], 'n=0');
        await settle();
        expect(child(s.root!).props['text'], 'n=10');
        s.field('', child(s.root!, 1).props['value']).set(2);
        await settle();
        expect(child(s.root!).props['text'], 'n=20');
        expect(calls, [
          {'k': 1},
          {'k': 2},
        ]);
      },
    );

    test('a missing tool is a query issue, and the defaults stay', () async {
      final s = session(
        r'root = Col([Text("n=" + q.n)])'
        '\n'
        r'q = Query("nope", {}, {n: 0})',
        tools: demoTools(),
      );
      await settle();
      expect(child(s.root!).props['text'], 'n=0');
      expect(s.issues.single, 'Query tool "nope" not found');
    });

    test('queries wait until the program stops streaming', () async {
      var calls = 0;
      final s = OpenUiSession(
        intelligentUi,
        tools: [
          OpenUiTool(
            name: 't',
            call: (_) async {
              calls++;
              return {'n': 1};
            },
          ),
        ],
      );
      addTearDown(s.dispose);
      s.update(
        'root = Col([Text("" + q.n)])\nq = Query("t", {}, {n: 0})',
        streaming: true,
      );
      await settle();
      expect(calls, 0);
      s.update(
        'root = Col([Text("" + q.n)])\nq = Query("t", {}, {n: 0})',
        streaming: false,
      );
      await settle();
      expect(calls, 1);
    });

    test('a failed Mutation stops the plan', () async {
      final s = session(
        r'root = Col([b])'
        '\n'
        r'm = Mutation("save", {})'
        '\n'
        r'b = Button("go", Action([@Run(m), @Set($done, true)]))'
        '\n'
        r'$done = false',
        tools: [
          OpenUiTool(name: 'save', call: (_) async => throw StateError('down')),
        ],
      );
      await s.run(
        child(s.root!).props.action('action'),
        label: 'go',
        emit: (_) {},
      );
      expect(s.state[r'$done'], false);
      expect(s.issues.single, startsWith('Mutation "save" failed'));
    });
  });

  test('the server check reports what is wrong with a program', () {
    final report = intelligentUi.parse('root = Col([Nope("x"), missing])');
    expect(report.isClean, isFalse);
    expect(report.errors.single, startsWith('Unknown component "Nope"'));
    expect(report.unresolved, ['missing']);
  });

  test(
    'the demo tools read a day count from a string, as JavaScript Number() does',
    () async {
      final tool = demoTools(
        now: () => DateTime.utc(2026, 11, 8),
      ).firstWhere((t) => t.name == 'get_traffic');
      final thirty = (await tool.call({'days': '30'}) as Map)['rows'] as List;
      final ninety = (await tool.call(const {}) as Map)['rows'] as List;
      expect(thirty.length, 30 * 5);
      expect(ninety.length, 90 * 5);
      expect((thirty.last as Map)['date'], '2026-11-08');
    },
  );
}
