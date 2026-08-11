import 'dart:convert';

import 'package:ai_sdk_dart/test.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

/// Exercises the streaming code paths of the public mock models that the
/// existing tests only drive via doGenerate: reasoning + tool-call fan-out in
/// `MockLanguageModelV4.doStream`, the structured warnings surface, and the
/// `specificationVersion` getters.
void main() {
  group('MockLanguageModelV4 streaming fan-out', () {
    test('specificationVersion is v4', () {
      final model = MockLanguageModelV4(response: [mockText('hi')]);
      expect(model.specificationVersion, 'v4');
    });

    test('doStream emits reasoning deltas for reasoning parts', () async {
      final model = MockLanguageModelV4(
        response: [mockReasoning('thinking'), mockText('answer')],
      );
      final result = await model.doStream(
        const LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(messages: []),
        ),
      );
      final parts = await result.stream.toList();
      expect(parts.whereType<StreamPartReasoningDelta>(), hasLength(1));
      expect(
        parts.whereType<StreamPartReasoningDelta>().single.delta,
        'thinking',
      );
      expect(parts.whereType<StreamPartTextDelta>(), hasLength(1));
    });

    test('doStream fans out tool-call start/delta/end parts', () async {
      final model = MockLanguageModelV4(
        response: [
          mockToolCall(
            toolName: 'search',
            input: const {'q': 'x'},
            toolCallId: 'tc-1',
          ),
        ],
        finishReason: LanguageModelV4FinishReason.toolCalls,
        rawFinishReason: 'tool_calls',
      );
      final result = await model.doStream(
        const LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(messages: []),
        ),
      );
      final parts = await result.stream.toList();
      expect(parts.whereType<StreamPartToolInputStart>(), hasLength(1));
      final delta = parts.whereType<StreamPartToolInputDelta>().single;
      expect(jsonDecode(delta.delta), {'q': 'x'});
      expect(parts.whereType<StreamPartToolInputEnd>(), hasLength(1));
      final call = parts.whereType<StreamPartToolCall>().single.toolCall;
      expect(call.input, {'q': 'x'});
      final finish = parts.whereType<StreamPartFinish>().single;
      expect(finish.finishReason, LanguageModelV4FinishReason.toolCalls);
    });

    test('doStream exposes structured warnings on the stream result', () async {
      final model = MockLanguageModelV4(
        response: [mockText('hi')],
        warnings: const ['deprecated-param'],
      );
      final result = await model.doStream(
        const LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(messages: []),
        ),
      );
      expect(
        result.warnings,
        contains(
          isA<LanguageModelV4OtherWarning>().having(
            (warning) => warning.message,
            'message',
            'deprecated-param',
          ),
        ),
      );
      await result.stream.toList();
    });

    test('records both generate and stream call options', () async {
      final model = MockLanguageModelV4(response: [mockText('hi')]);
      await model.doGenerate(
        const LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(messages: []),
        ),
      );
      final stream = await model.doStream(
        const LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(messages: []),
        ),
      );
      await stream.stream.toList();
      expect(model.generateCalls, hasLength(1));
      expect(model.streamCalls, hasLength(1));
    });
  });

  group('MockEmbeddingModelV2', () {
    test('specificationVersion is v2', () {
      final model = MockEmbeddingModelV2<String>(embedding: const [0.1]);
      expect(model.specificationVersion, 'v2');
    });
  });
}
