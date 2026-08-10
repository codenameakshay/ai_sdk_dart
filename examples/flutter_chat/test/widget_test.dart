import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_chat/main.dart';
import 'package:flutter_chat/pages/completion_page.dart';
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
}

class _HoldingTextModel implements LanguageModelV3 {
  _HoldingTextModel(this.text);

  final String text;
  final StreamController<LanguageModelV3StreamPart> _controller =
      StreamController<LanguageModelV3StreamPart>();

  @override
  String get provider => 'mock';

  @override
  String get modelId => 'holding-text';

  @override
  String get specificationVersion => 'v3';

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async {
    return LanguageModelV3GenerateResult(
      content: [LanguageModelV3TextPart(text: text)],
      finishReason: LanguageModelV3FinishReason.stop,
      rawFinishReason: 'stop',
    );
  }

  @override
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  ) async {
    const id = 'text-1';
    _controller
      ..add(const StreamPartTextStart(id: id))
      ..add(StreamPartTextDelta(id: id, delta: text))
      ..add(const StreamPartTextEnd(id: id));
    return LanguageModelV3StreamResult(stream: _controller.stream);
  }
}
