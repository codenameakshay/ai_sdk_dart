import 'dart:async';

import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_chat/main.dart';
import 'package:flutter_chat/pages/completion_page.dart';
import 'package:flutter_chat/pages/conversation_page.dart';
import 'package:flutter_chat/pages/object_stream_page.dart';

void main() {
  testWidgets('app navigates every primary screen offline', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const App());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Chat'), findsWidgets);
    expect(find.text('Say hello to start the conversation'), findsOneWidget);

    await tester.tap(find.text('Completion'));
    await tester.pumpAndSettle();

    expect(find.text('Quick prompts'), findsOneWidget);
    expect(find.text('Generate'), findsOneWidget);

    await tester.tap(find.text('Object'));
    await tester.pumpAndSettle();

    expect(find.text('Object Stream'), findsWidgets);
    expect(find.textContaining('Streams a typed JSON object'), findsOneWidget);
    expect(find.text('Generate'), findsOneWidget);

    await tester.tap(find.text('Local'));
    await tester.pumpAndSettle();

    expect(find.text('Local conversation'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-composer-field')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('conversation-language-toggle')),
      findsOneWidget,
    );

    await tester.tap(find.text('Remote'));
    await tester.pumpAndSettle();

    expect(find.text('Remote conversation'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-composer-field')), findsOneWidget);
  });

  testWidgets('completion page streams text and stop cancels offline', (
    WidgetTester tester,
  ) async {
    final model = _HoldingTextModel('Working on it...');
    final controller = CompletionController(agent: ToolLoopAgent(model: model));
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: CompletionPage(controller: controller)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.enterText(find.byType(TextField).first, 'Explain isolates');
    await tester.tap(find.text('Generate'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Stop'), findsOneWidget);

    await tester.tap(find.text('Stop'));
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets(
    'object stream page renders structured output without a network key',
    (WidgetTester tester) async {
      final controller = ObjectStreamController<Map<String, dynamic>>();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(home: ObjectStreamPage(controller: controller)),
      );
      await tester.pumpAndSettle();

      await controller.bind(
        Stream<Map<String, dynamic>>.fromIterable(const [
          {'country': 'Japan'},
          {'country': 'Japan', 'capital': 'Tokyo', 'currency': 'JPY'},
        ]),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Country Profile'), findsOneWidget);
      expect(find.text('Japan'), findsWidgets);
      expect(find.text('Tokyo'), findsOneWidget);
      expect(find.text('JPY'), findsOneWidget);
    },
  );

  testWidgets('app restores the selected tab after restart', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const App());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Object'));
    await tester.pumpAndSettle();
    expect(find.text('Object Stream'), findsOneWidget);

    await tester.restartAndRestore();
    await tester.pumpAndSettle();

    expect(find.text('Object Stream'), findsOneWidget);
    expect(find.text('Say hello to start the conversation'), findsNothing);
  });

  testWidgets('conversation language toggle switches labels and RTL offline', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LocalConversationPage()));
    await tester.pump();

    expect(find.text('Message…'), findsOneWidget);
    expect(
      Directionality.of(
        tester.element(find.byKey(const ValueKey('chat-composer-field'))),
      ),
      TextDirection.ltr,
    );

    await tester.tap(
      find.byKey(const ValueKey('conversation-language-toggle')),
    );
    await tester.pump();

    expect(find.text('رسالة…'), findsOneWidget);
    expect(
      Directionality.of(
        tester.element(find.byKey(const ValueKey('chat-composer-field'))),
      ),
      TextDirection.rtl,
    );
  });

  for (final decisions in [
    [true, false, true],
    [false, true, false],
  ]) {
    testWidgets('local conversation handles successive $decisions approvals', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: LocalConversationPage()));
      await tester.pumpAndSettle();
      final conversation = tester
          .widget<AiChatScaffold>(find.byType(AiChatScaffold))
          .conversationController!;
      final callIds = <String>{};

      for (final approved in decisions) {
        await tester.runAsync(
          () => conversation.send('Please delete the example file.'),
        );
        await tester.pumpAndSettle();
        expect(
          find.byType(ToolApprovalCard),
          findsOneWidget,
          reason: 'Approval for turn ${callIds.length + 1}',
        );
        final card = tester.widget<ToolApprovalCard>(
          find.byType(ToolApprovalCard),
        );
        final request = card.request;
        expect(callIds.add(request.toolCall.toolCallId), isTrue);
        expect(request.toolCall.toolName, 'deleteFile');
        expect(request.toolCall.input, {'path': '/tmp/example'});
        expect(request.argumentsFingerprint, '{"path":"/tmp/example"}');
        expect(request.policyRevision, 'default');

        final respond = approved ? card.onApprove : card.onDeny;
        respond(null);
        respond(null);
        for (var i = 0; i < 100; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          final message = conversation.conversation.messages.last;
          if (message.status == ConversationMessageStatus.complete &&
              message.parts.whereType<TextPart>().isNotEmpty) {
            break;
          }
          await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        }
        expect(
          conversation.conversation.messages.last.status,
          ConversationMessageStatus.complete,
        );
        final parts = conversation.conversation.messages.last.parts;
        expect(
          parts.whereType<TextPart>().map((part) => part.text).join(),
          approved
              ? 'Tool result: deleted /tmp/example'
              : 'Tool denied; no local action ran.',
        );
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}

class _HoldingTextModel extends LanguageModelV4 {
  _HoldingTextModel(this.text);

  final String text;
  final StreamController<LanguageModelV4StreamPart> _controller =
      StreamController<LanguageModelV4StreamPart>();

  @override
  String get provider => 'mock';

  @override
  String get modelId => 'holding-text';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    return LanguageModelV4GenerateResult(
      content: [LanguageModelV4TextPart(text: text)],
      finishReason: LanguageModelV4FinishReason.stop,
      rawFinishReason: 'stop',
    );
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    const id = 'text-1';
    _controller
      ..add(const StreamPartTextStart(id: id))
      ..add(StreamPartTextDelta(id: id, delta: text))
      ..add(const StreamPartTextEnd(id: id));
    return LanguageModelV4StreamResult(stream: _controller.stream);
  }
}
