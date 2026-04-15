import 'dart:async';
import 'dart:convert';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';

/// Mistral AI provider for language models and embeddings.
///
/// Use [call] to create a language model for a given model ID, and [embedding]
/// for an embedding model.
///
/// Example:
/// ```dart
/// final model = mistral('mistral-large-latest');
/// final embedder = mistral.embedding('mistral-embed');
/// ```
class MistralProvider {
  const MistralProvider({this.apiKey, this.baseUrl});

  /// Mistral API key (defaults to `MISTRAL_API_KEY` env variable).
  final String? apiKey;

  /// Base URL — defaults to `https://api.mistral.ai/v1`.
  final String? baseUrl;

  /// Returns a language model for the given [modelId].
  LanguageModelV3 call(String modelId) => _MistralLanguageModel(
    modelId: modelId,
    apiKey: apiKey,
    baseUrl: baseUrl,
  );

  /// Returns an embedding model for the given [modelId].
  EmbeddingModelV2<String> embedding(String modelId) =>
      _MistralEmbeddingModel(
        modelId: modelId,
        apiKey: apiKey,
        baseUrl: baseUrl,
      );
}

/// Default Mistral provider instance.
const mistral = MistralProvider();

// ---------------------------------------------------------------------------
// HTTP helper
// ---------------------------------------------------------------------------

Dio _mistralDio({String? apiKey, String? baseUrl}) {
  final key = apiKey ?? const String.fromEnvironment('MISTRAL_API_KEY');
  return Dio(
    BaseOptions(
      baseUrl: baseUrl ?? 'https://api.mistral.ai/v1',
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

class _MistralLanguageModel implements LanguageModelV3 {
  const _MistralLanguageModel({
    required this.modelId,
    this.apiKey,
    this.baseUrl,
  });

  @override
  final String modelId;
  final String? apiKey;
  final String? baseUrl;

  @override
  String get provider => 'mistral';

  @override
  String get specificationVersion => 'v3';

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
      if (options.topP != null) 'top_p': options.topP,
      if (options.seed != null) 'random_seed': options.seed,
      if (options.stopSequences.isNotEmpty) 'stop': options.stopSequences,
    };
  }

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async {
    final client = _mistralDio(apiKey: apiKey, baseUrl: baseUrl);
    final body = _buildBody(options);

    final response = await client.post<Map<String, dynamic>>(
      '/chat/completions',
      data: body,
    );
    final data = response.data!;

    final choices = data['choices'] as List?;
    final firstChoice = choices?.isNotEmpty == true
        ? choices![0] as Map<String, dynamic>
        : null;
    final message = firstChoice?['message'] as Map<String, dynamic>?;
    final text = (message?['content'] as String?) ?? '';
    final rawFinishReason = firstChoice?['finish_reason'] as String?;

    final usage = data['usage'] as Map<String, dynamic>?;

    return LanguageModelV3GenerateResult(
      content: [LanguageModelV3TextPart(text: text)],
      finishReason: _mapFinishReason(rawFinishReason),
      rawFinishReason: rawFinishReason,
      usage: LanguageModelV3Usage(
        inputTokens: (usage?['prompt_tokens'] as num?)?.toInt() ?? 0,
        outputTokens: (usage?['completion_tokens'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  @override
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  ) async {
    final client = _mistralDio(apiKey: apiKey, baseUrl: baseUrl);
    final body = _buildBody(options)..['stream'] = true;

    final response = await client.post<ResponseBody>(
      '/chat/completions',
      data: body,
      options: Options(responseType: ResponseType.stream),
    );

    final controller = StreamController<LanguageModelV3StreamPart>();
    unawaited(
      _processStream(response.data!.stream, controller).catchError((Object e) {
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
        if (!trimmed.startsWith('data:')) continue;
        final jsonStr = trimmed.substring(5).trim();
        if (jsonStr == '[DONE]') continue;
        try {
          final event = jsonDecode(jsonStr) as Map<String, dynamic>;
          final choices = event['choices'] as List?;
          if (choices == null || choices.isEmpty) continue;
          final choice = choices[0] as Map<String, dynamic>;
          final delta = choice['delta'] as Map<String, dynamic>?;
          final content = delta?['content'] as String?;
          if (content != null) {
            controller.add(StreamPartTextDelta(id: '0', delta: content));
          }
          final finishReason = choice['finish_reason'] as String?;
          if (finishReason != null) {
            final usage = event['usage'] as Map<String, dynamic>?;
            controller.add(
              StreamPartFinish(
                finishReason: _mapFinishReason(finishReason),
                rawFinishReason: finishReason,
                usage: usage != null
                    ? LanguageModelV3Usage(
                        inputTokens:
                            (usage['prompt_tokens'] as num?)?.toInt() ?? 0,
                        outputTokens:
                            (usage['completion_tokens'] as num?)?.toInt() ?? 0,
                      )
                    : null,
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
      'stop' => LanguageModelV3FinishReason.stop,
      'length' => LanguageModelV3FinishReason.length,
      'tool_calls' => LanguageModelV3FinishReason.toolCalls,
      _ => LanguageModelV3FinishReason.other,
    };
  }
}

// ---------------------------------------------------------------------------
// Embedding model
// ---------------------------------------------------------------------------

class _MistralEmbeddingModel implements EmbeddingModelV2<String> {
  const _MistralEmbeddingModel({
    required this.modelId,
    this.apiKey,
    this.baseUrl,
  });

  @override
  final String modelId;
  final String? apiKey;
  final String? baseUrl;

  @override
  String get provider => 'mistral';

  @override
  String get specificationVersion => 'v2';

  @override
  Future<EmbeddingModelV2GenerateResult<String>> doEmbed(
    EmbeddingModelV2CallOptions<String> options,
  ) async {
    final client = _mistralDio(apiKey: apiKey, baseUrl: baseUrl);

    final body = <String, dynamic>{
      'model': modelId,
      'input': options.values,
    };

    final response = await client.post<Map<String, dynamic>>(
      '/embeddings',
      data: body,
    );
    final data = response.data!;
    final dataList = (data['data'] as List?) ?? [];
    final embeddings = dataList.asMap().entries.map((entry) {
      final item = entry.value as Map<String, dynamic>;
      final vector = (item['embedding'] as List).cast<double>();
      return EmbeddingModelV2Embedding<String>(
        value: options.values[entry.key],
        embedding: vector,
      );
    }).toList();

    return EmbeddingModelV2GenerateResult<String>(embeddings: embeddings);
  }
}
