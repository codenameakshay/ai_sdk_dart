import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advanced_app/main.dart';

void main() {
  testWidgets('App boots and shows the prebuilt chat composer', (tester) async {
    await tester.pumpWidget(const App());
    await tester.pump();

    // The default page (Provider Chat) is built from the prebuilt
    // AiChatScaffold, so its ChatComposer renders without any network call.
    expect(find.byType(ChatComposer), findsOneWidget);
    expect(find.text('Provider Chat'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Navigation drawer lists the feature pages', (tester) async {
    await tester.pumpWidget(const App());

    // Open the shell's navigation drawer.
    final shell = tester.firstState<ScaffoldState>(find.byType(Scaffold));
    shell.openDrawer();
    await tester.pumpAndSettle();

    // The drawer's ListView lazily builds children, so assert on the header
    // and the items above the fold.
    expect(find.text('AI SDK Advanced'), findsOneWidget);
    expect(find.text('Tools Chat'), findsOneWidget);
    expect(find.text('Multimodal'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
