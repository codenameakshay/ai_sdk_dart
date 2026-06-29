import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ToolCallCard', () {
    testWidgets('shows the tool name and pretty-printed args', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ToolCallCard(
            call: LanguageModelV3ToolCallPart(
              toolCallId: 'c1',
              toolName: 'getWeather',
              input: {'city': 'Tokyo'},
            ),
          ),
        ),
      );

      expect(find.text('getWeather'), findsOneWidget);
      // Pretty-printed JSON includes the key/value.
      expect(find.textContaining('"city": "Tokyo"'), findsOneWidget);
    });

    testWidgets('renders a successful result', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ToolCallCard(
            call: LanguageModelV3ToolCallPart(
              toolCallId: 'c1',
              toolName: 'getWeather',
              input: {'city': 'Tokyo'},
            ),
            result: LanguageModelV3ToolResultPart(
              toolCallId: 'c1',
              toolName: 'getWeather',
              output: ToolResultOutputText('Sunny, 22C'),
            ),
          ),
        ),
      );

      expect(find.text('Result'), findsOneWidget);
      expect(find.text('Sunny, 22C'), findsOneWidget);
      expect(find.text('Error'), findsNothing);
    });

    testWidgets('renders an error result distinctly', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ToolCallCard(
            call: LanguageModelV3ToolCallPart(
              toolCallId: 'c1',
              toolName: 'getWeather',
              input: {'city': 'Tokyo'},
            ),
            result: LanguageModelV3ToolResultPart(
              toolCallId: 'c1',
              toolName: 'getWeather',
              isError: true,
              output: ToolResultOutputText('network failure'),
            ),
          ),
        ),
      );

      expect(find.text('Error'), findsOneWidget);
      expect(find.text('network failure'), findsOneWidget);
      expect(find.text('Result'), findsNothing);
    });
  });
}
