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

    testWidgets('falls back to toString when args are not JSON-encodable', (
      tester,
    ) async {
      // A non-JSON value makes JsonEncoder.convert throw, exercising the
      // _prettyJson catch branch that falls back to value.toString().
      final input = <String, dynamic>{'fn': const _Unencodable()};
      await tester.pumpWidget(
        _wrap(
          ToolCallCard(
            call: LanguageModelV3ToolCallPart(
              toolCallId: 'c1',
              toolName: 'runFn',
              input: input,
            ),
          ),
        ),
      );

      expect(find.text('runFn'), findsOneWidget);
      // The raw Map.toString() output is shown instead of pretty JSON.
      expect(find.textContaining('UNENCODABLE'), findsOneWidget);
    });

    testWidgets('stringifies a multi-part content result', (tester) async {
      // ToolResultOutputContent goes through the parts.map(...).join branch,
      // joining the runtimeType of each content part.
      await tester.pumpWidget(
        _wrap(
          const ToolCallCard(
            call: LanguageModelV3ToolCallPart(
              toolCallId: 'c1',
              toolName: 'render',
              input: {},
            ),
            result: LanguageModelV3ToolResultPart(
              toolCallId: 'c1',
              toolName: 'render',
              output: ToolResultOutputContent([
                LanguageModelV3TextPart(text: 'hi'),
              ]),
            ),
          ),
        ),
      );

      expect(find.text('Result'), findsOneWidget);
      // The body lists the runtimeType of the single content part.
      expect(
        find.textContaining('LanguageModelV3TextPart'),
        findsOneWidget,
      );
    });
  });
}

/// A value that always throws when JSON-encoded, to drive the _prettyJson
/// fallback, but has a recognizable toString().
class _Unencodable {
  const _Unencodable();

  @override
  String toString() => 'UNENCODABLE';

  Map<String, dynamic> toJson() => throw StateError('not encodable');
}
