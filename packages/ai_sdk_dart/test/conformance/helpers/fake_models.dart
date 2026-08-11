import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';

// ---------------------------------------------------------------------------
// Fake Language Models
// ---------------------------------------------------------------------------

/// A fake language model that returns a static text response.
///
/// Optionally supports reasoning, sources, and custom usage/finishReason.
class FakeTextModel extends LanguageModelV4 {
  FakeTextModel(
    this.text, {
    this.finishReason = LanguageModelV4FinishReason.stop,
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
  final LanguageModelV4FinishReason finishReason;
  final String? rawFinishReason;
  final LanguageModelV4Usage? usage;
  final List<String> warnings;
  final String? reasoning;
  final bool redactedReasoning;
  final List<LanguageModelV4SourcePart> sources;
  final ProviderMetadata? providerMetadata;

  @override
  final String provider;

  @override
  final String modelId;

  @override
  String get specificationVersion => 'v4';

  List<LanguageModelV4Warning> get structuredWarnings => warnings
      .map((warning) => LanguageModelV4OtherWarning(message: warning))
      .toList(growable: false);

  /// Last options passed to doGenerate — useful for verifying what was sent.
  LanguageModelV4CallOptions? lastCallOptions;

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    lastCallOptions = options;
    final content = <LanguageModelV4ContentPart>[
      if (reasoning != null) LanguageModelV4ReasoningPart(text: reasoning!),
      if (redactedReasoning)
        LanguageModelV4RedactedReasoningPart(data: Uint8List(0)),
      LanguageModelV4TextPart(text: text),
      ...sources,
    ];
    return LanguageModelV4GenerateResult(
      content: content,
      finishReason: finishReason,
      rawFinishReason: rawFinishReason,
      usage: usage,
      warnings: structuredWarnings,
      providerMetadata: providerMetadata,
    );
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    lastCallOptions = options;
    return LanguageModelV4StreamResult(
      stream: simulateReadableStream(
        parts: [
          StreamPartTextStart(id: 'text-1'),
          StreamPartTextDelta(id: 'text-1', delta: text),
          StreamPartTextEnd(id: 'text-1'),
          StreamPartFinish(
            finishReason: finishReason,
            rawFinishReason: rawFinishReason,
            usage: usage ?? const LanguageModelV4Usage(),
          ),
        ],
      ),
      warnings: structuredWarnings,
    );
  }
}

/// A fake language model backed by a list of stream parts.
///
/// Useful for testing exact event sequences in streamText.
class FakeStreamModel extends LanguageModelV4 {
  FakeStreamModel(
    this.parts, {
    this.provider = 'fake',
    this.modelId = 'fake-stream-model',
  });

  final List<LanguageModelV4StreamPart> parts;

  @override
  final String provider;

  @override
  final String modelId;

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    final textParts = parts.whereType<StreamPartTextDelta>();
    final text = textParts.map((p) => p.delta).join();
    final finish = parts.whereType<StreamPartFinish>().firstOrNull;
    return LanguageModelV4GenerateResult(
      content: [LanguageModelV4TextPart(text: text)],
      finishReason: finish?.finishReason ?? LanguageModelV4FinishReason.stop,
      usage: finish?.usage,
    );
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    return LanguageModelV4StreamResult(
      stream: simulateReadableStream(parts: parts),
    );
  }
}

/// A fake language model that emits a stream error.
class FakeErrorStreamModel extends LanguageModelV4 {
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
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    throw error;
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    return LanguageModelV4StreamResult(
      stream: Stream<LanguageModelV4StreamPart>.fromIterable([
        StreamPartError(error: error),
        StreamPartFinish(finishReason: LanguageModelV4FinishReason.error),
      ]),
    );
  }
}

/// A fake language model that returns a single tool call.
class FakeToolModel extends LanguageModelV4 {
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
  String get specificationVersion => 'v4';

  LanguageModelV4CallOptions? lastCallOptions;

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    lastCallOptions = options;
    return LanguageModelV4GenerateResult(
      content: [
        LanguageModelV4ToolCallPart(
          toolCallId: toolCallId,
          toolName: toolName,
          input: toolInput,
        ),
      ],
      finishReason: LanguageModelV4FinishReason.toolCalls,
      rawFinishReason: 'tool_calls',
    );
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    lastCallOptions = options;
    final argsJson = jsonEncode(toolInput);
    return LanguageModelV4StreamResult(
      stream: simulateReadableStream(
        parts: [
          StreamPartToolInputStart(id: toolCallId, toolName: toolName),
          StreamPartToolInputDelta(id: toolCallId, delta: argsJson),
          StreamPartToolInputEnd(id: toolCallId),
          StreamPartToolCall(
            toolCall: LanguageModelV4ToolCallPart(
              toolCallId: toolCallId,
              toolName: toolName,
              input: toolInput,
            ),
          ),
          StreamPartFinish(
            finishReason: LanguageModelV4FinishReason.toolCalls,
            usage: const LanguageModelV4Usage(),
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
class FakeMultiStepModel extends LanguageModelV4 {
  FakeMultiStepModel(
    this.responses, {
    this.provider = 'fake',
    this.modelId = 'fake-multistep-model',
  });

  final List<LanguageModelV4GenerateResult> responses;
  int _callCount = 0;

  @override
  final String provider;

  @override
  final String modelId;

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    return responses[_callCount++ % responses.length];
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    final result = await doGenerate(options);
    final parts = <LanguageModelV4StreamPart>[];
    for (final part in result.content) {
      if (part is LanguageModelV4TextPart) {
        parts.add(StreamPartTextStart(id: 'text-1'));
        parts.add(StreamPartTextDelta(id: 'text-1', delta: part.text));
        parts.add(StreamPartTextEnd(id: 'text-1'));
      } else if (part is LanguageModelV4ToolCallPart) {
        parts.add(
          StreamPartToolInputStart(
            id: part.toolCallId,
            toolName: part.toolName,
          ),
        );
        parts.add(StreamPartToolInputEnd(id: part.toolCallId));
        parts.add(StreamPartToolCall(toolCall: part));
      }
    }
    parts.add(
      StreamPartFinish(finishReason: result.finishReason, usage: result.usage),
    );
    return LanguageModelV4StreamResult(
      stream: simulateReadableStream(parts: parts),
    );
  }
}

/// A fake language model that always throws on doGenerate/doStream.
class FakeErrorModel extends LanguageModelV4 {
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
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    throw error;
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    throw error;
  }
}

/// A fake language model that captures all call options for inspection.
class FakeCapturingModel extends LanguageModelV4 {
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
  String get specificationVersion => 'v4';

  final List<LanguageModelV4CallOptions> capturedOptions = [];

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    capturedOptions.add(options);
    return LanguageModelV4GenerateResult(
      content: [LanguageModelV4TextPart(text: responseText)],
      finishReason: LanguageModelV4FinishReason.stop,
    );
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    capturedOptions.add(options);
    return LanguageModelV4StreamResult(
      stream: simulateReadableStream(
        parts: [
          StreamPartTextStart(id: 'text-1'),
          StreamPartTextDelta(id: 'text-1', delta: responseText),
          StreamPartTextEnd(id: 'text-1'),
          StreamPartFinish(
            finishReason: LanguageModelV4FinishReason.stop,
            usage: const LanguageModelV4Usage(),
          ),
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
          .map((v) => EmbeddingModelV2Embedding(value: v, embedding: embedding))
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
