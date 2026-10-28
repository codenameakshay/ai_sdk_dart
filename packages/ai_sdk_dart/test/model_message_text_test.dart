import 'dart:typed_data';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

void main() {
  group('ModelMessage.text', () {
    test('returns content for a content-only message', () {
      final message = ModelMessage(
        role: ModelMessageRole.user,
        content: 'hello',
      );

      expect(message.text, 'hello');
    });

    test('returns empty string for empty content', () {
      final message = ModelMessage(role: ModelMessageRole.user, content: '');

      expect(message.text, '');
    });

    test('joins text parts in order without a separator', () {
      final message = ModelMessage.parts(
        role: ModelMessageRole.assistant,
        parts: const [
          LanguageModelV4TextPart(text: 'Hello, '),
          LanguageModelV4TextPart(text: 'world'),
        ],
      );

      expect(message.text, 'Hello, world');
    });

    test('excludes non-text parts from mixed parts', () {
      final message = ModelMessage.parts(
        role: ModelMessageRole.assistant,
        parts: const [
          LanguageModelV4ReasoningPart(text: 'thinking'),
          LanguageModelV4TextPart(text: 'Answer: '),
          LanguageModelV4ToolCallPart(
            toolCallId: 'c1',
            toolName: 'search',
            input: {'query': 'answer'},
          ),
          LanguageModelV4TextPart(text: '42'),
          LanguageModelV4ToolResultPart(
            toolCallId: 'c1',
            toolName: 'search',
            output: ToolResultOutputText('found'),
          ),
        ],
      );

      expect(message.text, 'Answer: 42');
    });

    test('returns empty string when parts contain no text parts', () {
      final message = ModelMessage.parts(
        role: ModelMessageRole.assistant,
        parts: const [LanguageModelV4ReasoningPart(text: 'thinking')],
      );

      expect(message.text, '');
    });

    test('excludes media, citations, approvals, and opaque parts', () {
      final message = ModelMessage.parts(
        role: ModelMessageRole.assistant,
        parts: [
          const LanguageModelV4TextPart(text: 'visible'),
          const LanguageModelV4ImagePart(image: DataContentBase64('image')),
          const LanguageModelV4FilePart(
            data: DataContentBase64('file'),
            mediaType: 'text/plain',
          ),
          const LanguageModelV4ReasoningFilePart(
            data: DataContentBase64('reasoning file'),
            mediaType: 'text/plain',
          ),
          LanguageModelV4RedactedReasoningPart(data: Uint8List(0)),
          const LanguageModelV4SourcePart(
            id: 'source',
            url: 'https://example.com',
            title: 'citation',
          ),
          const LanguageModelV4DocumentSourcePart(
            id: 'document',
            mediaType: 'text/plain',
            title: 'document citation',
          ),
          const LanguageModelV4ToolApprovalRequestPart(
            approvalId: 'approval',
            toolCall: LanguageModelV4ToolCallPart(
              toolCallId: 'call',
              toolName: 'search',
              input: 'query',
            ),
          ),
          const LanguageModelV4ToolApprovalResponse(
            approvalId: 'approval',
            approved: false,
            reason: 'denied',
          ),
          const LanguageModelV4OpaquePart(
            provider: 'custom',
            raw: {'text': 'hidden'},
          ),
          const LanguageModelV4TextPart(text: ' text'),
        ],
      );

      expect(message.text, 'visible text');
    });

    for (final role in ModelMessageRole.values) {
      test('extracts text independently of the ${role.name} role', () {
        expect(ModelMessage(role: role, content: 'content').text, 'content');
        expect(
          ModelMessage.parts(
            role: role,
            parts: const [LanguageModelV4TextPart(text: 'part')],
          ).text,
          'part',
        );
      });
    }

    test('reflects mutations to the supplied parts list on each read', () {
      final parts = <LanguageModelV4ContentPart>[
        const LanguageModelV4TextPart(text: 'first'),
      ];
      final message = ModelMessage.parts(
        role: ModelMessageRole.assistant,
        parts: parts,
      );

      expect(message.text, 'first');
      parts[0] = const LanguageModelV4TextPart(text: 'updated');
      parts.add(const LanguageModelV4TextPart(text: ' text'));
      expect(message.text, 'updated text');
      parts.clear();
      expect(message.text, '');
    });

    test('returns empty string for an empty parts list', () {
      final message = ModelMessage.parts(
        role: ModelMessageRole.assistant,
        parts: const [],
      );

      expect(message.text, '');
    });

    test('returns text parts from a provider message', () {
      final message = ModelMessage.fromProvider(
        const LanguageModelV4Message(
          role: LanguageModelV4Role.assistant,
          content: [
            LanguageModelV4TextPart(text: 'a'),
            LanguageModelV4ReasoningPart(text: 'r'),
            LanguageModelV4TextPart(text: 'b'),
          ],
        ),
      );

      expect(message.text, 'ab');
    });
  });
}
