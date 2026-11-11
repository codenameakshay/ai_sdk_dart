// ignore_for_file: implementation_imports
import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_openui/ai_sdk_openui.dart'
    show
        OpenUiAnswers,
        OpenUiMessageEvent,
        OpenUiTextDelta,
        OpenUiMessageDone,
        buildActionUserMessage;
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui_core/open_intelligent_ui_core.dart' as core;
import 'package:open_intelligent_ui/chat.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart'
    show ActionEvent, intelligentUi;
import 'package:open_intelligent_ui_chat/src/chat.dart' show formFields;

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
  ChatController? controller,
  Future<void> Function(String text)? send,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final model = _HandModel();
  final agent = ToolLoopAgent(model: model);
  final transcript =
      controller ??
      ChatController(generateId: _ids(), initialMessages: initial);
  final chat = OpenUiChat(
    controller: transcript,
    agent: send == null ? agent : null,
    send: send,
  );
  addTearDown(() {
    chat.dispose();
    transcript.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AiChatScaffold(
          controller: transcript,
          agent: agent,
          chatMessageBuilder: chat.buildMessage,
        ),
      ),
    ),
  );
  return _Harness(transcript, model, chat);
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
      unawaited(h.controller.sendMessage(agent: h.chat.agent!, text: 'hello'));
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
      unawaited(h.controller.sendMessage(agent: h.chat.agent!, text: 'first'));
    });
    await _real(tester, () => h.model.say(_greeting));
    final firstId = h.controller.streamingMessageId!;
    expect(h.chat.sessionOf(firstId), isNotNull);

    await _real(tester, () {
      unawaited(h.controller.sendMessage(agent: h.chat.agent!, text: 'second'));
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
      unawaited(h.controller.sendMessage(agent: h.chat.agent!, text: 'hello'));
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
      unawaited(h.controller.sendMessage(agent: h.chat.agent!, text: 'hello'));
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
      unawaited(h.controller.sendMessage(agent: h.chat.agent!, text: 'hello'));
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
      unawaited(h.controller.sendMessage(agent: h.chat.agent!, text: 'hello'));
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
      unawaited(h.controller.reload(agent: h.chat.agent!));
    });
    await _real(tester, () {
      h.model.say(_greeting);
      h.model.finish();
    });
    final first = h.controller.chatMessages.last.id;
    final session = h.chat.sessionOf(first)!;
    expect(session.root, isNotNull);

    await _real(tester, () {
      unawaited(h.controller.reload(agent: h.chat.agent!));
    });
    expect(h.model.calls, hasLength(2));
    expect(h.chat.sessionOf(first), isNull);
    await _real(tester, h.model.finish);
    expect(h.controller.status, ChatStatus.ready);
  });

  testWidgets('a failed answer drops its streaming session', (tester) async {
    final h = await _pump(tester);
    await _real(tester, () {
      unawaited(h.controller.sendMessage(agent: h.chat.agent!, text: 'hello'));
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

  testWidgets('a send transport renders an answer from a plain event stream', (
    tester,
  ) async {
    final events = StreamController<OpenUiMessageEvent>();
    addTearDown(events.close);
    late _Harness h;
    Future<void> relay(String text) async {
      h.controller
        ..append(ModelMessage(role: ModelMessageRole.user, content: text))
        ..append(
          const ModelMessage(role: ModelMessageRole.assistant, content: ''),
        );
      final id = h.controller.chatMessages.last.id;
      var raw = '';
      await for (final event in events.stream) {
        if (event is OpenUiTextDelta) raw += event.delta;
        h.controller.updateMessage(
          id,
          ModelMessage(role: ModelMessageRole.assistant, content: raw),
        );
        if (event is OpenUiMessageDone) return;
      }
    }

    h = await _pump(
      tester,
      initial: const [
        ModelMessage(
          role: ModelMessageRole.assistant,
          content: r'root = Col([Button("Go", @ToAssistant("go"))])',
        ),
      ],
      send: relay,
    );
    await tester.tap(find.text('Go'));
    await tester.pump();

    await _real(
      tester,
      () => events.add(
        const OpenUiTextDelta(
          'm3',
          'root = Col([Input(\$name), Text("Hi " + \$name)])\n',
        ),
      ),
    );
    expect(
      h.chat.sessionOf(h.controller.chatMessages.last.id)!.root,
      isNotNull,
    );

    await _real(
      tester,
      () => events.add(const OpenUiTextDelta('m3', r'$name = "Ana"')),
    );
    await _real(tester, () => events.add(const OpenUiMessageDone('m3')));
    expect(find.text('Hi Ana'), findsOneWidget);
  });

  testWidgets('a new chat over a saved transcript shows the saved state', (
    tester,
  ) async {
    final first = await _pump(
      tester,
      initial: const [
        ModelMessage(role: ModelMessageRole.assistant, content: _greeting),
      ],
    );
    await tester.enterText(find.byType(TextField).first, 'Bo');
    await tester.pump();

    await _pump(tester, initial: first.controller.messages);
    expect(find.text('Hi Bo'), findsOneWidget);
  });

  testWidgets('an answer stored as text parts renders and saves edits', (
    tester,
  ) async {
    final h = await _pump(
      tester,
      initial: [
        const ModelMessage(role: ModelMessageRole.user, content: 'hello'),
        ModelMessage.parts(
          role: ModelMessageRole.assistant,
          parts: const [LanguageModelV4TextPart(text: _greeting)],
        ),
      ],
    );
    expect(find.text('Hi Ana'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Bo');
    await tester.pump();
    expect(
      h.controller.messages[1].content,
      ']]>openui:content\n$_greeting\n]]>openui:context\n[{"\$name":"Bo"}]',
    );
  });

  testWidgets('send carries @ToAssistant turns without an agent', (
    tester,
  ) async {
    final sent = <String>[];
    await _pump(
      tester,
      initial: const [
        ModelMessage(
          role: ModelMessageRole.assistant,
          content:
              r'root = Col([Button("More", @ToAssistant("Tell me more"))])',
        ),
      ],
      send: (text) async => sent.add(text),
    );
    await tester.tap(find.text('More'));
    await tester.pump();
    expect(sent.single, contains('Tell me more'));
    expect(sent.single, contains('User clicked: Tell me more'));
  });

  testWidgets('send ignores a second click while the transport is pending', (
    tester,
  ) async {
    final sent = <String>[];
    final pendingSends = <Completer<void>>[];
    await _pump(
      tester,
      initial: const [
        ModelMessage(
          role: ModelMessageRole.assistant,
          content:
              r'root = Col([Button("More", @ToAssistant("Tell me more"))])',
        ),
      ],
      send: (text) {
        sent.add(text);
        final pendingSend = Completer<void>();
        pendingSends.add(pendingSend);
        return pendingSend.future;
      },
    );

    await tester.tap(find.text('More'));
    await tester.pump();
    await tester.tap(find.text('More'));
    await tester.pump();

    expect(sent, hasLength(1));
    pendingSends.single.complete();
    await tester.pump();
    await tester.tap(find.text('More'));
    await tester.pump();
    expect(sent, hasLength(2));
    pendingSends.last.complete();
  });

  testWidgets('a failed send can be retried without hiding its error', (
    tester,
  ) async {
    var attempts = 0;
    await _pump(
      tester,
      initial: const [
        ModelMessage(
          role: ModelMessageRole.assistant,
          content:
              r'root = Col([Button("More", @ToAssistant("Tell me more"))])',
        ),
      ],
      send: (_) async {
        attempts++;
        if (attempts == 1) throw StateError('offline');
      },
    );

    final callback = tester
        .widget<core.OpenUiView>(find.byType(core.OpenUiView))
        .onToAssistant!;
    final errors = <Object>[];
    final failed = Completer<void>();
    runZonedGuarded(
      () => callback(
        const ActionEvent(
          type: ActionEvent.continueConversation,
          humanFriendlyMessage: 'Tell me more',
        ),
      ),
      (error, _) {
        errors.add(error);
        failed.complete();
      },
    );
    await failed.future;
    expect(errors.single, isA<StateError>());

    await tester.tap(find.text('More'));
    await tester.pump();
    expect(attempts, 2);
  });

  test('OpenUiChat needs an agent or a send function', () {
    final controller = ChatController();
    addTearDown(controller.dispose);
    expect(() => OpenUiChat(controller: controller), throwsArgumentError);
  });

  testWidgets('OpenUiAnswerView renders a message from any transport', (
    tester,
  ) async {
    final saved = <String, String>{};
    final answers = OpenUiAnswers(
      library: intelligentUi,
      onSave: (id, text) => saved[id] = text,
    );
    addTearDown(answers.dispose);

    answers.append('m1', _greeting);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OpenUiAnswerView(answers: answers, id: 'm1'),
        ),
      ),
    );
    expect(find.text('Hi Ana'), findsOneWidget);

    answers.finish('m1');
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'Bo');
    await tester.pump();
    expect(saved['m1'], endsWith('[{"\$name":"Bo"}]'));

    answers.update('m2', 'Just text', streaming: false);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OpenUiAnswerView(answers: answers, id: 'm2'),
        ),
      ),
    );
    expect(find.text('Just text'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OpenUiAnswerView(answers: answers, id: 'missing'),
        ),
      ),
    );
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('OpenUiAnswerView renders completed prose from an empty stream', (
    tester,
  ) async {
    final answers = OpenUiAnswers(library: intelligentUi);
    addTearDown(answers.dispose);
    answers.update('m1', '', streaming: true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OpenUiAnswerView(answers: answers, id: 'm1'),
        ),
      ),
    );

    answers.append('m1', 'Plain response');
    answers.finish('m1');
    await tester.pump();

    expect(find.text('Plain response'), findsOneWidget);
  });

  testWidgets('OpenUiAnswerView draws prose fences with its fallback '
      'services', (tester) async {
    final answers = OpenUiAnswers(library: intelligentUi);
    addTearDown(answers.dispose);
    answers.update(
      'm1',
      'Here is **the** chart:\n\n```chart\n{"a":1}\n```',
      streaming: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OpenUiAnswerView(
            answers: answers,
            id: 'm1',
            fallbackServices: core.OpenUiServices(
              markdownFences: {
                'chart': (context, fence) => Text('chart:${fence.body}'),
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('Here is the chart:'), findsOneWidget);
    expect(find.text('chart:{"a":1}'), findsOneWidget);
    expect(find.text('{"a":1}'), findsNothing);
  });

  testWidgets('OpenUiAnswerView switches a program to prose reactively', (
    tester,
  ) async {
    final answers = OpenUiAnswers(library: intelligentUi);
    addTearDown(answers.dispose);
    answers.update('m1', _greeting, streaming: false);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OpenUiAnswerView(answers: answers, id: 'm1'),
        ),
      ),
    );
    expect(find.text('Hi Ana'), findsOneWidget);

    answers.update('m1', 'Plain response', streaming: false);
    await tester.pump();

    expect(find.text('Plain response'), findsOneWidget);
  });

  testWidgets('OpenUiAnswerView switches prose to a program reactively', (
    tester,
  ) async {
    final answers = OpenUiAnswers(library: intelligentUi);
    addTearDown(answers.dispose);
    answers.update('m1', 'Plain response', streaming: false);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OpenUiAnswerView(answers: answers, id: 'm1'),
        ),
      ),
    );
    expect(find.text('Plain response'), findsOneWidget);

    answers.update('m1', _greeting, streaming: false);
    await tester.pump();

    expect(find.text('Hi Ana'), findsOneWidget);
  });

  testWidgets('OpenUiAnswerView preserves and rebinds answer sessions', (
    tester,
  ) async {
    final answers = OpenUiAnswers(library: intelligentUi);
    addTearDown(answers.dispose);
    answers.update('m1', _greeting, streaming: false);
    final original = answers.sessionOf('m1');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OpenUiAnswerView(answers: answers, id: 'm1'),
        ),
      ),
    );

    answers.update('m1', _greeting, streaming: false);
    expect(identical(answers.sessionOf('m1'), original), isTrue);

    answers.remove('m1');
    answers.update('m1', _greeting, streaming: false);
    final replacement = answers.sessionOf('m1');
    expect(identical(replacement, original), isFalse);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OpenUiAnswerView(answers: answers, id: 'm1'),
        ),
      ),
    );
    answers.update('m1', 'Replacement prose', streaming: false);
    await tester.pump();
    expect(find.text('Replacement prose'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    answers.update('m1', _greeting, streaming: false);
    await tester.pump();
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

  group('buildActionUserMessage', () {
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
        buildActionUserMessage(event),
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
        buildActionUserMessage(event),
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
        buildActionUserMessage(event),
        ']]>openui:content\nContinue\n]]>openui:context\n'
        '["User clicked: Continue",{},null]',
      );
    });

    test('drops the content line when there is no message', () {
      const event = ActionEvent(type: ActionEvent.continueConversation);
      expect(
        buildActionUserMessage(event),
        '\n]]>openui:context\n["User clicked: ",{}]',
      );
    });
  });
}
