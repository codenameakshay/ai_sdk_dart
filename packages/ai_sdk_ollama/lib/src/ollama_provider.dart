import 'dart:async';
import 'dart:convert';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';

/// Ollama provider for local language models and embeddings.
///
/// Use [call] to create a language model, and [embedding] for an embedding
/// model. Requires a running Ollama instance (default: http://localhost:11434).
///
/// Example:
/// ```dart
/// final model = ollama('llama3');
/// final embedder = ollama.embedding('nomic-embed-text');
/// ```
class OllamaProvider {
  const OllamaProvider({this.baseUrl});

  /// Base URL — defaults to `http://localhost:11434/api`.
  final String? baseUrl;

  /// Returns a language model for the given [model].
  LanguageModelV3 call(String model) => _OllamaLanguageModel(
    model: model,
    baseUrl: baseUrl,
  );

  /// Returns an embedding model for the given [model].
  EmbeddingModelV2<String> embedding(String model) => _OllamaEmbeddingModel(
    model: model,
    baseUrl: baseUrl,
  );
}

/// Default Ollama provider instance (connects to http://localhost:11434).
const ollama = OllamaProvider();

// ---------------------------------------------------------------------------
// HTTP helper
// ---------------------------------------------------------------------------

Dio _ollamaDio({String? baseUrl}) {
  return Dio(
    BaseOptions(
      baseUrl: baseUrl ?? 'http://localhost:11434/api',
      headers: {'Content-Type': 'application/json'},
    ),
  );
}

// ---------------------------------------------------------------------------
// Language model
// ---------------------------------------------------------------------------

class _OllamaLanguageModel implements LanguageModelV3 {
  const _OllamaLanguageModel({required this.model, this.baseUrl});

  final String model;
  final String? baseUrl;

  @override
  String get modelId => model;

  @override
  String get provider => 'ollama';

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
    final ollamaOptions = <String, dynamic>{
      if (options.maxOutputTokens != null)
        'num_predict': options.maxOutputTokens,
      if (options.temperature != null) 'temperature': options.temperature,
      if (options.topP != null) 'top_p': options.topP,
      if (options.topK != null) 'top_k': options.topK,
      if (options.seed != null) 'seed': options.seed,
      if (options.stopSequences.isNotEmpty) 'stop': options.stopSequences,
    };

    return <String, dynamic>{
      'model': model,
      'messages': _buildMessages(options.prompt),
      if (ollamaOptions.isNotEmpty) 'options': ollamaOptions,
      'stream': false,
    };
  }

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async {
    final client = _ollamaDio(baseUrl: baseUrl);
    final body = _buildBody(options);

    final response = await client.post<Map<String, dynamic>>(
      '/chat',
      data: body,
    );
    final data = response.data!;

    final message = data['message'] as Map<String, dynamic>?;
    final text = (message?['content'] as String?) ?? '';
    final rawFinishReason = data['done_reason'] as String?;

    return LanguageModelV3GenerateResult(
      content: [LanguageModelV3TextPart(text: text)],
      finishReason: _mapFinishReason(rawFinishReason),
      rawFinishReason: rawFinishReason,
      usage: const LanguageModelV3Usage(inputTokens: 0, outputTokens: 0),
    );
  }

  @override
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  ) async {
    final client = _ollamaDio(baseUrl: baseUrl);
    // Override stream to true for streaming mode.
    final body = _buildBody(options);
    body['stream'] = true;

    final response = await client.post<ResponseBody>(
      '/chat',
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
        try {
          final event = jsonDecode(trimmed) as Map<String, dynamic>;
          final message = event['message'] as Map<String, dynamic>?;
          final content = message?['content'] as String?;
          if (content != null && content.isNotEmpty) {
            controller.add(StreamPartTextDelta(id: '0', delta: content));
          }
          final done = event['done'] as bool? ?? false;
          if (done) {
            final doneReason = event['done_reason'] as String?;
            controller.add(
              StreamPartFinish(
                finishReason: _mapFinishReason(doneReason),
                rawFinishReason: doneReason,
                usage: const LanguageModelV3Usage(
                  inputTokens: 0,
                  outputTokens: 0,
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
      'stop' => LanguageModelV3FinishReason.stop,
      'length' => LanguageModelV3FinishReason.length,
      _ => LanguageModelV3FinishReason.other,
    };
  }
}

// ---------------------------------------------------------------------------
// Embedding model
// ---------------------------------------------------------------------------

class _OllamaEmbeddingModel implements EmbeddingModelV2<String> {
  const _OllamaEmbeddingModel({required this.model, this.baseUrl});

  final String model;
  final String? baseUrl;

  @override
  String get modelId => model;

  @override
  String get provider => 'ollama';

  @override
  String get specificationVersion => 'v2';

  @override
  Future<EmbeddingModelV2GenerateResult<String>> doEmbed(
    EmbeddingModelV2CallOptions<String> options,
  ) async {
    final client = _ollamaDio(baseUrl: baseUrl);

    final body = <String, dynamic>{
      'model': model,
      'input': options.values,
    };

    final response = await client.post<Map<String, dynamic>>(
      '/embed',
      data: body,
    );
    final data = response.data!;
    final embeddingsList = (data['embeddings'] as List?) ?? [];
    final embeddings = embeddingsList.asMap().entries.map((entry) {
      final vector = (entry.value as List).cast<double>();
      return EmbeddingModelV2Embedding<String>(
        value: options.values[entry.key],
        embedding: vector,
      );
    }).toList();

    return EmbeddingModelV2GenerateResult<String>(embeddings: embeddings);
  }
}
