import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_flutter_ui/src/widgets/content_direction.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('content direction follows the first letter across Unicode planes', () {
    for (final text in [
      'שלום',
      '123! العربية',
      '\u{10800}',
      '\u{10D00}',
      '\u{1E800}',
      '\u{1E900}',
      '\u{1EE00}',
    ]) {
      expect(contentDirection(text), TextDirection.rtl, reason: text);
    }
    for (final text in ['123! Hello', '\u{10400}', '\u{1D400}', '\u{20000}']) {
      expect(contentDirection(text), TextDirection.ltr, reason: text);
    }
    for (final text in ['', '123 !?', '\uFEFF']) {
      expect(contentDirection(text), isNull, reason: text);
    }
  });

  testWidgets('message text renders supplementary RTL letters right-to-left', (
    tester,
  ) async {
    const text = '123! \u{1E900}\u{1E922}';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ChatMessageBubble.text(text: text)),
      ),
    );

    expect(
      tester.widget<Text>(find.text(text)).textDirection,
      TextDirection.rtl,
    );
  });

  testWidgets('custom assistant text inherits its content direction', (
    tester,
  ) async {
    for (final (text, direction) in [
      ('123! Hello.', TextDirection.ltr),
      ('123! العربية', TextDirection.rtl),
      ('123!?', TextDirection.rtl),
    ]) {
      TextDirection? builderDirection;
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: AssistantMessageView(
                message: ModelMessage(
                  role: ModelMessageRole.assistant,
                  content: text,
                ),
                textBuilder: (context, text) {
                  builderDirection = Directionality.of(context);
                  return Text(text);
                },
              ),
            ),
          ),
        ),
      );

      final paragraph = find.descendant(
        of: find.text(text),
        matching: find.byType(RichText),
      );
      expect(builderDirection, direction);
      expect(
        tester.renderObject<RenderParagraph>(paragraph).textDirection,
        direction,
      );
    }
  });
}
