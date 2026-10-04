// Drives the README screenshot states with scripted models, so no provider
// keys are needed. Each state prints a README_SHOT marker and holds still
// while the host captures the simulator, status bar included. From
// examples/advanced_app, with one iPhone simulator booted:
//
//   fvm flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/readme_screenshots_test.dart |
//   while IFS= read -r line; do
//     echo "$line"
//     case "$line" in *README_SHOT:*) xcrun simctl io booted screenshot \
//       "../../docs/screenshots/${line##*README_SHOT:}.png";; esac
//   done
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_dart/test.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:advanced_app/pages/conversation_page.dart';
import 'package:advanced_app/pages/responses_page.dart';
import 'package:advanced_app/pages/tools_chat_page.dart';

import '../test/support/scripted_models.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Widget themed(Widget home) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
      useMaterial3: true,
    ),
    home: home,
  );

  testWidgets('tools chat', (tester) async {
    await tester.pumpWidget(
      themed(const ToolsChatPage(fixture: ToolsChatFixture.sourcesTool)),
    );
    await _waitFor(tester, find.text('Example Weather Feed'));
    await _capture(tester, 'adv_02_tools_chat');
  });

  testWidgets('conversation with a pending approval', (tester) async {
    final agent = ToolLoopAgent(
      model: QueuedLanguageModel([
        [
          mockToolCall(
            toolName: 'deleteFile',
            input: {'path': 'reports/q3-draft.pdf'},
            toolCallId: 'call-delete-1',
          ),
        ],
        [mockText('Deleted reports/q3-draft.pdf.')],
      ]),
      tools: {
        'deleteFile': tool<Map<String, dynamic>, String>(
          inputSchema: Schema<Map<String, dynamic>>(
            jsonSchema: const {'type': 'object'},
            fromJson: (json) => json,
          ),
          execute: (input, _) async => 'Deleted ${input['path']}',
        ),
      },
      approvalPolicy: ToolApprovalPolicy.always,
    );
    await tester.pumpWidget(themed(ConversationPage(testAgent: agent)));
    await tester.enterText(
      find.byKey(const ValueKey('chat-composer-field')),
      'Delete the Q3 draft report.',
    );
    await tester.tap(find.byKey(const ValueKey('chat-composer-send')));
    await _waitFor(tester, find.byType(ToolApprovalCard));
    await _capture(tester, 'adv_10_conversation');
  });

  testWidgets('responses with web search', (tester) async {
    await tester.pumpWidget(
      themed(
        ResponsesPage(
          testModel: ResponsesFakeModel(
            reasoning:
                'The question is about a recent release, so search the web '
                'and cite the release notes.',
            text:
                'Flutter 3.44 is the current stable release. It ships Dart '
                '3.12, faster shader warm-up on iOS, and new Material 3 '
                'components.',
            sources: const [
              LanguageModelV4SourcePart(
                id: 'source-1',
                url: 'https://docs.flutter.dev/release/release-notes',
                title: 'Flutter release notes',
              ),
              LanguageModelV4SourcePart(
                id: 'source-2',
                url: 'https://dart.dev/guides/whats-new',
                title: "What's new in Dart",
              ),
            ],
          ),
        ),
      ),
    );
    final webSearch = find.byKey(const ValueKey('responses-web-search-switch'));
    if (!tester.widget<SwitchListTile>(webSearch).value) {
      await tester.tap(webSearch);
    }
    await tester.enterText(
      find.byKey(const ValueKey('responses-prompt-field')),
      "What's in the latest Flutter release?",
    );
    await tester.tap(find.byKey(const ValueKey('responses-ask-button')));
    await _waitFor(tester, find.textContaining('Flutter 3.44 is the current'));
    await tester.ensureVisible(find.byType(SourceCitations));
    await _capture(tester, 'adv_11_responses');
  });
}

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) break;
  }
  expect(finder, findsWidgets);
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  debugPrint('README_SHOT:$name');
  await Future<void>.delayed(const Duration(seconds: 3));
}
