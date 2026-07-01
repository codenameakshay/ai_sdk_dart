import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_sdk_openai_compatible/ai_sdk_openai_compatible.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';

/// OpenAI provider for language models, embeddings, images, speech, and transcription.
///
/// Use [call] for language models, [embedding] for embeddings, [image] for image
/// generation, [speech] for text-to-speech, [transcription] for speech-to-text.
///
/// Example:
/// ```dart
/// final model = openai('gpt-4o');
/// final result = await generateText(model: model, prompt: 'Hello');
/// ```
class OpenAIProvider {
  const OpenAIProvider({this.apiKey, this.baseUrl});

  /// API key (defaults to `OPENAI_API_KEY` environment variable).
  final String? apiKey;

  /// Base URL (defaults to `https://api.openai.com/v1`).
  final String? baseUrl;

  /// Returns a language model for the given [modelId].
  ///
  /// Built on the shared `ai_sdk_openai_compatible` base; OpenAI-specific
  /// `reasoning_effort` / `reasoning_summary` and pass-through provider options
  /// are injected via the config's `extraBody` hook.
  LanguageModelV3 call(String modelId) => OpenAICompatibleChatLanguageModel(
    modelId: modelId,
    config: OpenAICompatibleConfig(
      provider: 'openai',
      baseUrl: baseUrl ?? 'https://api.openai.com/v1',
      headers: () {
        final key = apiKey ?? const String.fromEnvironment('OPENAI_API_KEY');
        return {if (key.isNotEmpty) 'Authorization': 'Bearer $key'};
      },
      extraBody: _openAiExtraBody,
    ),
  );

  /// Returns an embedding model for the given [modelId].
  EmbeddingModelV2<String> embedding(String modelId) =>
      _OpenAIEmbeddingModel(modelId: modelId, apiKey: apiKey, baseUrl: baseUrl);

  /// Returns an image generation model for the given [modelId].
  ImageModelV3 image(String modelId) =>
      _OpenAIImageModel(modelId: modelId, apiKey: apiKey, baseUrl: baseUrl);

  /// Returns a speech (text-to-speech) model for the given [modelId].
  SpeechModelV1 speech(String modelId) =>
      _OpenAISpeechModel(modelId: modelId, apiKey: apiKey, baseUrl: baseUrl);

  /// Returns a transcription (speech-to-text) model for the given [modelId].
  TranscriptionModelV1 transcription(String modelId) =>
      _OpenAITranscriptionModel(
        modelId: modelId,
        apiKey: apiKey,
        baseUrl: baseUrl,
      );
}

/// Default OpenAI provider instance — call it with a model id, e.g.
/// `openai('gpt-4.1-mini')`. Reads the API key from the `OPENAI_API_KEY`
/// environment variable unless an [OpenAIProvider] is constructed explicitly.
const openai = OpenAIProvider();

/// Builds the OpenAI-specific request-body additions for the shared base's
/// `extraBody` hook: reasoning_effort / reasoning_summary (accepting both
/// camelCase and snake_case keys) plus any other pass-through provider options.
Map<String, dynamic>? _openAiExtraBody(LanguageModelV3CallOptions options) {
  final po = options.providerOptions?['openai'];
  final (reasoningEffort, reasoningSummary, cleanedPo) =
      _extractReasoningOptions(po);
  final out = <String, dynamic>{
    if (reasoningEffort != null) 'reasoning_effort': reasoningEffort,
    if (reasoningSummary != null) 'reasoning_summary': reasoningSummary,
    ...?cleanedPo,
  };
  return out.isEmpty ? null : out;
}

class _OpenAIEmbeddingModel implements EmbeddingModelV2<String> {
  const _OpenAIEmbeddingModel({
    required this.modelId,
    this.apiKey,
    this.baseUrl,
  });

  @override
  final String modelId;

  final String? apiKey;
  final String? baseUrl;

  @override
  String get provider => 'openai';

  @override
  String get specificationVersion => 'v2';

  @override
  Future<EmbeddingModelV2GenerateResult<String>> doEmbed(
    EmbeddingModelV2CallOptions<String> options,
  ) async {
    final client = _openAiDio(apiKey: apiKey, baseUrl: baseUrl);
    final providerOptions = options.providerOptions != null
        ? options.providerOptions![provider]
        : null;
    final Response<Map<String, dynamic>> response;
    try {
      response = await client.post<Map<String, dynamic>>(
        '/embeddings',
        data: {'model': modelId, 'input': options.values, ...?providerOptions},
        options: Options(headers: options.headers),
      );
    } on DioException catch (e) {
      throw await apiErrorFromDioException(e, provider: provider);
    }

    final data = response.data ?? <String, dynamic>{};
    final rawEmbeddings = (data['data'] as List?) ?? const [];

    final embeddings = <EmbeddingModelV2Embedding<String>>[];
    for (
      var i = 0;
      i < rawEmbeddings.length && i < options.values.length;
      i++
    ) {
      final row = (rawEmbeddings[i] as Map).cast<String, dynamic>();
      final vector = ((row['embedding'] as List?) ?? const [])
          .map((v) => (v as num).toDouble())
          .toList();
      embeddings.add(
        EmbeddingModelV2Embedding<String>(
          value: options.values[i],
          embedding: vector,
        ),
      );
    }

    final usage = (data['usage'] as Map?)?.cast<String, dynamic>();
    return EmbeddingModelV2GenerateResult<String>(
      embeddings: embeddings,
      usage: EmbeddingModelV2Usage(tokens: _intOrNull(usage?['total_tokens'])),
    );
  }
}

class _OpenAIImageModel implements ImageModelV3 {
  const _OpenAIImageModel({required this.modelId, this.apiKey, this.baseUrl});

  @override
  final String modelId;

  final String? apiKey;
  final String? baseUrl;

  @override
  String get provider => 'openai';

  @override
  String get specificationVersion => 'v3';

  @override
  Future<ImageModelV3GenerateResult> doGenerate(
    ImageModelV3CallOptions options,
  ) async {
    final client = _openAiDio(apiKey: apiKey, baseUrl: baseUrl);
    final providerOptions = options.providerOptions != null
        ? options.providerOptions![provider]
        : null;
    final Response<Map<String, dynamic>> response;
    try {
      response = await client.post<Map<String, dynamic>>(
        '/images/generations',
        data: {
          'model': modelId,
          'prompt': options.prompt ?? options.promptObject?.text ?? '',
          if (options.n != null) 'n': options.n,
          if (options.size != null) 'size': options.size,
          // gpt-image-1 always returns base64 and rejects `response_format`;
          // dall-e-2/3 need it to return bytes (b64) instead of a hosted URL.
          if (!modelId.startsWith('gpt-image')) 'response_format': 'b64_json',
          ...?providerOptions,
        },
        options: Options(headers: options.headers),
      );
    } on DioException catch (e) {
      throw await apiErrorFromDioException(e, provider: provider);
    }

    final data = response.data ?? <String, dynamic>{};
    final imagesData = (data['data'] as List?) ?? const [];
    final images = <GeneratedImage>[];
    for (final item in imagesData) {
      final map = (item as Map).cast<String, dynamic>();
      final b64 = map['b64_json']?.toString();
      if (b64 == null || b64.isEmpty) continue;
      images.add(
        GeneratedImage(
          bytes: Uint8List.fromList(base64Decode(b64)),
          mediaType: 'image/png',
        ),
      );
    }

    return ImageModelV3GenerateResult(
      images: images,
      usage: ImageModelV3Usage(imagesGenerated: images.length),
      responses: [
        ImageModelV3ResponseMetadata(
          timestamp: DateTime.now().toUtc(),
          modelId: modelId,
        ),
      ],
    );
  }
}

Dio _openAiDio({String? apiKey, String? baseUrl}) {
  final resolvedApiKey =
      apiKey ?? const String.fromEnvironment('OPENAI_API_KEY');
  final client = Dio(
    BaseOptions(
      baseUrl: baseUrl ?? 'https://api.openai.com/v1',
      headers: {
        if (resolvedApiKey.isNotEmpty)
          'Authorization': 'Bearer $resolvedApiKey',
        'Content-Type': 'application/json',
      },
      responseType: ResponseType.json,
    ),
  );
  return client;
}

int? _intOrNull(Object? value) => switch (value) {
  int v => v,
  num v => v.toInt(),
  String v => int.tryParse(v),
  _ => null,
};

class _OpenAISpeechModel implements SpeechModelV1 {
  const _OpenAISpeechModel({required this.modelId, this.apiKey, this.baseUrl});

  @override
  final String modelId;
  final String? apiKey;
  final String? baseUrl;

  @override
  String get provider => 'openai';

  @override
  String get specificationVersion => 'v1';

  @override
  Future<SpeechModelV1GenerateResult> doGenerate(
    SpeechModelV1CallOptions options,
  ) async {
    final client = _openAiDio(apiKey: apiKey, baseUrl: baseUrl);
    final providerOptions = options.providerOptions?['openai'];
    final requestBody = {
      'model': modelId,
      'input': options.text,
      if (options.voice != null) 'voice': options.voice,
      if (options.format != null) 'response_format': options.format,
      if (options.speed != null) 'speed': options.speed,
      ...?providerOptions,
    };
    final Response<Uint8List> response;
    try {
      response = await client.post<Uint8List>(
        '/audio/speech',
        data: requestBody,
        options: Options(
          responseType: ResponseType.bytes,
          headers: options.headers,
        ),
      );
    } on DioException catch (e) {
      throw await apiErrorFromDioException(e, provider: provider);
    }
    final contentType = response.headers.value('content-type') ?? 'audio/mpeg';
    final mediaType = contentType.split(';').first.trim();
    return SpeechModelV1GenerateResult(
      audio: response.data ?? Uint8List(0),
      mediaType: mediaType,
    );
  }
}

class _OpenAITranscriptionModel implements TranscriptionModelV1 {
  const _OpenAITranscriptionModel({
    required this.modelId,
    this.apiKey,
    this.baseUrl,
  });

  @override
  final String modelId;
  final String? apiKey;
  final String? baseUrl;

  @override
  String get provider => 'openai';

  @override
  String get specificationVersion => 'v1';

  @override
  Future<TranscriptionModelV1GenerateResult> doGenerate(
    TranscriptionModelV1CallOptions options,
  ) async {
    final client = _openAiDio(apiKey: apiKey, baseUrl: baseUrl);
    final formData = FormData.fromMap({
      'model': modelId,
      'file': MultipartFile.fromBytes(
        options.audio,
        filename: 'audio.${_audioExtension(options.audioMediaType)}',
        contentType: DioMediaType.parse(options.audioMediaType ?? 'audio/mpeg'),
      ),
      'response_format': 'json',
      if (options.language != null) 'language': options.language,
      if (options.prompt != null) 'prompt': options.prompt,
    });
    final Response<Map<String, dynamic>> response;
    try {
      response = await client.post<Map<String, dynamic>>(
        '/audio/transcriptions',
        data: formData,
        options: Options(headers: options.headers),
      );
    } on DioException catch (e) {
      throw await apiErrorFromDioException(e, provider: provider);
    }
    final data = response.data ?? <String, dynamic>{};
    return TranscriptionModelV1GenerateResult(
      text: data['text']?.toString() ?? '',
    );
  }

  String _audioExtension(String? mediaType) {
    return switch (mediaType) {
      'audio/mpeg' || 'audio/mp3' => 'mp3',
      'audio/wav' => 'wav',
      'audio/ogg' => 'ogg',
      'audio/flac' => 'flac',
      'audio/mp4' || 'audio/m4a' => 'm4a',
      'audio/webm' => 'webm',
      _ => 'mp3',
    };
  }
}

(String?, String?, Map<String, dynamic>?) _extractReasoningOptions(
  Map<String, dynamic>? po,
) {
  if (po == null) return (null, null, null);

  final reasoningEffort =
      po['reasoning_effort'] as String? ?? po['reasoningEffort'] as String?;
  final reasoningSummary =
      po['reasoning_summary'] as String? ?? po['reasoningSummary'] as String?;

  final cleaned = Map<String, dynamic>.from(po)
    ..remove('reasoning_effort')
    ..remove('reasoningEffort')
    ..remove('reasoning_summary')
    ..remove('reasoningSummary');

  return (reasoningEffort, reasoningSummary, cleaned.isEmpty ? null : cleaned);
}
