import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('UsageView', () {
    testWidgets('renders input, output, and total token counts', (
      tester,
    ) async {
      // Build the usage at runtime so the UsageView construction is non-const.
      final usage = LanguageModelV3Usage(
        inputTokens: 10,
        outputTokens: 20,
        totalTokens: 30,
      );
      await tester.pumpWidget(_wrap(UsageView(usage: usage)));

      expect(find.textContaining('Input'), findsOneWidget);
      expect(find.textContaining('10'), findsOneWidget);
      expect(find.textContaining('Output'), findsOneWidget);
      expect(find.textContaining('20'), findsOneWidget);
      expect(find.textContaining('Total'), findsOneWidget);
      expect(find.textContaining('30'), findsOneWidget);
    });

    testWidgets('omits fields whose token count is null', (tester) async {
      await tester.pumpWidget(
        _wrap(const UsageView(usage: LanguageModelV3Usage(inputTokens: 5))),
      );

      expect(find.textContaining('Input'), findsOneWidget);
      expect(find.textContaining('Output'), findsNothing);
      expect(find.textContaining('Total'), findsNothing);
    });

    testWidgets('renders nothing when all token counts are null', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const UsageView(usage: LanguageModelV3Usage())));

      expect(find.byType(SizedBox), findsWidgets);
      expect(find.textContaining('Input'), findsNothing);
    });
  });
}
