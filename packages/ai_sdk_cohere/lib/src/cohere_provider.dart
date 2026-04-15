import 'dart:async';
import 'dart:convert';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';

/// Cohere provider for language models, embeddings, and reranking.
///
/// Use [call] for language model generation, [embedding] for text embeddings,
/// and [rerank] for document reranking.
///
/// Example:
/// ```dart
/// // Language model
/// final model = cohere('command-r-plus');
/// final result = await generateText(model: model, prompt: 'Hello');
///
/// // Reranking
/// final ranker = cohere.rerank('rerank-english-v3.0');
/// final ranked = await rerank(
///   model: ranker,
///   query: 'What is AI?',
///   documents: ['AI is...', 'Machines are...'],
/// );
/// ```
class CohereProvider {
  const CohereProvider({this.apiKey, this.baseUrl});

  /// Cohere API key (defaults to `COHERE_API_KEY` env variable).
  final String? apiKey;

  /// Base URL — defaults to `https://api.cohere.com/v2`.
  final String? baseUrl;

  /// Returns a language model for the given [modelId].
  LanguageModelV3 call(String modelId) =>
      _CohereLanguageModel(modelId: modelId, apiKey: apiKey, baseUrl: baseUrl);

  /// Returns an embedding model for the given [modelId].
  EmbeddingModelV2<String> embedding(String modelId) =>
      _CohereEmbeddingModel(modelId: modelId, apiKey: apiKey, baseUrl: baseUrl);

  /// Returns a reranking model for the given [modelId].
  RerankModelV1 rerank(String modelId) =>
      _CohereRerankModel(modelId: modelId, apiKey: apiKey, baseUrl: baseUrl);
}

/// Default Cohere provider instance.
const cohere = CohereProvider();

// ---------------------------------------------------------------------------
// HTTP helper
// ---------------------------------------------------------------------------

Dio _cohereDio({String? apiKey, String? baseUrl}) {
  final key = apiKey ?? const String.fromEnvironment('COHERE_API_KEY');
  return Dio(
    BaseOptions(
      baseUrl: baseUrl ?? 'https://api.cohere.com/v2',
      headers: {
        'Authorization': 'Bearer $key',
        'Content-Type': 'application/json',
      },
    ),
  );
}

// ---------------------------------------------------------------------------
// Language model
// ---------------------------------------------------------------------------

class _CohereLanguageModel implements LanguageModelV3 {
  const _CohereLanguageModel({
    required this.modelId,
    this.apiKey,
    this.baseUrl,
  });

  @override
  final String modelId;
  final String? apiKey;
  final String? baseUrl;

  @override
  String get provider => 'cohere';

  @override
  String get specificationVersion => 'v3';

  /// Build Cohere v2 messages from a [LanguageModelV3Prompt].
  List<Map<String, dynamic>> _buildMessages(LanguageModelV3Prompt prompt) {
    final messages = <Map<String, dynamic>>[];
    if (prompt.system != null) {
      messages.add({'role': 'system', 'content': prompt.system!});
    }
    for (final msg in prompt.messages) {
      final textContent = msg.content
          .whereType<LanguageModelV3TextPart>()
          .map((p) => p.text)
          .join('\n');
      final role = switch (msg.role) {
        LanguageModelV3Role.user => 'user',
        LanguageModelV3Role.assistant => 'assistant',
        LanguageModelV3Role.tool => 'tool',
        LanguageModelV3Role.system => 'system',
      };
      messages.add({'role': role, 'content': textContent});
    }
    return messages;
  }

  Map<String, dynamic> _buildBody(LanguageModelV3CallOptions options) {
    return <String, dynamic>{
      'model': modelId,
      'messages': _buildMessages(options.prompt),
      if (options.maxOutputTokens != null)
        'max_tokens': options.maxOutputTokens,
      if (options.temperature != null) 'temperature': options.temperature,
      if (options.topP != null) 'p': options.topP,
      if (options.topK != null) 'k': options.topK,
      if (options.stopSequences.isNotEmpty)
        'stop_sequences': options.stopSequences,
      if (options.seed != null) 'seed': options.seed,
    };
  }

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async {
    final client = _cohereDio(apiKey: apiKey, baseUrl: baseUrl);
    final body = _buildBody(options);

    final response = await client.post<Map<String, dynamic>>(
      '/chat',
      data: body,
    );
    final data = response.data!;

    final message = data['message'] as Map<String, dynamic>?;
    final contentList = message?['content'] as List?;
    final text = contentList
            ?.whereType<Map<String, dynamic>>()
            .where((c) => c['type'] == 'text')
            .map((c) => c['text'] as String)
            .join() ??
        '';

    final usage = data['usage'] as Map<String, dynamic>?;
    final tokens = usage?['tokens'] as Map<String, dynamic>?;

    return LanguageModelV3GenerateResult(
      content: [LanguageModelV3TextPart(text: text)],
      finishReason: _mapFinishReason(data['finish_reason'] as String?),
      rawFinishReason: data['finish_reason'] as String?,
      usage: LanguageModelV3Usage(
        inputTokens: (tokens?['input_tokens'] as num?)?.toInt() ?? 0,
        outputTokens: (tokens?['output_tokens'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  @override
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  ) async {
    final client = _cohereDio(apiKey: apiKey, baseUrl: baseUrl);
    final body = _buildBody(options)..['stream'] = true;

    final response = await client.post<ResponseBody>(
      '/chat',
      data: body,
      options: Options(responseType: ResponseType.stream),
    );

    final controller = StreamController<LanguageModelV3StreamPart>();
    final byteStream = response.data!.stream;

    unawaited(
      _processStream(byteStream, controller).catchError((Object e) {
        if (!controller.isClosed) {
          controller.add(StreamPartError(error: e));
          controller.close();
        }
      }),
    );

    return LanguageModelV3StreamResult(stream: controller.stream);
  }

  Future<void> _processStream(
    Stream<List<int>> byteStream,
    StreamController<LanguageModelV3StreamPart> controller,
  ) async {
    var buffer = '';
    await for (final bytes in byteStream) {
      buffer += utf8.decode(bytes);
      final lines = buffer.split('\n');
      buffer = lines.removeLast();
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        try {
          final event = jsonDecode(trimmed) as Map<String, dynamic>;
          final type = event['type'] as String?;
          if (type == 'content-delta') {
            final delta = event['delta'] as Map<String, dynamic>?;
            final message = delta?['message'] as Map<String, dynamic>?;
            final content = message?['content'] as Map<String, dynamic>?;
            final text = content?['text'] as String?;
            if (text != null) {
              controller.add(StreamPartTextDelta(id: '0', delta: text));
            }
          } else if (type == 'message-end') {
            final delta = event['delta'] as Map<String, dynamic>?;
            final usage = delta?['usage'] as Map<String, dynamic>?;
            final tokens = usage?['tokens'] as Map<String, dynamic>?;
            controller.add(
              StreamPartFinish(
                finishReason: _mapFinishReason(
                  delta?['finish_reason'] as String?,
                ),
                rawFinishReason: delta?['finish_reason'] as String?,
                usage: LanguageModelV3Usage(
                  inputTokens:
                      (tokens?['input_tokens'] as num?)?.toInt() ?? 0,
                  outputTokens:
                      (tokens?['output_tokens'] as num?)?.toInt() ?? 0,
                ),
              ),
            );
          }
        } catch (_) {
          // Ignore malformed JSON lines.
        }
      }
    }
    await controller.close();
  }

  LanguageModelV3FinishReason _mapFinishReason(String? reason) {
    return switch (reason) {
      'COMPLETE' || 'complete' => LanguageModelV3FinishReason.stop,
      'MAX_TOKENS' || 'max_tokens' => LanguageModelV3FinishReason.length,
      'STOP_SEQUENCE' || 'stop_sequence' => LanguageModelV3FinishReason.stop,
      'TOOL_CALL' || 'tool_call' => LanguageModelV3FinishReason.toolCalls,
      _ => LanguageModelV3FinishReason.other,
    };
  }
}

// ---------------------------------------------------------------------------
// Embedding model
// ---------------------------------------------------------------------------

class _CohereEmbeddingModel implements EmbeddingModelV2<String> {
  const _CohereEmbeddingModel({
    required this.modelId,
    this.apiKey,
    this.baseUrl,
  });

  @override
  final String modelId;
  final String? apiKey;
  final String? baseUrl;

  @override
  String get provider => 'cohere';

  @override
  String get specificationVersion => 'v2';

  @override
  Future<EmbeddingModelV2GenerateResult<String>> doEmbed(
    EmbeddingModelV2CallOptions<String> options,
  ) async {
    final client = _cohereDio(apiKey: apiKey, baseUrl: baseUrl);

    final body = <String, dynamic>{
      'model': modelId,
      'texts': options.values,
      'input_type': 'search_document',
      'embedding_types': ['float'],
    };

    final response = await client.post<Map<String, dynamic>>(
      '/embed',
      data: body,
    );
    final data = response.data!;
    final embeddingsData = data['embeddings'] as Map<String, dynamic>?;
    final floats = (embeddingsData?['float'] as List?) ?? [];
    final embeddings = floats.asMap().entries.map((entry) {
      final vector = (entry.value as List).cast<double>();
      return EmbeddingModelV2Embedding<String>(
        value: options.values[entry.key],
        embedding: vector,
      );
    }).toList();

    return EmbeddingModelV2GenerateResult<String>(embeddings: embeddings);
  }
}

// ---------------------------------------------------------------------------
// Rerank model
// ---------------------------------------------------------------------------

class _CohereRerankModel implements RerankModelV1 {
  const _CohereRerankModel({
    required this.modelId,
    this.apiKey,
    this.baseUrl,
  });

  @override
  final String modelId;
  final String? apiKey;
  final String? baseUrl;

  @override
  String get provider => 'cohere';

  @override
  String get specificationVersion => 'v1';

  @override
  Future<RerankModelV1Result> doRerank(RerankModelV1CallOptions options) async {
    final client = _cohereDio(apiKey: apiKey, baseUrl: baseUrl);

    final body = <String, dynamic>{
      'model': modelId,
      'query': options.query,
      'documents': options.documents,
      if (options.topN != null) 'top_n': options.topN,
    };

    final response = await client.post<Map<String, dynamic>>(
      '/rerank',
      data: body,
    );
    final data = response.data!;
    final results = (data['results'] as List?) ?? [];

    final documents =
        results.map((r) {
          final map = r as Map<String, dynamic>;
          final idx = (map['index'] as num).toInt();
          return RerankDocument(
            index: idx,
            document: options.documents[idx],
            relevanceScore: (map['relevance_score'] as num).toDouble(),
          );
        }).toList();

    return RerankModelV1Result(documents: documents);
  }
}
