import 'dart:async';
import 'dart:convert';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';

/// Azure OpenAI provider for language models and embeddings.
///
/// Use [call] to create a language model for a deployment, and [embedding]
/// for an embedding model.
///
/// Example:
/// ```dart
/// final provider = AzureOpenAIProvider(
///   endpoint: 'https://my-resource.openai.azure.com',
///   apiKey: 'my-api-key',
/// );
/// final model = provider('gpt-4-deployment');
/// final result = await model.doGenerate(options);
/// ```
class AzureOpenAIProvider {
  const AzureOpenAIProvider({
    required this.endpoint,
    required this.apiKey,
    this.apiVersion = '2024-02-15-preview',
  });

  /// The Azure OpenAI endpoint URL, e.g.
  /// `https://my-resource.openai.azure.com`.
  final String endpoint;

  /// The Azure OpenAI API key.
  final String apiKey;

  /// The API version to use for all requests.
  final String apiVersion;

  /// Returns a language model for the given Azure deployment [deploymentId].
  LanguageModelV3 call(String deploymentId) => _AzureLanguageModel(
    deploymentId: deploymentId,
    endpoint: endpoint,
    apiKey: apiKey,
    apiVersion: apiVersion,
  );

  /// Returns an embedding model for the given Azure deployment [deploymentId].
  EmbeddingModelV2<String> embedding(String deploymentId) =>
      _AzureEmbeddingModel(
        deploymentId: deploymentId,
        endpoint: endpoint,
        apiKey: apiKey,
        apiVersion: apiVersion,
      );
}

/// Default Azure OpenAI provider instance (endpoint and apiKey must be set
/// before use).
const azureOpenAI = AzureOpenAIProvider(endpoint: '', apiKey: '');

// ---------------------------------------------------------------------------
// HTTP helper
// ---------------------------------------------------------------------------

Dio _azureDio({
  required String endpoint,
  required String deploymentId,
  required String apiKey,
}) {
  return Dio(
    BaseOptions(
      baseUrl: '$endpoint/openai/deployments/$deploymentId',
      headers: {
        'api-key': apiKey,
        'Content-Type': 'application/json',
      },
    ),
  );
}

// ---------------------------------------------------------------------------
// Language model
// ---------------------------------------------------------------------------

class _AzureLanguageModel implements LanguageModelV3 {
  const _AzureLanguageModel({
    required this.deploymentId,
    required this.endpoint,
    required this.apiKey,
    required this.apiVersion,
  });

  final String deploymentId;
  final String endpoint;
  final String apiKey;
  final String apiVersion;

  @override
  String get modelId => deploymentId;

  @override
  String get provider => 'azure';

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
      'model': deploymentId,
      'messages': _buildMessages(options.prompt),
      if (options.maxOutputTokens != null)
        'max_tokens': options.maxOutputTokens,
      if (options.temperature != null) 'temperature': options.temperature,
      if (options.topP != null) 'top_p': options.topP,
      if (options.seed != null) 'seed': options.seed,
      if (options.stopSequences.isNotEmpty) 'stop': options.stopSequences,
    };
  }

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async {
    final client = _azureDio(
      endpoint: endpoint,
      deploymentId: deploymentId,
      apiKey: apiKey,
    );
    final body = _buildBody(options);

    final response = await client.post<Map<String, dynamic>>(
      '/chat/completions',
      queryParameters: {'api-version': apiVersion},
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
    final client = _azureDio(
      endpoint: endpoint,
      deploymentId: deploymentId,
      apiKey: apiKey,
    );
    final body = _buildBody(options)..['stream'] = true;

    final response = await client.post<ResponseBody>(
      '/chat/completions',
      queryParameters: {'api-version': apiVersion},
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

class _AzureEmbeddingModel implements EmbeddingModelV2<String> {
  const _AzureEmbeddingModel({
    required this.deploymentId,
    required this.endpoint,
    required this.apiKey,
    required this.apiVersion,
  });

  final String deploymentId;
  final String endpoint;
  final String apiKey;
  final String apiVersion;

  @override
  String get modelId => deploymentId;

  @override
  String get provider => 'azure';

  @override
  String get specificationVersion => 'v2';

  @override
  Future<EmbeddingModelV2GenerateResult<String>> doEmbed(
    EmbeddingModelV2CallOptions<String> options,
  ) async {
    final client = _azureDio(
      endpoint: endpoint,
      deploymentId: deploymentId,
      apiKey: apiKey,
    );

    final body = <String, dynamic>{
      'input': options.values,
      'model': deploymentId,
    };

    final response = await client.post<Map<String, dynamic>>(
      '/embeddings',
      queryParameters: {'api-version': apiVersion},
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
