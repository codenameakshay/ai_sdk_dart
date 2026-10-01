// Drives the README screenshot states through the app shell with the
// Local tab's scripted model, so no provider keys are needed. Each
// state prints a README_SHOT marker and holds still while the host captures
// the simulator, status bar included. From examples/flutter_chat, with one
// iPhone simulator booted:
//
//   fvm flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/readme_screenshots_test.dart |
//   while IFS= read -r line; do
//     echo "$line"
//     case "$line" in *README_SHOT:*) xcrun simctl io booted screenshot \
//       "../../docs/screenshots/${line##*README_SHOT:}.png";; esac
//   done
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_chat/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('conversation approval and RTL strings', (tester) async {
    await tester.pumpWidget(const App(initialIndex: 3));
    await tester.enterText(
      find.byKey(const ValueKey('chat-composer-field')),
      'Please delete the example file.',
    );
    await tester.tap(find.byKey(const ValueKey('chat-composer-send')));
    await _waitFor(tester, find.byKey(const ValueKey('tool-approval-approve')));
    await _capture(tester, '11_conversation_approval');

    await tester.tap(find.byKey(const ValueKey('tool-approval-approve')));
    await _waitFor(tester, find.text('Tool result: deleted /tmp/example'));
    await tester.tap(
      find.byKey(const ValueKey('conversation-language-toggle')),
    );
    await _capture(tester, '12_conversation_rtl');
  });
}

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) break;
  }
  expect(finder, findsWidgets);
}

Future<void> _capture(WidgetTester tester, String name) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  debugPrint('README_SHOT:$name');
  await Future<void>.delayed(const Duration(seconds: 3));
}
