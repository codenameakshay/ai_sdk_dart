import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

Widget _reduced(Widget child) => MaterialApp(
  home: MediaQuery(
    data: const MediaQueryData(disableAnimations: true),
    child: Scaffold(body: child),
  ),
);

void main() {
  group('PromptSuggestions', () {
    testWidgets('renders a chip per suggestion', (tester) async {
      await tester.pumpWidget(
        _wrap(
          PromptSuggestions(
            suggestions: const ['Summarize this', 'Write a poem'],
            onSelected: (_) {},
          ),
        ),
      );

      expect(find.text('Summarize this'), findsOneWidget);
      expect(find.text('Write a poem'), findsOneWidget);
    });

    testWidgets('invokes onSelected with the tapped suggestion', (
      tester,
    ) async {
      String? selected;
      await tester.pumpWidget(
        _wrap(
          PromptSuggestions(
            suggestions: const ['First', 'Second'],
            onSelected: (value) => selected = value,
          ),
        ),
      );

      await tester.tap(find.text('Second'));
      expect(selected, 'Second');
    });

    testWidgets('renders an optional title', (tester) async {
      await tester.pumpWidget(
        _wrap(
          PromptSuggestions(
            title: 'Try asking',
            suggestions: const ['One'],
            onSelected: (_) {},
          ),
        ),
      );

      expect(find.text('Try asking'), findsOneWidget);
    });

    testWidgets('collapses to nothing when there are no suggestions', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(PromptSuggestions(suggestions: const [], onSelected: (_) {})),
      );

      expect(find.byType(ActionChip), findsNothing);
    });

    testWidgets('appears immediately when reduced motion is requested', (
      tester,
    ) async {
      await tester.pumpWidget(
        _reduced(
          PromptSuggestions(
            suggestions: const ['One', 'Two'],
            onSelected: (_) {},
          ),
        ),
      );

      final opacities = find.byType(Opacity);
      expect(opacities, findsNWidgets(2));
      for (final element in opacities.evaluate()) {
        expect(
          tester.widget<Opacity>(find.byWidget(element.widget)).opacity,
          1,
        );
      }
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ActionChip), findsNWidgets(2));
    });
  });
}
