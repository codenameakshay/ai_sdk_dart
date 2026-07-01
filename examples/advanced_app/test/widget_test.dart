import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advanced_app/main.dart';
import 'package:advanced_app/pages/widget_gallery_page.dart';

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

  testWidgets('Widget Gallery renders the prebuilt widgets offline', (
    tester,
  ) async {
    // A tall surface so the whole (lazily-built) gallery list is laid out.
    await tester.binding.setSurfaceSize(const Size(800, 5000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // The gallery is driven entirely by sample data, so it renders without a
    // network call or API key.
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

  testWidgets('Widget Gallery copy action shows a confirmation', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 5000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Stub the clipboard so the (async) copy completes and fires onCopied.
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
    await tester.pump(); // resolve the async clipboard write + onCopied
    await tester.pump(const Duration(milliseconds: 50)); // SnackBar enters

    expect(find.text('Copied to clipboard'), findsOneWidget);
  });
}
