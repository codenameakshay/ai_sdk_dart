import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advanced_app/main.dart';
import 'package:advanced_app/pages/tools_chat_page.dart';
import 'package:advanced_app/pages/widget_gallery_page.dart';

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
      'Widget Gallery',
    ]) {
      await _selectDrawerItem(tester, label);
      expect(find.text(label), findsWidgets);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('tools chat clears old sources when a new turn has none', (
    tester,
  ) async {
    final runner = _QueuedToolsRunner([
      _completedStreamResult(
        events: const [
          StreamTextStartStepEvent(stepNumber: 1),
          StreamTextTextDeltaEvent(id: 'text-1', delta: 'Tokyo is sunny.'),
          StreamTextSourceEvent(
            source: LanguageModelV3SourcePart(
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
    expect(find.text('Tokyo weather'), findsNothing);
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
          initialPage: AdvancedExamplePage.toolsChat,
          initialToolsFixture: fixture.key,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining(fixture.value), findsOneWidget);
    }
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
}) {
  return StreamTextResult<Object?>(
    stream: const Stream<LanguageModelV3StreamPart>.empty(),
    fullStream: Stream<StreamTextEvent>.fromIterable(events),
    textStream: const Stream<String>.empty(),
    partialOutputStream: const Stream<Object?>.empty(),
    elementStream: const Stream<Object?>.empty(),
    text: Future<String>.value(finalText),
    output: Future<Object?>.value(finalText),
    content: Future<List<LanguageModelV3ContentPart>>.value(
      finalText.isEmpty ? const [] : [LanguageModelV3TextPart(text: finalText)],
    ),
    reasoning: Future<List<LanguageModelV3ReasoningPart>>.value(const []),
    reasoningText: Future<String>.value(''),
    files: Future<List<LanguageModelV3FilePart>>.value(const []),
    sources: Future<List<LanguageModelV3SourcePart>>.value(const []),
    toolCalls: Future<List<LanguageModelV3ToolCallPart>>.value(const []),
    toolResults: Future<List<LanguageModelV3ToolResultPart>>.value(const []),
    finishReason: Future<LanguageModelV3FinishReason?>.value(
      LanguageModelV3FinishReason.stop,
    ),
    rawFinishReason: Future<String?>.value('stop'),
    usage: Future<LanguageModelV3Usage?>.value(null),
    totalUsage: Future<LanguageModelV3Usage?>.value(null),
    warnings: Future<List<String>>.value(const []),
    steps: Future<List<GenerateTextStep>>.value(const []),
    request: Future<GenerateTextRequest>.value(
      const GenerateTextRequest(system: null, messages: []),
    ),
    response: Future<GenerateTextResponse>.value(
      const GenerateTextResponse(messages: [], body: null, metadata: null),
    ),
    providerMetadata: Future<ProviderMetadata?>.value(null),
    finish: Future<StreamPartFinish?>.value(
      const StreamPartFinish(
        finishReason: LanguageModelV3FinishReason.stop,
        rawFinishReason: 'stop',
      ),
    ),
  );
}
