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
