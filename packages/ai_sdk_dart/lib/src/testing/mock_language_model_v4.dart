import 'dart:async';
import 'dart:convert';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';

import '../utils/utils.dart';

/// A controllable mock language model for testing.
///
/// Mirrors `MockLanguageModelV1` from the JS AI SDK v6 `ai/test` sub-path.
///
/// ```dart
/// final model = MockLanguageModelV3(
///   response: [MockTextPart('Hello!')],
/// );
/// final result = await generateText(model: model, prompt: 'Hi');
/// expect(result.text, 'Hello!');
/// ```
class MockLanguageModelV3 implements LanguageModelV3 {
  MockLanguageModelV3({
    this.response = const [],
    this.finishReason = LanguageModelV3FinishReason.stop,
    this.rawFinishReason = 'stop',
    this.usage,
    this.warnings = const [],
    this.providerMetadata,
    this.doGenerateError,
    this.doStreamError,
    this.provider = 'mock',
    this.modelId = 'mock-language-model',
  });

  /// Content parts to return from every call.
  final List<LanguageModelV3ContentPart> response;

  /// Finish reason to report.
  final LanguageModelV3FinishReason finishReason;

  final String? rawFinishReason;

  /// Token usage to report.
  final LanguageModelV3Usage? usage;

  /// Warnings to report.
  final List<String> warnings;

  final ProviderMetadata? providerMetadata;

  /// If set, [doGenerate] throws this error instead of returning a response.
  final Object? doGenerateError;

  /// If set, [doStream] throws this error instead of returning a stream.
  final Object? doStreamError;

  @override
  final String provider;

  @override
  final String modelId;

  @override
  String get specificationVersion => 'v3';

  /// All call options passed to [doGenerate] in the order they were called.
  final List<LanguageModelV3CallOptions> generateCalls = [];

  /// All call options passed to [doStream] in the order they were called.
  final List<LanguageModelV3CallOptions> streamCalls = [];

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async {
    generateCalls.add(options);
    if (doGenerateError != null) throw doGenerateError!;
    return LanguageModelV3GenerateResult(
      content: response,
      finishReason: finishReason,
      rawFinishReason: rawFinishReason,
      usage: usage,
      warnings: warnings,
      providerMetadata: providerMetadata,
    );
  }

  @override
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  ) async {
    streamCalls.add(options);
    if (doStreamError != null) throw doStreamError!;

    final textId = generateId();
    final parts = <LanguageModelV3StreamPart>[];

    for (final part in response) {
      if (part is LanguageModelV3TextPart) {
        parts.add(StreamPartTextStart(id: textId));
        parts.add(StreamPartTextDelta(id: textId, delta: part.text));
        parts.add(StreamPartTextEnd(id: textId));
      } else if (part is LanguageModelV3ReasoningPart) {
        parts.add(StreamPartReasoningDelta(delta: part.text));
      } else if (part is LanguageModelV3ToolCallPart) {
        parts.add(
          StreamPartToolCallStart(
            toolCallId: part.toolCallId,
            toolName: part.toolName,
          ),
        );
        parts.add(
          StreamPartToolCallDelta(
            toolCallId: part.toolCallId,
            toolName: part.toolName,
            argsTextDelta: jsonEncode(part.input),
          ),
        );
        parts.add(
          StreamPartToolCallEnd(
            toolCallId: part.toolCallId,
            toolName: part.toolName,
            input: part.input,
          ),
        );
      }
    }

    parts.add(
      StreamPartFinish(
        finishReason: finishReason,
        rawFinishReason: rawFinishReason,
        usage: usage,
        providerMetadata: providerMetadata,
      ),
    );

    return LanguageModelV3StreamResult(
      stream: Stream.fromIterable(parts),
      rawResponse: warnings.isEmpty
          ? null
          : <Object?, Object?>{'warnings': warnings},
    );
  }
}

/// Convenience constructor for a mock text content part.
///
/// ```dart
/// final model = MockLanguageModelV3(
///   response: [mockText('Hello!')],
/// );
/// ```
LanguageModelV3TextPart mockText(String text) =>
    LanguageModelV3TextPart(text: text);

/// Convenience constructor for a mock reasoning content part.
LanguageModelV3ReasoningPart mockReasoning(String text) =>
    LanguageModelV3ReasoningPart(text: text);

/// Convenience constructor for a mock tool call content part.
LanguageModelV3ToolCallPart mockToolCall({
  required String toolName,
  required Object input,
  String? toolCallId,
}) =>
    LanguageModelV3ToolCallPart(
      toolCallId: toolCallId ?? generateId(),
      toolName: toolName,
      input: input,
    );
