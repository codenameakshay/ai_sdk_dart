import 'dart:convert';

import 'package:ai_sdk_dart/test.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

/// Exercises the streaming code paths of the public mock models that the
/// existing tests only drive via doGenerate: reasoning + tool-call fan-out in
/// `MockLanguageModelV3.doStream`, the warnings rawResponse envelope, and the
/// `specificationVersion` getters.
void main() {
  group('MockLanguageModelV3 streaming fan-out', () {
    test('specificationVersion is v3', () {
      final model = MockLanguageModelV3(response: [mockText('hi')]);
      expect(model.specificationVersion, 'v3');
    });

    test('doStream emits reasoning deltas for reasoning parts', () async {
      final model = MockLanguageModelV3(
        response: [mockReasoning('thinking'), mockText('answer')],
      );
      final result = await model.doStream(
        const LanguageModelV3CallOptions(
          prompt: LanguageModelV3Prompt(messages: []),
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
      final model = MockLanguageModelV3(
        response: [
          mockToolCall(
            toolName: 'search',
            input: const {'q': 'x'},
            toolCallId: 'tc-1',
          ),
        ],
        finishReason: LanguageModelV3FinishReason.toolCalls,
        rawFinishReason: 'tool_calls',
      );
      final result = await model.doStream(
        const LanguageModelV3CallOptions(
          prompt: LanguageModelV3Prompt(messages: []),
        ),
      );
      final parts = await result.stream.toList();
      expect(parts.whereType<StreamPartToolCallStart>(), hasLength(1));
      final delta = parts.whereType<StreamPartToolCallDelta>().single;
      expect(jsonDecode(delta.argsTextDelta), {'q': 'x'});
      final end = parts.whereType<StreamPartToolCallEnd>().single;
      expect(end.input, {'q': 'x'});
      final finish = parts.whereType<StreamPartFinish>().single;
      expect(finish.finishReason, LanguageModelV3FinishReason.toolCalls);
    });

    test('doStream exposes warnings via the rawResponse envelope', () async {
      final model = MockLanguageModelV3(
        response: [mockText('hi')],
        warnings: const ['deprecated-param'],
      );
      final result = await model.doStream(
        const LanguageModelV3CallOptions(
          prompt: LanguageModelV3Prompt(messages: []),
        ),
      );
      expect(result.rawResponse, isA<Map>());
      expect(
        (result.rawResponse! as Map)['warnings'],
        contains('deprecated-param'),
      );
      await result.stream.toList();
    });

    test('records both generate and stream call options', () async {
      final model = MockLanguageModelV3(response: [mockText('hi')]);
      await model.doGenerate(
        const LanguageModelV3CallOptions(
          prompt: LanguageModelV3Prompt(messages: []),
        ),
      );
      final stream = await model.doStream(
        const LanguageModelV3CallOptions(
          prompt: LanguageModelV3Prompt(messages: []),
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
