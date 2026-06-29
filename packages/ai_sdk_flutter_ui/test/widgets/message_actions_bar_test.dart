import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('MessageActionsBar', () {
    testWidgets('copy button writes to the clipboard and fires onCopied', (
      tester,
    ) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      var copied = false;
      await tester.pumpWidget(
        _wrap(
          MessageActionsBar(
            copyText: 'hello world',
            onCopied: () => copied = true,
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('message-copy')));
      await tester.pump();

      expect(copied, isTrue);
      expect(calls, hasLength(1));
      expect(
        (calls.single.arguments as Map)['text'],
        'hello world',
      );
    });

    testWidgets('regenerate button fires onRegenerate', (tester) async {
      var regenerated = false;
      await tester.pumpWidget(
        _wrap(MessageActionsBar(onRegenerate: () => regenerated = true)),
      );

      await tester.tap(find.byKey(const ValueKey('message-regenerate')));
      expect(regenerated, isTrue);
    });

    testWidgets('thumbs up and down fire their callbacks', (tester) async {
      var up = false;
      var down = false;
      await tester.pumpWidget(
        _wrap(
          MessageActionsBar(
            onThumbUp: () => up = true,
            onThumbDown: () => down = true,
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('message-thumb-up')));
      await tester.tap(find.byKey(const ValueKey('message-thumb-down')));
      expect(up, isTrue);
      expect(down, isTrue);
    });

    testWidgets('only renders actions whose inputs are provided', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(MessageActionsBar(onRegenerate: () {})),
      );

      expect(find.byKey(const ValueKey('message-regenerate')), findsOneWidget);
      expect(find.byKey(const ValueKey('message-copy')), findsNothing);
      expect(find.byKey(const ValueKey('message-thumb-up')), findsNothing);
      expect(find.byKey(const ValueKey('message-thumb-down')), findsNothing);
    });
  });
}
