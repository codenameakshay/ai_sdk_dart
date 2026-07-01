import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('SourceCitations', () {
    testWidgets('renders nothing when there are no sources', (tester) async {
      await tester.pumpWidget(_wrap(const SourceCitations(sources: [])));
      expect(find.byType(ActionChip), findsNothing);
    });

    testWidgets('renders a chip per source using title', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SourceCitations(
            sources: [
              LanguageModelV3SourcePart(
                id: 's1',
                url: 'https://a.example',
                title: 'Alpha',
              ),
              LanguageModelV3SourcePart(
                id: 's2',
                url: 'https://b.example',
                title: 'Beta',
              ),
            ],
          ),
        ),
      );

      expect(find.byType(ActionChip), findsNWidgets(2));
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
      expect(find.text('Sources'), findsOneWidget);
    });

    testWidgets('falls back to URL when title is missing', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SourceCitations(
            sources: [
              LanguageModelV3SourcePart(
                id: 's1',
                url: 'https://only-url.example',
              ),
            ],
          ),
        ),
      );
      expect(find.text('https://only-url.example'), findsOneWidget);
    });

    testWidgets('invokes onTap with the tapped source', (tester) async {
      LanguageModelV3SourcePart? tapped;
      await tester.pumpWidget(
        _wrap(
          SourceCitations(
            sources: const [
              LanguageModelV3SourcePart(
                id: 's1',
                url: 'https://a.example',
                title: 'Alpha',
              ),
            ],
            onTap: (s) => tapped = s,
          ),
        ),
      );
      await tester.tap(find.text('Alpha'));
      await tester.pump();
      expect(tapped, isNotNull);
      expect(tapped!.id, 's1');
    });
  });
}
