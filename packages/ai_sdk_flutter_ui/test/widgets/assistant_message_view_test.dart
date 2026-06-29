import 'dart:typed_data';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('AssistantMessageView', () {
    testWidgets('renders text, reasoning, a tool call, and a source from parts',
        (tester) async {
      final message = ModelMessage.parts(
        role: ModelMessageRole.assistant,
        parts: const [
          LanguageModelV3ReasoningPart(text: 'thinking hard'),
          LanguageModelV3TextPart(text: 'Here is the answer'),
          LanguageModelV3ToolCallPart(
            toolCallId: 'c1',
            toolName: 'search',
            input: {'q': 'flutter'},
          ),
          LanguageModelV3SourcePart(
            id: 's1',
            url: 'https://example.com',
            title: 'Example',
          ),
        ],
      );

      await tester.pumpWidget(_wrap(AssistantMessageView(message: message)));

      expect(find.text('Here is the answer'), findsOneWidget);
      expect(find.byType(ReasoningView), findsOneWidget);
      expect(find.byType(ToolCallCard), findsOneWidget);
      expect(find.text('search'), findsOneWidget);
      expect(find.byType(SourceCitations), findsOneWidget);
      expect(find.text('Example'), findsOneWidget);
    });

    testWidgets('falls back to message.content when there are no parts', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const AssistantMessageView(
            message: ModelMessage(
              role: ModelMessageRole.assistant,
              content: 'plain text answer',
            ),
          ),
        ),
      );

      expect(find.text('plain text answer'), findsOneWidget);
    });

    testWidgets('uses the textBuilder slot for text parts', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AssistantMessageView(
            message: const ModelMessage(
              role: ModelMessageRole.assistant,
              content: '# Heading',
            ),
            textBuilder: (context, text) => Text(
              'custom:$text',
              key: const ValueKey('custom-text'),
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('custom-text')), findsOneWidget);
      expect(find.text('custom:# Heading'), findsOneWidget);
    });

    testWidgets('pairs a tool result with its call by toolCallId', (
      tester,
    ) async {
      final message = ModelMessage.parts(
        role: ModelMessageRole.assistant,
        parts: const [
          LanguageModelV3ToolCallPart(
            toolCallId: 'c1',
            toolName: 'search',
            input: {'q': 'flutter'},
          ),
        ],
      );

      await tester.pumpWidget(
        _wrap(
          AssistantMessageView(
            message: message,
            toolResults: const [
              LanguageModelV3ToolResultPart(
                toolCallId: 'c1',
                toolName: 'search',
                output: ToolResultOutputText('found it'),
              ),
            ],
          ),
        ),
      );

      expect(find.text('Result'), findsOneWidget);
      expect(find.text('found it'), findsOneWidget);
    });

    testWidgets('renders an approval card whose buttons fire callbacks', (
      tester,
    ) async {
      var approvedId = '';
      final message = ModelMessage.parts(
        role: ModelMessageRole.assistant,
        parts: const [
          LanguageModelV3ToolApprovalRequestPart(
            approvalId: 'approval_c1',
            toolCall: LanguageModelV3ToolCallPart(
              toolCallId: 'c1',
              toolName: 'deleteFile',
              input: {'path': '/x'},
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        _wrap(
          AssistantMessageView(
            message: message,
            onToolApprove: (request, _) => approvedId = request.approvalId,
            onToolDeny: (_, __) {},
          ),
        ),
      );

      var deniedId = '';
      await tester.pumpWidget(
        _wrap(
          AssistantMessageView(
            message: message,
            onToolApprove: (request, _) => approvedId = request.approvalId,
            onToolDeny: (request, _) => deniedId = request.approvalId,
          ),
        ),
      );

      expect(find.byType(ToolApprovalCard), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tool-approval-approve')));
      expect(approvedId, 'approval_c1');
      await tester.tap(find.byKey(const ValueKey('tool-approval-deny')));
      expect(deniedId, 'approval_c1');
    });

    testWidgets('renders images, files, and ignores non-inline parts', (
      tester,
    ) async {
      var tappedFile = false;
      final message = ModelMessage.parts(
        role: ModelMessageRole.assistant,
        parts: [
          LanguageModelV3ImagePart(
            image: DataContentUrl(Uri.parse('https://example.com/a.png')),
          ),
          LanguageModelV3FilePart(
            data: DataContentUrl(Uri.parse('https://example.com/f.pdf')),
            mediaType: 'application/pdf',
            filename: 'paper.pdf',
          ),
          LanguageModelV3RedactedReasoningPart(
            data: Uint8List.fromList(const [1, 2, 3]),
          ),
          const LanguageModelV3ToolResultPart(
            toolCallId: 'c1',
            toolName: 'x',
            output: ToolResultOutputText('y'),
          ),
          const LanguageModelV3ToolApprovalResponse(
            approvalId: 'a1',
            approved: true,
          ),
        ],
      );

      await tester.pumpWidget(
        _wrap(
          AssistantMessageView(
            message: message,
            onFileTap: (_) => tappedFile = true,
          ),
        ),
      );

      expect(find.byType(MessageImage), findsOneWidget);
      expect(find.byType(MessageAttachment), findsOneWidget);
      await tester.tap(find.text('paper.pdf'));
      expect(tappedFile, isTrue);
    });

    testWidgets('renders an approval part as a plain card without callbacks', (
      tester,
    ) async {
      final message = ModelMessage.parts(
        role: ModelMessageRole.assistant,
        parts: const [
          LanguageModelV3ToolApprovalRequestPart(
            approvalId: 'a1',
            toolCall: LanguageModelV3ToolCallPart(
              toolCallId: 'c1',
              toolName: 'doThing',
              input: {'a': 1},
            ),
          ),
        ],
      );

      await tester.pumpWidget(_wrap(AssistantMessageView(message: message)));

      expect(find.byType(ToolApprovalCard), findsNothing);
      expect(find.byType(ToolCallCard), findsOneWidget);
      expect(find.text('doThing'), findsOneWidget);
    });

    testWidgets('collapses to nothing for an empty message', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const AssistantMessageView(
            message: ModelMessage(
              role: ModelMessageRole.assistant,
              content: '',
            ),
          ),
        ),
      );

      expect(find.byType(SelectableText), findsNothing);
    });
  });
}
