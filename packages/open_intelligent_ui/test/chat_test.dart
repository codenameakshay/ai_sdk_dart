import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/chat.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart' show ActionEvent;
import 'package:open_intelligent_ui/src/chat.dart' show formFields;

/// A model whose answers the test streams by hand, one call at a time.
final class _HandModel extends LanguageModelV4 {
  final calls = <StreamController<LanguageModelV4StreamPart>>[];

  void say(String text, {int call = -1}) {
    final c = call == -1 ? calls.last : calls[call];
    c.add(StreamPartTextDelta(id: 't', delta: text));
  }

  void finish() {
    calls.last
      ..add(const StreamPartTextEnd(id: 't'))
      ..add(
        const StreamPartFinish(
          finishReason: LanguageModelV4FinishReason.stop,
          rawFinishReason: 'stop',
        ),
      );
    unawaited(calls.last.close());
  }

  @override
  String get provider => 'hand';
  @override
  String get modelId => 'hand';
  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) => throw UnimplementedError();

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    final c = StreamController<LanguageModelV4StreamPart>()
      ..add(const StreamPartTextStart(id: 't'));
    calls.add(c);
    return LanguageModelV4StreamResult(stream: c.stream);
  }
}

String Function() _ids() {
  var n = 0;
  return () => 'm${++n}';
}

/// Runs [body] on the real event loop (streamText does not settle under the
/// test clock), lets the stream deliver, then pumps a frame.
Future<void> _real(WidgetTester tester, FutureOr<void> Function() body) async {
  await tester.runAsync(() async {
    await body();
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });
  await tester.pump();
}

final class _Harness {
  _Harness(this.controller, this.model, this.chat);
  final ChatController controller;
  final _HandModel model;
  final OpenUiChat chat;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  List<ModelMessage> initial = const [],
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final model = _HandModel();
  final agent = ToolLoopAgent(model: model);
  final controller = ChatController(
    generateId: _ids(),
    initialMessages: initial,
  );
  final chat = OpenUiChat(controller: controller, agent: agent);
  addTearDown(() {
    chat.dispose();
    controller.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AiChatScaffold(
          controller: controller,
          agent: agent,
          chatMessageBuilder: chat.buildMessage,
        ),
      ),
    ),
  );
  return _Harness(controller, model, chat);
}

const _greeting =
    r'root = Col([Input($name), Text("Hi " + $name)])'
    '\n'
    r'$name = "Ana"';

void main() {
  testWidgets('one session runs from the first token to the committed answer', (
    tester,
  ) async {
    final h = await _pump(tester);
    await _real(tester, () {
      unawaited(h.controller.sendMessage(agent: h.chat.agent, text: 'hello'));
    });
    await _real(tester, () => h.model.say(_greeting));
    expect(find.text('Hi Ana'), findsOneWidget);

    final id = h.controller.streamingMessageId!;
    final live = h.chat.sessionOf(id)!;
    expect(live.isStreaming, isTrue);

    await _real(tester, h.model.finish);
    expect(h.controller.status, ChatStatus.ready);
    expect(h.controller.chatMessages.last.id, id);
    expect(identical(h.chat.sessionOf(id), live), isTrue);
    expect(live.isStreaming, isFalse);
    expect(find.text('Hi Ana'), findsOneWidget);
  });

  testWidgets('an edit is written into the answer for the next turn', (
    tester,
  ) async {
    final h = await _pump(
      tester,
      initial: const [
        ModelMessage(role: ModelMessageRole.user, content: 'hello'),
        ModelMessage(role: ModelMessageRole.assistant, content: _greeting),
      ],
    );
    await tester.enterText(find.byType(TextField).first, 'Bo');
    await tester.pump();

    expect(find.text('Hi Bo'), findsOneWidget);
    expect(
      h.controller.messages[1].content,
      ']]>openui:content\n$_greeting\n]]>openui:context\n[{"\$name":"Bo"}]',
    );
    expect(h.controller.chatMessages[1].id, 'm2');
  });

  testWidgets('clear restores the initial answer state', (tester) async {
    final h = await _pump(
      tester,
      initial: const [
        ModelMessage(role: ModelMessageRole.assistant, content: _greeting),
      ],
    );
    await tester.enterText(find.byType(TextField).first, 'Bo');
    await tester.pump();
    expect(find.text('Hi Bo'), findsOneWidget);

    h.controller.clear();
    await tester.pump();
    expect(find.text('Hi Ana'), findsOneWidget);
    expect(h.controller.messages.single.content, _greeting);
  });

  testWidgets('clear cancels an edit waiting to be saved', (tester) async {
    final h = await _pump(
      tester,
      initial: const [
        ModelMessage(role: ModelMessageRole.assistant, content: _greeting),
      ],
    );
    final session = h.chat.sessionOf(h.controller.chatMessages.single.id)!;
    final input = session.root!.props.elements('children').first;
    session.field('name', input.props['value']).set('Bo');
    h.controller.clear();
    await tester.pump();

    expect(find.text('Hi Ana'), findsOneWidget);
    expect(h.controller.messages.single.content, _greeting);
    expect(h.chat.sessionOf(h.controller.chatMessages.single.id)!.state, {
      r'$name': 'Ana',
    });
  });

  testWidgets('a replaced answer restores its new state and accepts edits', (
    tester,
  ) async {
    final h = await _pump(
      tester,
      initial: const [
        ModelMessage(role: ModelMessageRole.assistant, content: _greeting),
      ],
    );
    final id = h.controller.chatMessages.single.id;
    h.controller.updateMessage(
      id,
      const ModelMessage(
        role: ModelMessageRole.assistant,
        content:
            ']]>openui:content\n$_greeting\n]]>openui:context\n'
            '[{"\$name":"Zed"}]',
      ),
    );
    await tester.pump();
    expect(find.text('Hi Zed'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Cy');
    await tester.pump();
    expect(find.text('Hi Cy'), findsOneWidget);
    expect(
      h.controller.messages.single.content,
      ']]>openui:content\n$_greeting\n]]>openui:context\n'
      '[{"\$name":"Cy"}]',
    );
  });

  testWidgets('a superseded streaming answer drops its session immediately', (
    tester,
  ) async {
    final h = await _pump(tester);
    await _real(tester, () {
      unawaited(h.controller.sendMessage(agent: h.chat.agent, text: 'first'));
    });
    await _real(tester, () => h.model.say(_greeting));
    final firstId = h.controller.streamingMessageId!;
    expect(h.chat.sessionOf(firstId), isNotNull);

    await _real(tester, () {
      unawaited(h.controller.sendMessage(agent: h.chat.agent, text: 'second'));
    });
    expect(h.controller.isLoading, isTrue);
    expect(h.chat.sessionOf(firstId), isNull);
    await _real(tester, h.model.finish);
  });

  testWidgets('a restored answer starts from its saved state', (tester) async {
    await _pump(
      tester,
      initial: const [
        ModelMessage(
          role: ModelMessageRole.assistant,
          content:
              ']]>openui:content\n$_greeting\n]]>openui:context\n'
              '[{"\$name":"Zed"}]',
        ),
      ],
    );
    expect(find.text('Hi Zed'), findsOneWidget);
  });

  testWidgets('an edit while streaming is saved once the answer commits', (
    tester,
  ) async {
    final h = await _pump(tester);
    await _real(tester, () {
      unawaited(h.controller.sendMessage(agent: h.chat.agent, text: 'hello'));
    });
    await _real(tester, () => h.model.say(_greeting));
    await tester.enterText(find.byType(TextField).first, 'Cy');
    await tester.pump();
    expect(h.controller.messages, hasLength(1));

    await _real(tester, h.model.finish);
    await _real(tester, () {});
    expect(
      h.controller.messages.last.content,
      ']]>openui:content\n$_greeting\n]]>openui:context\n[{"\$name":"Cy"}]',
    );
  });

  testWidgets('a streaming edit is saved when its row is no longer mounted', (
    tester,
  ) async {
    final h = await _pump(tester);
    await _real(tester, () {
      unawaited(h.controller.sendMessage(agent: h.chat.agent, text: 'hello'));
    });
    await _real(tester, () => h.model.say(_greeting));
    await tester.enterText(find.byType(TextField).first, 'Cy');
    await tester.pump();
    await tester.pumpWidget(const SizedBox());

    await _real(tester, h.model.finish);
    expect(h.controller.status, ChatStatus.ready);
    expect(
      h.controller.messages.last.content,
      ']]>openui:content\n$_greeting\n]]>openui:context\n[{"\$name":"Cy"}]',
    );
  });

  testWidgets('@ToAssistant sends the click and form state as the next turn', (
    tester,
  ) async {
    const program =
        r'root = Form([RadioGroup($pace, ["Relaxed", "Packed"], "Pace"), '
        r'Button("Plan my trip", @ToAssistant("Tailor my Lisbon trip"))])'
        '\n'
        r'$pace = "Relaxed"';
    final h = await _pump(
      tester,
      initial: const [
        ModelMessage(role: ModelMessageRole.assistant, content: program),
      ],
    );
    await tester.tap(find.text('Packed'));
    await tester.pump();
    await _real(tester, () => tester.tap(find.text('Plan my trip')));

    expect(h.controller.messages[1].role, ModelMessageRole.user);
    expect(
      h.controller.messages[1].content,
      ']]>openui:content\nTailor my Lisbon trip\n]]>openui:context\n'
      '["User clicked: Tailor my Lisbon trip",{"\$pace":"Packed"}]',
    );
    expect(find.text('Tailor my Lisbon trip'), findsOneWidget);
    expect(find.textContaining(']]>openui:'), findsNothing);

    await _real(tester, () => tester.tap(find.text('Plan my trip')));
    expect(
      h.controller.messages.where((m) => m.role == ModelMessageRole.user),
      hasLength(1),
      reason: 'a click while an answer is loading is ignored',
    );
    await _real(tester, h.model.finish);
    expect(h.controller.status, ChatStatus.ready);
  });

  testWidgets('a plain streaming action edit is saved at commit', (
    tester,
  ) async {
    const program =
        r'root = Col([Button("Change", @Set($name, "Cy")), Text($name)])'
        '\n'
        r'$name = "Ana"';
    final h = await _pump(tester);
    await _real(tester, () {
      unawaited(h.controller.sendMessage(agent: h.chat.agent, text: 'hello'));
    });
    await _real(tester, () => h.model.say(program));
    final session = h.chat.sessionOf(h.controller.streamingMessageId!)!;
    final button = session.root!.props.elements('children').first;
    await session.run(
      button.props.action('action'),
      label: 'Change',
      emit: (_) {},
    );
    await tester.pump();
    expect(find.text('Cy'), findsOneWidget);
    await _real(tester, h.model.finish);
    expect(
      h.controller.messages.last.content,
      ']]>openui:content\n$program\n]]>openui:context\n[{"\$name":"Cy"}]',
    );
  });

  testWidgets('saved edits preserve Cloud sections and replace only context', (
    tester,
  ) async {
    const raw =
        ']]>openui:content?name=Form\n$_greeting\n'
        ']]>openui:scripts{"count":0}\n[]\n]]>openui:end';
    final h = await _pump(
      tester,
      initial: const [
        ModelMessage(
          role: ModelMessageRole.assistant,
          content: '$raw\n]]>openui:context\n[{"\$name":"Zed"}]',
        ),
      ],
    );
    var writes = 0;
    h.controller.addListener(() => writes++);
    expect(find.text('Hi Zed'), findsOneWidget);
    for (final name in ['Bo', 'Cy']) {
      await tester.enterText(find.byType(TextField).first, name);
      await tester.pump();
      expect(
        h.controller.messages.single.content,
        '$raw\n]]>openui:context\n[{"\$name":"$name"}]',
      );
    }
    await tester.pump();
    expect(writes, 2);
    expect(
      h.chat.sessionOf(h.controller.chatMessages.single.id)!.isStreaming,
      isFalse,
    );
  });

  testWidgets('Cloud framing blocks actions until the answer commits', (
    tester,
  ) async {
    final h = await _pump(tester);
    await _real(tester, () {
      unawaited(h.controller.sendMessage(agent: h.chat.agent, text: 'hello'));
    });
    await _real(
      tester,
      () => h.model.say(
        ']]>openui:content\nroot = Button("Go", @ToAssistant("go"))',
      ),
    );
    final session = h.chat.sessionOf(h.controller.streamingMessageId!)!;
    final events = <ActionEvent>[];
    await session.run(
      session.root!.props.action('action'),
      label: 'Go',
      emit: events.add,
    );
    expect(events, isEmpty);
    await _real(tester, h.model.finish);
    await session.run(
      session.root!.props.action('action'),
      label: 'Go',
      emit: events.add,
    );
    expect(events.single.humanFriendlyMessage, 'go');
  });

  testWidgets('invalid scripts remain blocked and survive saved edits', (
    tester,
  ) async {
    const raw =
        ']]>openui:content?name=Form\n$_greeting\n'
        ']]>openui:scripts\n[]\n]]>openui:end';
    final h = await _pump(
      tester,
      initial: const [
        ModelMessage(role: ModelMessageRole.assistant, content: raw),
      ],
    );
    final session = h.chat.sessionOf(h.controller.chatMessages.single.id)!;
    expect(session.isStreaming, isTrue);
    expect(session.errors.single.message, 'Invalid scripts bundle');
    await tester.enterText(find.byType(TextField).first, 'Bo');
    await tester.pump();
    expect(
      h.controller.messages.single.content,
      '$raw\n]]>openui:context\n[{"\$name":"Bo"}]',
    );
    expect(session.isStreaming, isTrue);
    expect(session.errors.single.message, 'Invalid scripts bundle');
  });

  testWidgets('an answer that is not a program renders as prose', (
    tester,
  ) async {
    await _pump(
      tester,
      initial: const [
        ModelMessage(
          role: ModelMessageRole.assistant,
          content: 'Sorry, I cannot help with that.',
        ),
      ],
    );
    expect(find.text('Sorry, I cannot help with that.'), findsOneWidget);
  });

  testWidgets('reload drops the replaced answer session', (tester) async {
    final h = await _pump(
      tester,
      initial: const [
        ModelMessage(role: ModelMessageRole.user, content: 'hello'),
      ],
    );
    await _real(tester, () {
      unawaited(h.controller.reload(agent: h.chat.agent));
    });
    await _real(tester, () {
      h.model.say(_greeting);
      h.model.finish();
    });
    final first = h.controller.chatMessages.last.id;
    final session = h.chat.sessionOf(first)!;
    expect(session.root, isNotNull);

    await _real(tester, () {
      unawaited(h.controller.reload(agent: h.chat.agent));
    });
    expect(h.model.calls, hasLength(2));
    expect(h.chat.sessionOf(first), isNull);
    await _real(tester, h.model.finish);
    expect(h.controller.status, ChatStatus.ready);
  });

  testWidgets('a failed answer drops its streaming session', (tester) async {
    final h = await _pump(tester);
    await _real(tester, () {
      unawaited(h.controller.sendMessage(agent: h.chat.agent, text: 'hello'));
    });
    await _real(tester, () => h.model.say(_greeting));
    final id = h.controller.streamingMessageId!;
    expect(h.chat.sessionOf(id), isNotNull);

    await _real(
      tester,
      () => h.model.calls.last.add(StreamPartError(error: StateError('drop'))),
    );
    expect(h.controller.status, ChatStatus.error);
    expect(h.chat.sessionOf(id), isNull);
  });

  testWidgets('messages that are not plain text use the default widgets', (
    tester,
  ) async {
    await _pump(
      tester,
      initial: [
        ModelMessage.parts(
          role: ModelMessageRole.user,
          parts: const [LanguageModelV4TextPart(text: 'part text')],
        ),
        ModelMessage.parts(
          role: ModelMessageRole.assistant,
          parts: const [LanguageModelV4TextPart(text: 'assistant part')],
        ),
      ],
    );
    expect(find.text('part text'), findsOneWidget);
    expect(find.text('assistant part'), findsOneWidget);
  });

  testWidgets('a user turn folds its form values', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OpenUiUserMessage(
            text:
                ']]>openui:content\nBook it\n]]>openui:context\n'
                '["User clicked: Book it",'
                '{"trip":{"city":{"value":"Lisbon","componentType":"Input"},'
                '"notes":{"value":"","componentType":"TextArea"}}}]',
          ),
        ),
      ),
    );
    expect(find.text('Book it'), findsOneWidget);
    expect(find.text('Form data (1 field)'), findsOneWidget);
    expect(find.text('city: Lisbon'), findsNothing);
    await tester.tap(find.text('Form data (1 field)'));
    await tester.pump();
    expect(find.text('city: Lisbon'), findsOneWidget);
  });

  group('formFields', () {
    test('reads flat fields and skips empty values', () {
      expect(
        formFields({
          'a': {'value': 2, 'componentType': 'Slider'},
          'b': {'value': null},
          r'$x': 'not a field',
        }),
        [('a', '2')],
      );
    });

    test('reads fields nested by form name from a context list', () {
      expect(
        formFields([
          'User clicked: Go',
          {
            'f': {
              'tags': {
                'value': ['a', 'b'],
              },
            },
            'skip': 3,
          },
        ]),
        [('tags', 'a,b')],
      );
    });

    test('has no fields without an object', () {
      expect(formFields('text'), isEmpty);
      expect(formFields(null), isEmpty);
    });
  });

  group('actionUserMessage', () {
    test('sends the message with the click and form state', () {
      const event = ActionEvent(
        type: ActionEvent.continueConversation,
        humanFriendlyMessage: 'Tailor my Lisbon trip',
        formState: {
          'prefs': {
            'pace': {'value': 'Packed', 'componentType': 'RadioGroup'},
          },
        },
        formName: 'prefs',
      );
      expect(
        actionUserMessage(event),
        ']]>openui:content\nTailor my Lisbon trip\n]]>openui:context\n'
        '["User clicked: Tailor my Lisbon trip",'
        '{"prefs":{"pace":{"value":"Packed","componentType":"RadioGroup"}}}]',
      );
    });

    test('appends the action context after the form state', () {
      const event = ActionEvent(
        type: ActionEvent.continueConversation,
        params: {
          'context': {'orderId': 42},
        },
        humanFriendlyMessage: 'Show details',
      );
      expect(
        actionUserMessage(event),
        ']]>openui:content\nShow details\n]]>openui:context\n'
        '["User clicked: Show details",{},{"orderId":42}]',
      );
    });

    test('includes an explicitly null action context', () {
      const event = ActionEvent(
        type: ActionEvent.continueConversation,
        params: {'context': null},
        humanFriendlyMessage: 'Continue',
      );
      expect(
        actionUserMessage(event),
        ']]>openui:content\nContinue\n]]>openui:context\n'
        '["User clicked: Continue",{},null]',
      );
    });

    test('drops the content line when there is no message', () {
      const event = ActionEvent(type: ActionEvent.continueConversation);
      expect(
        actionUserMessage(event),
        '\n]]>openui:context\n["User clicked: ",{}]',
      );
    });
  });
}
