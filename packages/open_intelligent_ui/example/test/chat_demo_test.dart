import 'dart:async';

import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';
import 'package:open_intelligent_ui_gallery/chat_demo.dart';

/// Runs [body] on the real event loop, where the scripted stream's timers
/// and streamText's futures settle, then pumps a frame.
Future<void> _real(WidgetTester tester, FutureOr<void> Function() body) async {
  await tester.runAsync(() async {
    await body();
    await Future<void>.delayed(const Duration(milliseconds: 60));
  });
  await tester.pump();
}

final _list = find
    .descendant(
      of: find.byType(ChatMessageList),
      matching: find.byType(Scrollable),
    )
    .first;

void main() {
  test('the scripted answers are clean programs', () {
    for (final program in [
      lisbonProgram,
      tailoredProgram('Packed'),
      tailoredProgram('Relaxed'),
    ]) {
      final report = intelligentUi.parse(program);
      expect(report.isClean, isTrue, reason: '${report.errors}');
    }
  });

  test('a @ToAssistant turn with a pace gets the tailored page', () {
    expect(scriptedReply('Plan three days in Lisbon'), lisbonProgram);
    expect(
      scriptedReply(
        ']]>openui:content\nTailor my Lisbon trip\n]]>openui:context\n'
        '["User clicked: Tailor my Lisbon trip",{"\$pace":"Packed"}]',
      ),
      tailoredProgram('Packed'),
    );
  });

  testWidgets('the chat streams a page and answers its form', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: ChatDemoPage(
          model: ScriptedModel(
            chunk: 400,
            every: const Duration(milliseconds: 1),
          ),
        ),
      ),
    );

    await _real(
      tester,
      () => tester.tap(find.text('Plan three days in Lisbon')),
    );
    await _real(tester, () {});
    expect(find.text('Three days in Lisbon'), findsOneWidget);

    await tester.ensureVisible(find.text('Plan my trip'));
    await tester.pump();
    await tester.tap(find.text('Packed'));
    await tester.pump();
    await _real(tester, () => tester.tap(find.text('Plan my trip')));
    await _real(tester, () {});

    expect(find.text('Tailor my Lisbon trip'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Lisbon at a packed pace'),
      200,
      scrollable: _list,
    );
    expect(find.text('Lisbon at a packed pace'), findsOneWidget);
  });
}
