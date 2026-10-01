import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_dart/test.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advanced_app/main.dart';
import 'package:advanced_app/pages/conversation_page.dart';
import 'package:advanced_app/pages/object_stream_page.dart';
import 'package:advanced_app/pages/responses_page.dart';
import 'package:advanced_app/pages/tools_chat_page.dart';
import 'package:advanced_app/pages/widget_gallery_page.dart';

import 'support/scripted_models.dart';

void main() {
  testWidgets('app boots and shows the prebuilt chat composer', (tester) async {
    await tester.pumpWidget(const App());
    await tester.pump();

    expect(find.byType(ChatComposer), findsOneWidget);
    expect(find.text('Provider Chat'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('navigation drawer visits every documented primary screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const App());
    await tester.pump();

    for (final label in const [
      'Provider Chat',
      'Tools Chat',
      'Image Gen',
      'Multimodal',
      'Embeddings',
      'Text-to-Speech',
      'Speech-to-Text',
      'Completion',
      'Object Stream',
      'Conversation',
      'Responses',
      'Widget Gallery',
    ]) {
      await _selectDrawerItem(tester, label);
      expect(find.text(label), findsWidgets);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('tools chat keeps citations on the turn that produced them', (
    tester,
  ) async {
    final runner = _QueuedToolsRunner([
      _completedStreamResult(
        events: const [
          StreamTextStartStepEvent(stepNumber: 1),
          StreamTextTextDeltaEvent(id: 'text-1', delta: 'Tokyo is sunny.'),
          StreamTextSourceEvent(
            source: LanguageModelV4SourcePart(
              id: 'source-1',
              url: 'https://weather.example.com/tokyo',
              title: 'Tokyo weather',
            ),
          ),
        ],
        finalText: 'Tokyo is sunny.',
      ),
      _completedStreamResult(
        events: const [
          StreamTextStartStepEvent(stepNumber: 1),
          StreamTextTextDeltaEvent(id: 'text-2', delta: 'Paris has no source.'),
        ],
        finalText: 'Paris has no source.',
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: ToolsChatPage(streamRunner: runner.call)),
    );
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey('chat-composer-field')),
      'What is the weather in Tokyo?',
    );
    await tester.tap(find.byKey(const ValueKey('chat-composer-send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Tokyo weather'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('chat-composer-field')),
      'Tell me about Paris.',
    );
    await tester.tap(find.byKey(const ValueKey('chat-composer-send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Paris has no source.'), findsOneWidget);
    expect(find.text('Tokyo weather'), findsOneWidget);
    expect(find.byType(SourceCitations), findsOneWidget);
  });

  testWidgets(
    'tools chat uses instant scrolling when animations are disabled',
    (tester) async {
      final scrollController = _TrackingScrollController();
      addTearDown(scrollController.dispose);
      await tester.binding.setSurfaceSize(const Size(360, 320));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final longText = List.filled(80, 'Long streaming transcript').join(' ');
      final runner = _QueuedToolsRunner([
        _completedStreamResult(
          events: [
            const StreamTextStartStepEvent(stepNumber: 1),
            StreamTextTextDeltaEvent(id: 'text-1', delta: longText),
          ],
          finalText: longText,
        ),
      ]);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            home: ToolsChatPage(
              scrollController: scrollController,
              streamRunner: runner.call,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(
        find.byKey(const ValueKey('chat-composer-field')),
        'Stream a long answer',
      );
      await tester.tap(find.byKey(const ValueKey('chat-composer-send')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(scrollController.jumpCallCount, greaterThan(0));
      expect(scrollController.animateCallCount, 0);
    },
  );

  testWidgets('app restores the selected example page after restart', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const App());
    await tester.pump();

    await _selectDrawerItem(tester, 'Widget Gallery');
    expect(find.byType(PromptSuggestions), findsOneWidget);

    await tester.restartAndRestore();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Widget Gallery'), findsWidgets);
    expect(find.byType(PromptSuggestions), findsOneWidget);
  });

  testWidgets('advanced app exposes deterministic screenshot fixtures', (
    tester,
  ) async {
    for (final fixture in const <ToolsChatFixture, String>{
      ToolsChatFixture.normal: 'Offline fixture reply',
      ToolsChatFixture.approval: 'Approve tool call?',
      ToolsChatFixture.error: 'Retry',
      ToolsChatFixture.sourcesTool: 'Example Weather Feed',
      ToolsChatFixture.longHistory: 'Conversation history 1',
    }.entries) {
      await tester.pumpWidget(
        App(
          key: ValueKey(fixture.key),
          initialPage: AdvancedExamplePage.toolsChat,
          initialToolsFixture: fixture.key,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining(fixture.value), findsOneWidget);
    }
  });

  testWidgets(
    'tools chat fixture is consumed after leaving the initial route',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const App(
          initialPage: AdvancedExamplePage.toolsChat,
          initialToolsFixture: ToolsChatFixture.normal,
        ),
      );
      await tester.pump();

      expect(find.text('Offline fixture reply'), findsOneWidget);

      await _selectDrawerItem(tester, 'Provider Chat');
      await _selectDrawerItem(tester, 'Tools Chat');

      expect(find.text('Offline fixture reply'), findsNothing);
      expect(find.byType(ChatComposer), findsOneWidget);
      expect(
        find.textContaining('Try "What\'s the weather in Tokyo?"'),
        findsOneWidget,
      );
    },
  );

  testWidgets('non-tools initial pages ignore screenshot fixtures later', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const App(
        initialPage: AdvancedExamplePage.providerChat,
        initialToolsFixture: ToolsChatFixture.normal,
      ),
    );
    await tester.pump();

    await _selectDrawerItem(tester, 'Tools Chat');

    expect(find.text('Offline fixture reply'), findsNothing);
    expect(find.byType(ChatComposer), findsOneWidget);
  });

  testWidgets('widget gallery renders the prebuilt widgets offline', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 5000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: WidgetGalleryPage())),
    );
    await tester.pump();

    expect(find.byType(PromptSuggestions), findsOneWidget);
    expect(find.byType(TypingIndicator), findsOneWidget);
    expect(find.byType(AssistantMessageView), findsOneWidget);
    expect(find.byType(ToolApprovalCard), findsOneWidget);
    expect(find.byType(MessageActionsBar), findsOneWidget);
    expect(find.byType(UsageView), findsOneWidget);
    expect(find.byType(ChatErrorView), findsOneWidget);
    expect(find.byType(ObjectStreamView<Map<String, dynamic>>), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('widget gallery copy action shows a confirmation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 5000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: WidgetGalleryPage())),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('message-copy')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Copied to clipboard'), findsOneWidget);
  });

  testWidgets('conversation page resumes a tool call after approval', (
    tester,
  ) async {
    final model = QueuedLanguageModel([
      [
        mockToolCall(
          toolName: 'deleteFile',
          input: {'path': 'q3.pdf'},
          toolCallId: 'call-delete-1',
        ),
      ],
      [mockText('Deleted q3.pdf as requested.')],
    ]);
    final agent = ToolLoopAgent(
      model: model,
      tools: {
        'deleteFile': tool<Map<String, dynamic>, String>(
          inputSchema: Schema<Map<String, dynamic>>(
            jsonSchema: const {'type': 'object'},
            fromJson: (json) => json,
          ),
          execute: (input, _) async => 'Deleted ${input['path']}',
        ),
      },
      approvalPolicy: ToolApprovalPolicy.always,
    );

    await tester.pumpWidget(
      MaterialApp(home: ConversationPage(testAgent: agent)),
    );
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey('chat-composer-field')),
      'Delete q3.pdf',
    );
    // The SDK's tool-execution scheduling uses real timers (`Future(...)`
    // schedules via `Timer.run`), which the default fake-async test zone
    // never fires. The tap that kicks off the turn — and the polling for
    // its result — must both run inside the same runAsync callback so the
    // timer is created and fires in the same (real) zone.
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('chat-composer-send')));
      await tester.pump();
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
        if (find.byType(ToolApprovalCard).evaluate().isNotEmpty) return;
      }
    });

    expect(find.byType(ToolApprovalCard), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('tool-approval-approve')));
      await tester.pump();
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
        if (find
            .textContaining('Deleted q3.pdf as requested.')
            .evaluate()
            .isNotEmpty) {
          return;
        }
      }
    });

    expect(find.textContaining('Deleted q3.pdf as requested.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('conversation page saves and restores a snapshot', (
    tester,
  ) async {
    final agent = ToolLoopAgent(
      model: QueuedLanguageModel([
        [mockText('Hello from the fake model.')],
      ]),
    );

    await tester.pumpWidget(
      MaterialApp(home: ConversationPage(testAgent: agent)),
    );
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey('chat-composer-field')),
      'Say hi',
    );
    // See the comment on the approval test above: the tap and the polling
    // for its result must share one runAsync callback.
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('chat-composer-send')));
      await tester.pump();
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
        if (find
            .textContaining('Hello from the fake model.')
            .evaluate()
            .isNotEmpty) {
          return;
        }
      }
    });

    expect(find.textContaining('Hello from the fake model.'), findsOneWidget);

    await tester.tap(find.byTooltip('Save snapshot'));
    await tester.pump();
    await tester.tap(find.byTooltip('New conversation'));
    await tester.pump();

    expect(find.textContaining('Hello from the fake model.'), findsNothing);

    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Restore snapshot'));
      await tester.pump();
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
        if (find
            .textContaining('Hello from the fake model.')
            .evaluate()
            .isNotEmpty) {
          return;
        }
      }
    });

    expect(find.textContaining('Hello from the fake model.'), findsOneWidget);
  });

  testWidgets(
    'conversation page restores an empty snapshot without invoking the model',
    (tester) async {
      final model = QueuedLanguageModel([
        [mockText('Unused response.')],
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: ConversationPage(testAgent: ToolLoopAgent(model: model)),
        ),
      );
      final savedId = tester
          .widget<AiChatScaffold>(find.byType(AiChatScaffold))
          .conversationController!
          .conversation
          .id;
      await tester.tap(find.byTooltip('Save snapshot'));
      await tester.pump();
      await tester.tap(find.byTooltip('New conversation'));
      await tester.pump();
      expect(
        tester
            .widget<AiChatScaffold>(find.byType(AiChatScaffold))
            .conversationController!
            .conversation
            .id,
        isNot(savedId),
      );
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Restore snapshot'));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      });
      final restored = tester
          .widget<AiChatScaffold>(find.byType(AiChatScaffold))
          .conversationController!
          .conversation;
      expect(restored.id, savedId);
      expect(restored.messages, isEmpty);
      expect(model.calls, isEmpty);
    },
  );

  testWidgets(
    'tools chat keeps history replayable after an approved tool turn',
    (tester) async {
      final model = QueuedLanguageModel([
        [
          mockText('Deleting now. '),
          mockToolCall(
            toolName: 'deleteFile',
            input: {'path': 'q3.pdf'},
            toolCallId: 'call-delete-1',
          ),
        ],
        [mockText('Deleted q3.pdf.')],
        [mockText('Anything else?')],
      ]);

      await tester.pumpWidget(
        MaterialApp(home: ToolsChatPage(testModel: model)),
      );
      await tester.pump();

      Future<void> sendAndWaitFor(String message, Finder expected) async {
        await tester.pump(const Duration(milliseconds: 300));
        await tester.enterText(
          find.byKey(const ValueKey('chat-composer-field')),
          message,
        );
        await tester.runAsync(() async {
          await tester.tap(find.byKey(const ValueKey('chat-composer-send')));
          await tester.pump();
          for (var i = 0; i < 50; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            await tester.pump();
            if (expected.evaluate().isNotEmpty) return;
          }
        });
      }

      await sendAndWaitFor('Delete q3.pdf', find.byType(ToolApprovalCard));
      expect(find.byType(ToolApprovalCard), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('tool-approval-approve')));
        await tester.pump();
        for (var i = 0; i < 50; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
          if (find.textContaining('Deleted q3.pdf.').evaluate().isNotEmpty) {
            return;
          }
        }
      });
      expect(find.textContaining('Deleted q3.pdf.'), findsOneWidget);

      await sendAndWaitFor('Thanks', find.textContaining('Anything else?'));
      expect(find.textContaining('Anything else?'), findsOneWidget);

      final messages = model.calls.last.prompt.messages;
      final callIds = {
        for (final message in messages)
          if (message.role == LanguageModelV4Role.assistant)
            for (final part in message.content)
              if (part is LanguageModelV4ToolCallPart) part.toolCallId,
      };
      final resultIds = {
        for (final message in messages)
          for (final part in message.content)
            if (part is LanguageModelV4ToolResultPart) part.toolCallId,
      };
      expect(resultIds.containsAll(callIds), isTrue);

      final assistantText = [
        for (final message in messages)
          if (message.role == LanguageModelV4Role.assistant)
            for (final part in message.content)
              if (part is LanguageModelV4TextPart) part.text,
      ];
      expect(
        assistantText.where((text) => text.contains('Deleting now. ')),
        hasLength(1),
      );
    },
  );

  testWidgets('tools chat ignores late events from a cleared turn', (
    tester,
  ) async {
    final controller = StreamController<StreamTextEvent>();
    final runner = _QueuedToolsRunner([
      _completedStreamResult(
        events: const [],
        stream: controller.stream,
        finalText: '',
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: ToolsChatPage(streamRunner: runner.call)),
    );
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey('chat-composer-field')),
      'Stream something',
    );
    await tester.tap(find.byKey(const ValueKey('chat-composer-send')));
    await tester.pump();

    controller.add(const StreamTextStartStepEvent(stepNumber: 1));
    controller.add(const StreamTextTextDeltaEvent(id: 't1', delta: 'Early.'));
    await tester.pump();
    expect(find.text('Early.'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear chat'));
    await tester.pump();

    controller.add(const StreamTextTextDeltaEvent(id: 't1', delta: 'Late.'));
    unawaited(controller.close());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Late.'), findsNothing);
    expect(find.text('Early.'), findsNothing);
  });

  testWidgets('tools chat ends a failed stream before accepting another turn', (
    tester,
  ) async {
    final controller = StreamController<StreamTextEvent>();
    final runner = _QueuedToolsRunner([
      _completedStreamResult(
        events: const [],
        stream: controller.stream,
        finalText: '',
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(home: ToolsChatPage(streamRunner: runner.call)),
    );
    await tester.enterText(
      find.byKey(const ValueKey('chat-composer-field')),
      'First request',
    );
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('chat-composer-send')));
      await tester.pump();
      controller.add(StreamTextErrorEvent(error: StateError('Request failed')));
      controller.add(
        const StreamTextTextDeltaEvent(id: 'late', delta: 'Late success'),
      );
      unawaited(controller.close());
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
        if (find.textContaining('Request failed').evaluate().isNotEmpty) break;
      }
    });
    expect(find.textContaining('Request failed'), findsOneWidget);
    expect(find.text('Late success'), findsNothing);
    expect(
      tester.widget<ChatComposer>(find.byType(ChatComposer)).isLoading,
      isFalse,
    );
  });

  for (final approved in [true, false]) {
    testWidgets(
      'tools chat resumes once after ${approved ? 'approval' : 'denial'}',
      (tester) async {
        final model = QueuedLanguageModel([
          [
            mockToolCall(
              toolName: 'deleteFile',
              input: {'path': 'q3.pdf'},
              toolCallId: 'delete-1',
            ),
          ],
          [mockText('Decision processed.')],
        ]);
        await tester.pumpWidget(
          MaterialApp(home: ToolsChatPage(testModel: model)),
        );
        await tester.enterText(
          find.byKey(const ValueKey('chat-composer-field')),
          'Delete q3.pdf',
        );
        await tester.runAsync(() async {
          await tester.tap(find.byKey(const ValueKey('chat-composer-send')));
          for (var i = 0; i < 50; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            await tester.pump();
            if (find.byType(ToolApprovalCard).evaluate().isNotEmpty) break;
          }
          final card = tester.widget<ToolApprovalCard>(
            find.byType(ToolApprovalCard),
          );
          if (approved) {
            card.onApprove(null);
            card.onDeny(null);
          } else {
            card.onDeny(null);
            card.onApprove(null);
          }
          for (var i = 0; i < 50; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            await tester.pump();
            if (find.text('Decision processed.').evaluate().isNotEmpty) break;
          }
        });
        expect(find.text('Decision processed.'), findsOneWidget);
        expect(model.calls, hasLength(2));
        final results = [
          for (final message in model.calls.last.prompt.messages)
            for (final part in message.content)
              if (part is LanguageModelV4ToolResultPart) part,
        ];
        expect(results, hasLength(1));
        expect(results.single.toolCallId, 'delete-1');
        expect(results.single.isError, !approved);
        expect(
          results.single.output,
          approved
              ? isA<ToolResultOutputText>().having(
                  (output) => output.text,
                  'text',
                  'Deleted /workspace/q3.pdf',
                )
              : isA<ToolResultOutputText>().having(
                  (output) => output.text,
                  'error',
                  'Tool execution denied.',
                ),
        );
      },
    );
  }

  testWidgets('responses page renders reasoning and hosted-tool sources', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: ResponsesPage(testModel: ResponsesFakeModel())),
    );
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey('responses-prompt-field')),
      'What changed in Flutter?',
    );
    // See the comment on the conversation approval test above: the tap and
    // the polling for its result must share one runAsync callback.
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('responses-ask-button')));
      await tester.pump();
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
        if (find
            .textContaining('Flutter 3.44 is current.')
            .evaluate()
            .isNotEmpty) {
          return;
        }
      }
    });

    expect(find.byType(ReasoningView), findsOneWidget);
    expect(find.byType(SourceCitations), findsOneWidget);
    expect(find.textContaining('Flutter 3.44 is current.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'object stream reports an invalid final object without uncaught stream errors',
    (tester) async {
      final model = QueuedLanguageModel([
        [mockText('{"country":"Japan"}')],
      ]);
      await tester.pumpWidget(
        MaterialApp(home: ObjectStreamPage(testModel: model)),
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Generate'));
        for (var i = 0; i < 50; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
          if (find
              .textContaining('Schema validation failed')
              .evaluate()
              .isNotEmpty) {
            break;
          }
        }
      });
      expect(find.textContaining('Schema validation failed'), findsOneWidget);
      expect(find.text('Country Profile (validated)'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Generate'))
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final removePage in [false, true]) {
    testWidgets(
      'object stream ignores late data after ${removePage ? 'page removal' : 'stop'}',
      (tester) async {
        final model = _ControlledStreamModel();
        await tester.pumpWidget(
          MaterialApp(home: ObjectStreamPage(testModel: model)),
        );
        await tester.runAsync(() async {
          await tester.tap(find.text('Generate'));
          for (var i = 0; i < 50 && model.streamCalls.isEmpty; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            await tester.pump();
          }
          model.controller.add(const StreamPartTextStart(id: 't1'));
          model.controller.add(
            const StreamPartTextDelta(id: 't1', delta: '{"country":"Japan",'),
          );
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
          expect(find.text('Japan'), findsNWidgets(2));
          if (removePage) {
            await tester.pumpWidget(const SizedBox());
          } else {
            await tester.tap(find.text('Stop'));
            await tester.pump();
          }
          model.controller.add(
            const StreamPartTextDelta(
              id: 't1',
              delta: '"capital":"Late capital"}',
            ),
          );
          model.controller.add(const StreamPartTextEnd(id: 't1'));
          model.controller.add(
            const StreamPartFinish(
              finishReason: LanguageModelV4FinishReason.stop,
            ),
          );
          unawaited(model.controller.close());
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
        });
        expect(find.text('Late capital'), findsNothing);
        if (!removePage) {
          expect(
            tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Generate'),
                )
                .onPressed,
            isNotNull,
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _ControlledStreamModel extends MockLanguageModelV4 {
  final controller = StreamController<LanguageModelV4StreamPart>();

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    streamCalls.add(options);
    return LanguageModelV4StreamResult(stream: controller.stream);
  }
}

Future<void> _selectDrawerItem(WidgetTester tester, String label) async {
  final shell = tester.firstState<ScaffoldState>(find.byType(Scaffold));
  shell.openDrawer();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));

  final tile = find.widgetWithText(ListTile, label);
  await tester.ensureVisible(tile);
  await tester.tap(tile);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

class _TrackingScrollController extends ScrollController {
  int jumpCallCount = 0;
  int animateCallCount = 0;

  @override
  Future<void> animateTo(
    double offset, {
    required Duration duration,
    required Curve curve,
  }) {
    animateCallCount++;
    return super.animateTo(offset, duration: duration, curve: curve);
  }

  @override
  void jumpTo(double value) {
    jumpCallCount++;
    super.jumpTo(value);
  }
}

class _QueuedToolsRunner {
  _QueuedToolsRunner(this._results);

  final List<StreamTextResult<Object?>> _results;
  int _index = 0;

  Future<StreamTextResult> call(
    List<ModelMessage> messages,
    ToolSet tools,
  ) async {
    final result =
        _results[_index < _results.length ? _index : _results.length - 1];
    _index++;
    return result;
  }
}

StreamTextResult<Object?> _completedStreamResult({
  required List<StreamTextEvent> events,
  required String finalText,
  Stream<StreamTextEvent>? stream,
}) {
  final content = <LanguageModelV4ContentPart>[
    if (finalText.isNotEmpty) LanguageModelV4TextPart(text: finalText),
  ];
  final step = GenerateTextStep(
    stepNumber: 0,
    content: content,
    toolCalls: const [],
    toolResults: const [],
    toolApprovalRequests: const [],
    response: LanguageModelV4GenerateResult(
      content: content,
      finishReason: LanguageModelV4FinishReason.stop,
    ),
    text: finalText,
    finishReason: LanguageModelV4FinishReason.stop,
  );
  return StreamTextResult<Object?>(
    stream: stream ?? Stream<StreamTextEvent>.fromIterable(events),
    providerStream: const Stream<LanguageModelV4StreamPart>.empty(),
    textStream: const Stream<String>.empty(),
    partialOutputStream: const Stream<Object?>.empty(),
    elementStream: const Stream<Object?>.empty(),
    text: Future<String>.value(finalText),
    output: Future<Object?>.value(finalText),
    content: Future<List<LanguageModelV4ContentPart>>.value(content),
    reasoning: Future<List<LanguageModelV4ReasoningPart>>.value(const []),
    reasoningText: Future<String>.value(''),
    files: Future<List<LanguageModelV4FilePart>>.value(const []),
    reasoningFiles: Future<List<LanguageModelV4ReasoningFilePart>>.value(
      const [],
    ),
    sources: Future<List<LanguageModelV4SourcePart>>.value(const []),
    documentSources: Future<List<LanguageModelV4DocumentSourcePart>>.value(
      const [],
    ),
    toolCalls: Future<List<LanguageModelV4ToolCallPart>>.value(const []),
    toolResults: Future<List<LanguageModelV4ToolResultPart>>.value(const []),
    finishReason: Future<LanguageModelV4FinishReason?>.value(
      LanguageModelV4FinishReason.stop,
    ),
    rawFinishReason: Future<String?>.value('stop'),
    usage: Future<LanguageModelV4Usage?>.value(null),
    totalUsage: Future<LanguageModelV4Usage?>.value(null),
    warnings: Future.value(const <LanguageModelV4Warning>[]),
    steps: Future<List<GenerateTextStep>>.value([step]),
    finalStep: Future<GenerateTextStep>.value(step),
    request: Future<GenerateTextRequest>.value(
      const GenerateTextRequest(system: null, messages: []),
    ),
    response: Future<GenerateTextResponse>.value(
      const GenerateTextResponse(messages: [], body: null, metadata: null),
    ),
    providerMetadata: Future<ProviderMetadata?>.value(null),
    finish: Future<StreamPartFinish?>.value(
      const StreamPartFinish(
        finishReason: LanguageModelV4FinishReason.stop,
        rawFinishReason: 'stop',
      ),
    ),
  );
}
