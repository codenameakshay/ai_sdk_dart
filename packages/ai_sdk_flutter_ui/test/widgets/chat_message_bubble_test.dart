import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ChatMessageBubble', () {
    testWidgets('renders user message text with selection support', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const ChatMessageBubble(
            message: ModelMessage(
              role: ModelMessageRole.user,
              content: 'hello there',
            ),
          ),
        ),
      );
      expect(find.text('hello there'), findsOneWidget);
      // SelectionArea keeps the text selectable without mounting an editor.
      expect(find.byType(SelectionArea), findsOneWidget);
    });

    testWidgets('renders assistant message', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ChatMessageBubble(
            message: ModelMessage(
              role: ModelMessageRole.assistant,
              content: 'I am the assistant',
            ),
          ),
        ),
      );
      expect(find.text('I am the assistant'), findsOneWidget);
    });

    testWidgets('shows a streaming cursor while streaming', (tester) async {
      await tester.pumpWidget(
        _wrap(ChatMessageBubble.text(text: 'partial', isStreaming: true)),
      );
      expect(find.text('partial'), findsOneWidget);
      expect(find.byKey(const ValueKey('streaming-cursor')), findsOneWidget);
      // Let the eased blink advance, then settle so no ticker dangles.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpWidget(_wrap(ChatMessageBubble.text(text: 'partial')));
    });

    testWidgets('empty content renders a placeholder ellipsis', (tester) async {
      await tester.pumpWidget(_wrap(ChatMessageBubble.text(text: '')));
      expect(find.text('…'), findsOneWidget);
    });

    testWidgets('renders the text parts of a parts-based message', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          ChatMessageBubble(
            message: ModelMessage.parts(
              role: ModelMessageRole.user,
              parts: [
                LanguageModelV4TextPart(text: 'look at '),
                LanguageModelV4ReasoningPart(text: 'hidden'),
                LanguageModelV4TextPart(text: 'this'),
              ],
            ),
          ),
        ),
      );
      expect(find.text('look at this'), findsOneWidget);
      expect(find.text('hidden'), findsNothing);
      expect(find.text('…'), findsNothing);
    });

    for (final (role, label) in [
      (ModelMessageRole.user, 'User message'),
      (ModelMessageRole.tool, 'Tool message'),
    ]) {
      testWidgets('exposes parts-based ${role.name} text to semantics', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          _wrap(
            ChatMessageBubble(
              message: ModelMessage.parts(
                role: role,
                parts: const [
                  LanguageModelV4TextPart(text: 'look at '),
                  LanguageModelV4ToolResultPart(
                    toolCallId: 'c1',
                    toolName: 'search',
                    output: ToolResultOutputText('hidden result'),
                  ),
                  LanguageModelV4TextPart(text: 'this'),
                ],
              ),
            ),
          ),
        );

        final node = tester
            .getSemantics(find.byType(ChatMessageBubble))
            .getSemanticsData();
        expect(node.label, label);
        expect(node.value, 'look at this');
        expect(find.text('look at this'), findsOneWidget);
        expect(find.text('hidden result'), findsNothing);
        semantics.dispose();
      });
    }

    testWidgets('updates parts text, placeholder, and cursor on rebuild', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      Widget bubble(
        List<LanguageModelV4ContentPart> parts, {
        bool isStreaming = true,
      }) => _wrap(
        ChatMessageBubble(
          message: ModelMessage.parts(
            role: ModelMessageRole.assistant,
            parts: parts,
          ),
          isStreaming: isStreaming,
        ),
      );

      await tester.pumpWidget(
        bubble(const [LanguageModelV4TextPart(text: 'first answer')]),
      );
      expect(find.text('first answer'), findsOneWidget);
      expect(find.byKey(const ValueKey('streaming-cursor')), findsOneWidget);

      await tester.pumpWidget(
        bubble(const [LanguageModelV4ReasoningPart(text: 'hidden')]),
      );
      expect(find.text('…'), findsOneWidget);
      expect(find.text('first answer'), findsNothing);
      expect(find.text('hidden'), findsNothing);
      expect(
        tester
            .getSemantics(find.byType(ChatMessageBubble))
            .getSemanticsData()
            .value,
        '…',
      );
      expect(find.byKey(const ValueKey('streaming-cursor')), findsOneWidget);

      await tester.pumpWidget(
        bubble(const [
          LanguageModelV4TextPart(text: 'new answer'),
        ], isStreaming: false),
      );
      expect(find.text('new answer'), findsOneWidget);
      expect(find.text('…'), findsNothing);
      expect(
        tester
            .getSemantics(find.byType(ChatMessageBubble))
            .getSemanticsData()
            .value,
        'new answer',
      );
      expect(find.byKey(const ValueKey('streaming-cursor')), findsNothing);
      semantics.dispose();
    });

    testWidgets('renders a tool message with the tool styling branch', (
      tester,
    ) async {
      // Non-const so the constructor body is exercised at runtime, and a tool
      // role so the dedicated tool color branch is taken.
      await tester.pumpWidget(
        _wrap(
          ChatMessageBubble(
            message: ModelMessage(
              role: ModelMessageRole.tool,
              content: 'tool output',
            ),
          ),
        ),
      );
      expect(find.text('tool output'), findsOneWidget);
      // Left-aligned like assistant/system (not right-aligned like user).
      final align = tester.widget<Align>(find.byType(Align));
      expect(align.alignment, AlignmentDirectional.centerStart);
    });

    testWidgets('resolves user alignment against RTL direction', (
      tester,
    ) async {
      Widget harness(TextDirection direction) => MaterialApp(
        home: Directionality(
          textDirection: direction,
          child: const Scaffold(
            body: ChatMessageBubble(
              message: ModelMessage(
                role: ModelMessageRole.user,
                content: 'rtl-aware',
              ),
            ),
          ),
        ),
      );

      await tester.pumpWidget(harness(TextDirection.ltr));
      final ltrBubble = find.descendant(
        of: find.byType(Align),
        matching: find.byType(Container),
      );
      final ltrLeft = tester.getTopLeft(ltrBubble).dx;

      await tester.pumpWidget(harness(TextDirection.rtl));
      final rtlBubble = find.descendant(
        of: find.byType(Align),
        matching: find.byType(Container),
      );
      final rtlLeft = tester.getTopLeft(rtlBubble).dx;

      expect(rtlLeft, lessThan(ltrLeft));
    });

    testWidgets('message text keeps its own direction', (tester) async {
      Widget bubble(String content) => MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: ChatMessageBubble(
              message: ModelMessage(
                role: ModelMessageRole.user,
                content: content,
              ),
            ),
          ),
        ),
      );

      await tester.pumpWidget(bubble('Delete the file.'));
      expect(
        tester.widget<Text>(find.text('Delete the file.')).textDirection,
        TextDirection.ltr,
      );

      await tester.pumpWidget(bubble('احذف الملف.'));
      expect(
        tester.widget<Text>(find.text('احذف الملف.')).textDirection,
        TextDirection.rtl,
      );
    });
  });
}
