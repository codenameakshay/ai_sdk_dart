import 'dart:ui' as ui;

import 'package:ai_sdk_flutter_ui/src/widgets/source_citations.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

Future<void> _tabUntilActivated(
  WidgetTester tester,
  bool Function() activated, {
  int maxTabs = 10,
}) async {
  for (var i = 0; i < maxTabs; i++) {
    if (activated()) return;
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    if (activated()) return;
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
  }
  fail('Unable to activate target after $maxTabs tabs');
}

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
              LanguageModelV4SourcePart(
                id: 's1',
                url: 'https://a.example',
                title: 'Alpha',
              ),
              LanguageModelV4SourcePart(
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
              LanguageModelV4SourcePart(
                id: 's1',
                url: 'https://only-url.example',
              ),
            ],
          ),
        ),
      );
      expect(find.text('https://only-url.example'), findsOneWidget);
    });

    testWidgets(
      'uses truthful static semantics when a source is not tappable',
      (tester) async {
        final semantics = tester.ensureSemantics();

        await tester.pumpWidget(
          _wrap(
            const SourceCitations(
              sources: [
                LanguageModelV4SourcePart(
                  id: 's1',
                  url: 'https://a.example',
                  title: 'Alpha',
                ),
              ],
            ),
          ),
        );

        final chipNode = tester
            .getSemantics(find.byType(ActionChip))
            .getSemanticsData();
        expect(chipNode.label, 'Source: Alpha');
        expect(chipNode.hasAction(ui.SemanticsAction.tap), isFalse);
        expect(chipNode.flagsCollection.isButton, isNot(ui.Tristate.isTrue));
        expect(chipNode.flagsCollection.isLink, isNot(ui.Tristate.isTrue));
        semantics.dispose();
      },
    );

    testWidgets('invokes onTap with the tapped source', (tester) async {
      LanguageModelV4SourcePart? tapped;
      await tester.pumpWidget(
        _wrap(
          SourceCitations(
            sources: const [
              LanguageModelV4SourcePart(
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

    testWidgets('exposes accessible source labels with touch-sized chips', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        _wrap(
          SourceCitations(
            sources: const [
              LanguageModelV4SourcePart(
                id: 's1',
                url: 'https://a.example',
                title: 'Alpha',
              ),
            ],
            onTap: (_) {},
          ),
        ),
      );

      final chipNode = tester
          .getSemantics(find.byType(ActionChip))
          .getSemanticsData();
      expect(chipNode.label, 'Open source: Alpha');
      final chipSize = tester.getSize(find.byType(ActionChip));
      expect(chipSize.width, greaterThanOrEqualTo(44));
      expect(chipSize.height, greaterThanOrEqualTo(44));
      semantics.dispose();
    });

    testWidgets(
      'supports keyboard traversal and activation for tappable chips',
      (tester) async {
        final semantics = tester.ensureSemantics();
        LanguageModelV4SourcePart? tapped;

        await tester.pumpWidget(
          _wrap(
            SourceCitations(
              sources: const [
                LanguageModelV4SourcePart(
                  id: 's1',
                  url: 'https://a.example',
                  title: 'Alpha',
                ),
              ],
              onTap: (source) => tapped = source,
            ),
          ),
        );

        await _tabUntilActivated(tester, () => tapped != null);
        expect(tapped?.id, 's1');
        semantics.dispose();
      },
    );
  });
}
