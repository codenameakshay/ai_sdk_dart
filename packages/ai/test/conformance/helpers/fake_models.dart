import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ai/ai.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';

// ---------------------------------------------------------------------------
// Fake Language Models
// ---------------------------------------------------------------------------

/// A fake language model that returns a static text response.
///
/// Optionally supports reasoning, sources, and custom usage/finishReason.
class FakeTextModel implements LanguageModelV3 {
  FakeTextModel(
    this.text, {
    this.finishReason = LanguageModelV3FinishReason.stop,
    this.rawFinishReason = 'stop',
    this.usage,
    this.warnings = const [],
    this.reasoning,
    this.redactedReasoning = false,
    this.sources = const [],
    this.provider = 'fake',
    this.modelId = 'fake-model',
    this.providerMetadata,
  });

  final String text;
  final LanguageModelV3FinishReason finishReason;
  final String? rawFinishReason;
  final LanguageModelV3Usage? usage;
  final List<String> warnings;
  final String? reasoning;
  final bool redactedReasoning;
  final List<LanguageModelV3SourcePart> sources;
  final ProviderMetadata? providerMetadata;

  @override
  final String provider;

  @override
  final String modelId;

  @override
  String get specificationVersion => 'v3';

  /// Last options passed to doGenerate — useful for verifying what was sent.
  LanguageModelV3CallOptions? lastCallOptions;

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async {
    lastCallOptions = options;
    final content = <LanguageModelV3ContentPart>[
      if (reasoning != null) LanguageModelV3ReasoningPart(text: reasoning!),
      if (redactedReasoning)
        LanguageModelV3RedactedReasoningPart(data: Uint8List(0)),
      LanguageModelV3TextPart(text: text),
      ...sources,
    ];
    return LanguageModelV3GenerateResult(
      content: content,
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
    lastCallOptions = options;
    return LanguageModelV3StreamResult(
      stream: simulateReadableStream(
        parts: [
          StreamPartTextStart(id: 'text-1'),
          StreamPartTextDelta(id: 'text-1', delta: text),
          StreamPartTextEnd(id: 'text-1'),
          StreamPartFinish(
            finishReason: finishReason,
            rawFinishReason: rawFinishReason,
            usage: usage,
          ),
        ],
      ),
      // Pass warnings via rawResponse so streamText can extract them.
      rawResponse: warnings.isEmpty
          ? null
          : <Object?, Object?>{'warnings': warnings},
    );
  }
}

/// A fake language model backed by a list of stream parts.
///
/// Useful for testing exact event sequences in streamText.
class FakeStreamModel implements LanguageModelV3 {
  FakeStreamModel(
    this.parts, {
    this.provider = 'fake',
    this.modelId = 'fake-stream-model',
  });

  final List<LanguageModelV3StreamPart> parts;

  @override
  final String provider;

  @override
  final String modelId;

  @override
  String get specificationVersion => 'v3';

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async {
    final textParts = parts.whereType<StreamPartTextDelta>();
    final text = textParts.map((p) => p.delta).join();
    final finish = parts.whereType<StreamPartFinish>().firstOrNull;
    return LanguageModelV3GenerateResult(
      content: [LanguageModelV3TextPart(text: text)],
      finishReason: finish?.finishReason ?? LanguageModelV3FinishReason.stop,
      usage: finish?.usage,
    );
  }

  @override
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  ) async {
    return LanguageModelV3StreamResult(
      stream: simulateReadableStream(parts: parts),
    );
  }
}

/// A fake language model that emits a stream error.
class FakeErrorStreamModel implements LanguageModelV3 {
  FakeErrorStreamModel(
    this.error, {
    this.provider = 'fake',
    this.modelId = 'fake-error-stream-model',
  });

  final Object error;

  @override
  final String provider;

  @override
  final String modelId;

  @override
  String get specificationVersion => 'v3';

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async {
    throw error;
  }

  @override
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  ) async {
    return LanguageModelV3StreamResult(
      stream: Stream<LanguageModelV3StreamPart>.fromIterable([
        StreamPartError(error: error),
        StreamPartFinish(finishReason: LanguageModelV3FinishReason.error),
      ]),
    );
  }
}

/// A fake language model that returns a single tool call.
class FakeToolModel implements LanguageModelV3 {
  FakeToolModel({
    required this.toolName,
    required this.toolInput,
    this.toolCallId = 'call-1',
    this.provider = 'fake',
    this.modelId = 'fake-tool-model',
  });

  final String toolName;
  final Object toolInput;
  final String toolCallId;

  @override
  final String provider;

  @override
  final String modelId;

  @override
  String get specificationVersion => 'v3';

  LanguageModelV3CallOptions? lastCallOptions;

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async {
    lastCallOptions = options;
    return LanguageModelV3GenerateResult(
      content: [
        LanguageModelV3ToolCallPart(
          toolCallId: toolCallId,
          toolName: toolName,
          input: toolInput,
        ),
      ],
      finishReason: LanguageModelV3FinishReason.toolCalls,
      rawFinishReason: 'tool_calls',
    );
  }

  @override
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  ) async {
    lastCallOptions = options;
    final argsJson = jsonEncode(toolInput);
    return LanguageModelV3StreamResult(
      stream: simulateReadableStream(
        parts: [
          StreamPartToolCallStart(
            toolCallId: toolCallId,
            toolName: toolName,
          ),
          StreamPartToolCallDelta(
            toolCallId: toolCallId,
            toolName: toolName,
            argsTextDelta: argsJson,
          ),
          StreamPartToolCallEnd(
            toolCallId: toolCallId,
            toolName: toolName,
            input: toolInput,
          ),
          StreamPartFinish(
            finishReason: LanguageModelV3FinishReason.toolCalls,
          ),
        ],
      ),
    );
  }
}

/// A fake language model that cycles through multiple responses.
///
/// Useful for multi-step testing where the first call returns a tool call
/// and subsequent calls return text responses.
class FakeMultiStepModel implements LanguageModelV3 {
  FakeMultiStepModel(
    this.responses, {
    this.provider = 'fake',
    this.modelId = 'fake-multistep-model',
  });

  final List<LanguageModelV3GenerateResult> responses;
  int _callCount = 0;

  @override
  final String provider;

  @override
  final String modelId;

  @override
  String get specificationVersion => 'v3';

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async {
    return responses[_callCount++ % responses.length];
  }

  @override
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  ) async {
    final result = await doGenerate(options);
    final parts = <LanguageModelV3StreamPart>[];
    for (final part in result.content) {
      if (part is LanguageModelV3TextPart) {
        parts.add(StreamPartTextStart(id: 'text-1'));
        parts.add(StreamPartTextDelta(id: 'text-1', delta: part.text));
        parts.add(StreamPartTextEnd(id: 'text-1'));
      } else if (part is LanguageModelV3ToolCallPart) {
        parts.add(
          StreamPartToolCallStart(
            toolCallId: part.toolCallId,
            toolName: part.toolName,
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
        finishReason: result.finishReason,
        usage: result.usage,
      ),
    );
    return LanguageModelV3StreamResult(
      stream: simulateReadableStream(parts: parts),
    );
  }
}

/// A fake language model that always throws on doGenerate/doStream.
class FakeErrorModel implements LanguageModelV3 {
  FakeErrorModel(
    this.error, {
    this.provider = 'fake',
    this.modelId = 'fake-error-model',
  });

  final Object error;

  @override
  final String provider;

  @override
  final String modelId;

  @override
  String get specificationVersion => 'v3';

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async {
    throw error;
  }

  @override
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  ) async {
    throw error;
  }
}

/// A fake language model that captures all call options for inspection.
class FakeCapturingModel implements LanguageModelV3 {
  FakeCapturingModel({
    this.responseText = '',
    this.provider = 'fake',
    this.modelId = 'fake-capturing-model',
  });

  final String responseText;

  @override
  final String provider;

  @override
  final String modelId;

  @override
  String get specificationVersion => 'v3';

  final List<LanguageModelV3CallOptions> capturedOptions = [];

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async {
    capturedOptions.add(options);
    return LanguageModelV3GenerateResult(
      content: [LanguageModelV3TextPart(text: responseText)],
      finishReason: LanguageModelV3FinishReason.stop,
    );
  }

  @override
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  ) async {
    capturedOptions.add(options);
    return LanguageModelV3StreamResult(
      stream: simulateReadableStream(
        parts: [
          StreamPartTextStart(id: 'text-1'),
          StreamPartTextDelta(id: 'text-1', delta: responseText),
          StreamPartTextEnd(id: 'text-1'),
          StreamPartFinish(finishReason: LanguageModelV3FinishReason.stop),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Fake Embedding Model
// ---------------------------------------------------------------------------

/// A fake embedding model that returns a fixed embedding vector for any input.
class FakeEmbeddingModel implements EmbeddingModelV2<String> {
  FakeEmbeddingModel(
    this.embedding, {
    this.usage,
    this.provider = 'fake',
    this.modelId = 'fake-embedding-model',
  });

  final List<double> embedding;
  final EmbeddingModelV2Usage? usage;

  @override
  final String provider;

  @override
  final String modelId;

  @override
  String get specificationVersion => 'v2';

  @override
  Future<EmbeddingModelV2GenerateResult<String>> doEmbed(
    EmbeddingModelV2CallOptions<String> options,
  ) async {
    return EmbeddingModelV2GenerateResult(
      embeddings: options.values
          .map(
            (v) => EmbeddingModelV2Embedding(value: v, embedding: embedding),
          )
          .toList(),
      usage: usage,
    );
  }
}

// ---------------------------------------------------------------------------
// Fake Speech Model
// ---------------------------------------------------------------------------

/// A fake speech model that returns fixed audio bytes.
class FakeSpeechModel implements SpeechModelV1 {
  FakeSpeechModel({
    required this.audio,
    this.mediaType = 'audio/mpeg',
    this.provider = 'fake',
    this.modelId = 'fake-speech-model',
  });

  final Uint8List audio;
  final String mediaType;

  @override
  final String provider;

  @override
  final String modelId;

  @override
  String get specificationVersion => 'v1';

  /// Last options passed to doGenerate for verification.
  SpeechModelV1CallOptions? lastOptions;

  @override
  Future<SpeechModelV1GenerateResult> doGenerate(
    SpeechModelV1CallOptions options,
  ) async {
    lastOptions = options;
    return SpeechModelV1GenerateResult(audio: audio, mediaType: mediaType);
  }
}

// ---------------------------------------------------------------------------
// Fake Transcription Model
// ---------------------------------------------------------------------------

/// A fake transcription model that returns fixed text.
class FakeTranscriptionModel implements TranscriptionModelV1 {
  FakeTranscriptionModel(
    this.text, {
    this.provider = 'fake',
    this.modelId = 'fake-transcription-model',
  });

  final String text;

  @override
  final String provider;

  @override
  final String modelId;

  @override
  String get specificationVersion => 'v1';

  /// Last options passed to doGenerate for verification.
  TranscriptionModelV1CallOptions? lastOptions;

  @override
  Future<TranscriptionModelV1GenerateResult> doGenerate(
    TranscriptionModelV1CallOptions options,
  ) async {
    lastOptions = options;
    return TranscriptionModelV1GenerateResult(text: text);
  }
}
