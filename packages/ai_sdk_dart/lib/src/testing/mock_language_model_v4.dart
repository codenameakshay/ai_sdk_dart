import 'dart:async';
import 'dart:convert';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';

import '../utils/utils.dart';

/// A controllable mock language model for testing.
///
/// Mirrors `MockLanguageModelV1` from the JS AI SDK v6 `ai/test` sub-path.
///
/// ```dart
/// final model = MockLanguageModelV4(
///   response: [MockTextPart('Hello!')],
/// );
/// final result = await generateText(model: model, prompt: 'Hi');
/// expect(result.text, 'Hello!');
/// ```
class MockLanguageModelV4 extends LanguageModelV4 {
  MockLanguageModelV4({
    this.response = const [],
    this.finishReason = LanguageModelV4FinishReason.stop,
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
  final List<LanguageModelV4ContentPart> response;

  /// Finish reason to report.
  final LanguageModelV4FinishReason finishReason;

  final String? rawFinishReason;

  /// Token usage to report.
  final LanguageModelV4Usage? usage;

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
  String get specificationVersion => 'v4';

  /// All call options passed to [doGenerate] in the order they were called.
  final List<LanguageModelV4CallOptions> generateCalls = [];

  /// All call options passed to [doStream] in the order they were called.
  final List<LanguageModelV4CallOptions> streamCalls = [];

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    generateCalls.add(options);
    if (doGenerateError != null) throw doGenerateError!;
    return LanguageModelV4GenerateResult(
      content: response,
      finishReason: finishReason,
      rawFinishReason: rawFinishReason,
      usage: usage,
      warnings: warnings
          .map((warning) => LanguageModelV4OtherWarning(message: warning))
          .toList(growable: false),
      providerMetadata: providerMetadata,
    );
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    streamCalls.add(options);
    if (doStreamError != null) throw doStreamError!;

    final textId = generateId();
    final parts = <LanguageModelV4StreamPart>[];
    final streamWarnings = warnings
        .map((warning) => LanguageModelV4OtherWarning(message: warning))
        .toList(growable: false);

    parts.add(StreamPartStreamStart(warnings: streamWarnings));

    for (final part in response) {
      if (part is LanguageModelV4TextPart) {
        parts.add(StreamPartTextStart(id: textId));
        parts.add(StreamPartTextDelta(id: textId, delta: part.text));
        parts.add(StreamPartTextEnd(id: textId));
      } else if (part is LanguageModelV4ReasoningPart) {
        parts.add(const StreamPartReasoningStart(id: 'mock-reasoning'));
        parts.add(
          StreamPartReasoningDelta(id: 'mock-reasoning', delta: part.text),
        );
        parts.add(const StreamPartReasoningEnd(id: 'mock-reasoning'));
      } else if (part is LanguageModelV4ToolCallPart) {
        parts.add(
          StreamPartToolInputStart(
            id: part.toolCallId,
            toolName: part.toolName,
          ),
        );
        parts.add(
          StreamPartToolInputDelta(
            id: part.toolCallId,
            delta: jsonEncode(part.input),
          ),
        );
        parts.add(StreamPartToolInputEnd(id: part.toolCallId));
        parts.add(StreamPartToolCall(toolCall: part));
      }
    }

    parts.add(
      StreamPartFinish(
        finishReason: finishReason,
        rawFinishReason: rawFinishReason,
        usage: usage ?? const LanguageModelV4Usage(),
        providerMetadata: providerMetadata,
      ),
    );

    return LanguageModelV4StreamResult(
      stream: Stream.fromIterable(parts),
      warnings: streamWarnings,
    );
  }
}

/// Convenience constructor for a mock text content part.
///
/// ```dart
/// final model = MockLanguageModelV4(
///   response: [mockText('Hello!')],
/// );
/// ```
LanguageModelV4TextPart mockText(String text) =>
    LanguageModelV4TextPart(text: text);

/// Convenience constructor for a mock reasoning content part.
LanguageModelV4ReasoningPart mockReasoning(String text) =>
    LanguageModelV4ReasoningPart(text: text);

/// Convenience constructor for a mock tool call content part.
LanguageModelV4ToolCallPart mockToolCall({
  required String toolName,
  required Object input,
  String? toolCallId,
}) => LanguageModelV4ToolCallPart(
  toolCallId: toolCallId ?? generateId(),
  toolName: toolName,
  input: input,
);
