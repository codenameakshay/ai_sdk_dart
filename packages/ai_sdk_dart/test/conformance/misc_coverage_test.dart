import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

/// Sweeps up the remaining one-off uncovered lines across the smaller core
/// helpers: parallel embedMany usage aggregation, base64 image decoding,
/// transcribe/speech timeout branches, dynamicTool input parsing, the tool
/// role in convertToModelMessages, and the model-message content classes.
void main() {
  group('embedMany usage aggregation across parallel chunks', () {
    test('sums token usage from multiple parallel calls', () async {
      final model = _UsageEmbeddingModel([0.1, 0.2], tokensPerCall: 4);
      final result = await embedMany(
        model: model,
        values: ['a', 'b', 'c', 'd'],
        maxParallelCalls: 1, // → four separate calls, each reporting 4 tokens.
      );
      expect(result.embeddings, hasLength(4));
      expect(result.usage, isNotNull);
      expect(result.usage!.tokens, 16);
    });

    test('usage is null in parallel mode when no call reports usage', () async {
      final model = _UsageEmbeddingModel([0.1], tokensPerCall: null);
      final result = await embedMany(
        model: model,
        values: ['a', 'b', 'c'],
        maxParallelCalls: 2,
      );
      expect(result.usage, isNull);
    });

    test('uneven final batch is handled (5 values, parallel=2)', () async {
      // 5 values / parallel 2 → 3 chunks, the last batch shorter than the
      // batch window, exercising the batchEnd clamp.
      final model = _UsageEmbeddingModel([0.5], tokensPerCall: 1);
      final result = await embedMany(
        model: model,
        values: ['a', 'b', 'c', 'd', 'e'],
        maxParallelCalls: 2,
      );
      expect(result.embeddings, hasLength(5));
      // 3 provider calls (chunks of 2, 2, 1), each reporting 1 token.
      expect(result.usage!.tokens, 3);
    });
  });

  group('decodeBase64Image', () {
    test('decodes a base64 string to raw bytes', () {
      final original = Uint8List.fromList([1, 2, 3, 4, 5]);
      final encoded = base64Encode(original);
      final decoded = decodeBase64Image(encoded);
      expect(decoded, original);
    });
  });

  group('transcribe / generateSpeech timeouts', () {
    test('transcribe completes within a generous timeout', () async {
      final model = FakeTranscriptionModel('hello world');
      final result = await transcribe(
        model: model,
        audio: Uint8List.fromList([0, 1, 2]),
        audioMediaType: 'audio/wav',
        timeout: const Duration(seconds: 5),
      );
      expect(result.text, 'hello world');
    });

    test('generateSpeech completes within a generous timeout', () async {
      final audio = Uint8List.fromList([9, 8, 7]);
      final model = FakeSpeechModel(audio: audio, mediaType: 'audio/mpeg');
      final result = await generateSpeech(
        model: model,
        text: 'hi',
        timeout: const Duration(seconds: 5),
      );
      expect(result.audio, audio);
      expect(result.mediaType, 'audio/mpeg');
    });
  });

  group('generateImage timeout path', () {
    test('completes within a generous timeout', () async {
      final model = _OneImageModel();
      final result = await generateImage(
        model: model,
        prompt: 'a cat',
        timeout: const Duration(seconds: 5),
      );
      expect(result.images, hasLength(1));
    });
  });

  group('dynamicTool input parsing', () {
    test('non-strict dynamicTool forwards raw input to the executor',
        () async {
      Object? received;
      final model = FakeMultiStepModel([
        const LanguageModelV3GenerateResult(
          content: [
            LanguageModelV3ToolCallPart(
              toolCallId: 'c1',
              toolName: 'dyn',
              input: {'any': 'thing'},
            ),
          ],
          finishReason: LanguageModelV3FinishReason.toolCalls,
        ),
        const LanguageModelV3GenerateResult(
          content: [LanguageModelV3TextPart(text: 'done')],
          finishReason: LanguageModelV3FinishReason.stop,
        ),
      ]);
      await generateText(
        model: model,
        prompt: 'go',
        maxSteps: 3,
        tools: {
          'dyn': dynamicTool<String>(
            execute: (input, _) async {
              received = input;
              return 'ok';
            },
          ),
        },
      );
      expect(received, {'any': 'thing'});
    });

    test('dynamicTool schema fromJson returns the raw JSON unchanged', () {
      final t = dynamicTool<String>(execute: (_, __) async => 'x');
      final parsed = t.inputSchema.fromJson({'k': 'v'});
      expect(parsed, {'k': 'v'});
    });
  });

  group('non-JSON-encodable tool output falls back to toString', () {
    test('generateText stringifies an unencodable tool output', () async {
      final model = FakeMultiStepModel([
        const LanguageModelV3GenerateResult(
          content: [
            LanguageModelV3ToolCallPart(
              toolCallId: 'c1',
              toolName: 'obj',
              input: {},
            ),
          ],
          finishReason: LanguageModelV3FinishReason.toolCalls,
        ),
        const LanguageModelV3GenerateResult(
          content: [LanguageModelV3TextPart(text: 'done')],
          finishReason: LanguageModelV3FinishReason.stop,
        ),
      ]);
      final result = await generateText(
        model: model,
        prompt: 'go',
        maxSteps: 3,
        tools: {
          'obj': tool<Map<String, dynamic>, Object?>(
            inputSchema: Schema<Map<String, dynamic>>(
              jsonSchema: const {'type': 'object'},
              fromJson: (json) => json,
            ),
            // A bare Object() is not JSON-encodable → toString() fallback.
            execute: (_, __) async => _Unencodable(),
          ),
        },
      );
      final output =
          result.steps.first.toolResults.single.output as ToolResultOutputText;
      expect(output.text, contains('Unencodable'));
    });
  });

  group('convertToModelMessages', () {
    test('converts a tool-role message', () {
      final messages = convertToModelMessages([
        const LanguageModelV3Message(
          role: LanguageModelV3Role.tool,
          content: [
            LanguageModelV3ToolResultPart(
              toolCallId: 'c1',
              toolName: 'echo',
              output: ToolResultOutputText('result'),
            ),
          ],
        ),
      ]);
      expect(messages.single.role, ModelMessageRole.tool);
      expect(messages.single.parts, isNotNull);
    });

    test('converts every role including a single-text shortcut', () {
      final messages = convertToModelMessages(const [
        LanguageModelV3Message(
          role: LanguageModelV3Role.system,
          content: [LanguageModelV3TextPart(text: 'sys')],
        ),
        LanguageModelV3Message(
          role: LanguageModelV3Role.user,
          content: [LanguageModelV3TextPart(text: 'hi')],
        ),
        LanguageModelV3Message(
          role: LanguageModelV3Role.assistant,
          content: [LanguageModelV3TextPart(text: 'yo')],
        ),
      ]);
      expect(messages.map((m) => m.role.name), ['system', 'user', 'assistant']);
      expect(messages[1].content, 'hi');
    });
  });

  group('model message content classes', () {
    test('ToolApprovalRequestContent stores its fields', () {
      const content = ToolApprovalRequestContent(
        approvalId: 'a1',
        toolCallId: 'tc1',
        toolName: 'danger',
        input: {'x': 1},
      );
      expect(content.approvalId, 'a1');
      expect(content.toolCallId, 'tc1');
      expect(content.toolName, 'danger');
      expect(content.input, {'x': 1});
    });

    test('ToolApprovalResponseContent stores its fields', () {
      const content = ToolApprovalResponseContent(
        approvalId: 'a1',
        approved: true,
        reason: 'looks safe',
      );
      expect(content.approvalId, 'a1');
      expect(content.approved, isTrue);
      expect(content.reason, 'looks safe');
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// An embedding model that reports a fixed token count per call (or none).
class _UsageEmbeddingModel implements EmbeddingModelV2<String> {
  _UsageEmbeddingModel(this.embedding, {required this.tokensPerCall});
  final List<double> embedding;
  final int? tokensPerCall;

  @override
  String get provider => 'fake';
  @override
  String get modelId => 'usage-embedding';
  @override
  String get specificationVersion => 'v2';

  @override
  Future<EmbeddingModelV2GenerateResult<String>> doEmbed(
    EmbeddingModelV2CallOptions<String> options,
  ) async {
    return EmbeddingModelV2GenerateResult(
      embeddings: options.values
          .map((v) => EmbeddingModelV2Embedding(value: v, embedding: embedding))
          .toList(),
      usage: tokensPerCall == null
          ? null
          : EmbeddingModelV2Usage(tokens: tokensPerCall),
    );
  }
}

/// A value whose toString is stable but which jsonEncode cannot serialize.
class _Unencodable {
  @override
  String toString() => 'Unencodable()';
}

class _OneImageModel implements ImageModelV3 {
  @override
  String get provider => 'fake';
  @override
  String get modelId => 'one-image';
  @override
  String get specificationVersion => 'v3';

  @override
  Future<ImageModelV3GenerateResult> doGenerate(
    ImageModelV3CallOptions options,
  ) async {
    return ImageModelV3GenerateResult(
      images: [
        GeneratedImage(
          bytes: Uint8List.fromList([1, 2, 3]),
          mediaType: 'image/png',
        ),
      ],
    );
  }
}
