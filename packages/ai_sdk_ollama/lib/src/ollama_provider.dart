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
  LanguageModelV3 call(String model) =>
      _OllamaLanguageModel(model: model, baseUrl: baseUrl);

  /// Returns an embedding model for the given [model].
  EmbeddingModelV2<String> embedding(String model) =>
      _OllamaEmbeddingModel(model: model, baseUrl: baseUrl);
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

  /// Build Ollama `/api/chat` messages from a [LanguageModelV3Prompt].
  ///
  /// Image parts are attached to the message via the Ollama `images` field
  /// (base64 strings, no `data:` prefix). Assistant tool calls and `tool`
  /// result messages are preserved rather than dropped.
  List<Map<String, dynamic>> _buildMessages(LanguageModelV3Prompt prompt) {
    final messages = <Map<String, dynamic>>[];
    if (prompt.system != null) {
      messages.add({'role': 'system', 'content': prompt.system!});
    }
    for (final msg in prompt.messages) {
      final role = switch (msg.role) {
        LanguageModelV3Role.user => 'user',
        LanguageModelV3Role.assistant => 'assistant',
        LanguageModelV3Role.tool => 'tool',
        LanguageModelV3Role.system => 'system',
      };

      // Tool result messages: one Ollama `tool` message per result part.
      if (role == 'tool') {
        final toolResults = msg.content
            .whereType<LanguageModelV3ToolResultPart>();
        var emitted = false;
        for (final result in toolResults) {
          messages.add({
            'role': 'tool',
            'tool_name': result.toolName,
            'content': _toolResultText(result),
          });
          emitted = true;
        }
        if (emitted) continue;
      }

      final textContent = msg.content
          .whereType<LanguageModelV3TextPart>()
          .map((p) => p.text)
          .join('\n');

      // Assistant messages may carry tool calls.
      if (role == 'assistant') {
        final toolCalls = msg.content
            .whereType<LanguageModelV3ToolCallPart>()
            .map(
              (call) => {
                'function': {'name': call.toolName, 'arguments': call.input},
              },
            )
            .toList();
        if (toolCalls.isNotEmpty) {
          messages.add({
            'role': 'assistant',
            'content': textContent,
            'tool_calls': toolCalls,
          });
          continue;
        }
      }

      // Collect base64 image data for the Ollama `images` field.
      final images = <String>[];
      for (final part in msg.content) {
        if (part is LanguageModelV3ImagePart) {
          final b64 = _imageBase64(part.image);
          if (b64 != null) images.add(b64);
        } else if (part is LanguageModelV3FilePart &&
            part.mediaType.startsWith('image/')) {
          final b64 = _imageBase64(part.data);
          if (b64 != null) images.add(b64);
        }
      }

      messages.add({
        'role': role,
        'content': textContent,
        if (images.isNotEmpty) 'images': images,
      });
    }
    return messages;
  }

  String _toolResultText(LanguageModelV3ToolResultPart result) {
    final output = result.output;
    if (output is ToolResultOutputText) return output.text;
    if (output is ToolResultOutputContent) {
      return output.parts
          .whereType<LanguageModelV3TextPart>()
          .map((p) => p.text)
          .join('\n');
    }
    return '';
  }

  /// Serialize function tools into Ollama's OpenAI-style `tools` field.
  List<Map<String, dynamic>> _buildTools(
    List<LanguageModelV3FunctionTool> tools,
  ) {
    return tools
        .map(
          (tool) => {
            'type': 'function',
            'function': {
              'name': tool.name,
              if (tool.description != null) 'description': tool.description,
              'parameters': tool.inputSchema,
            },
          },
        )
        .toList();
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
      if (options.tools.isNotEmpty) 'tools': _buildTools(options.tools),
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

    final Response<Map<String, dynamic>> response;
    try {
      response = await client.post<Map<String, dynamic>>('/chat', data: body);
    } on DioException catch (e) {
      throw await _apiCallError(e, provider);
    }
    final data = response.data!;

    final message = data['message'] as Map<String, dynamic>?;
    final text = (message?['content'] as String?) ?? '';
    final rawFinishReason = data['done_reason'] as String?;

    final content = <LanguageModelV3ContentPart>[];
    if (text.isNotEmpty) {
      content.add(LanguageModelV3TextPart(text: text));
    }
    content.addAll(_parseToolCalls(message?['tool_calls'] as List?));

    return LanguageModelV3GenerateResult(
      content: content,
      finishReason: content.any((p) => p is LanguageModelV3ToolCallPart)
          ? LanguageModelV3FinishReason.toolCalls
          : _mapFinishReason(rawFinishReason),
      rawFinishReason: rawFinishReason,
      usage: _usageFrom(data),
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

    final Response<ResponseBody> response;
    try {
      response = await client.post<ResponseBody>(
        '/chat',
        data: body,
        options: Options(responseType: ResponseType.stream),
      );
    } on DioException catch (e) {
      throw await _apiCallError(e, provider);
    }

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

          // Ollama emits whole tool calls (not incremental deltas).
          final toolCalls = _parseToolCalls(message?['tool_calls'] as List?);
          var sawToolCall = false;
          for (final call in toolCalls) {
            sawToolCall = true;
            controller.add(
              StreamPartToolCallStart(
                toolCallId: call.toolCallId,
                toolName: call.toolName,
              ),
            );
            controller.add(
              StreamPartToolCallEnd(
                toolCallId: call.toolCallId,
                toolName: call.toolName,
                input: call.input,
              ),
            );
          }

          final done = event['done'] as bool? ?? false;
          if (done) {
            final doneReason = event['done_reason'] as String?;
            controller.add(
              StreamPartFinish(
                finishReason: sawToolCall
                    ? LanguageModelV3FinishReason.toolCalls
                    : _mapFinishReason(doneReason),
                rawFinishReason: doneReason,
                usage: _usageFrom(event),
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

  /// Parse `message.tool_calls` from an Ollama response into tool-call parts.
  List<LanguageModelV3ToolCallPart> _parseToolCalls(List? toolCalls) {
    if (toolCalls == null) return const [];
    final out = <LanguageModelV3ToolCallPart>[];
    for (final raw in toolCalls.whereType<Map<String, dynamic>>()) {
      final function = raw['function'] as Map<String, dynamic>?;
      if (function == null) continue;
      // Ollama returns arguments as an already-decoded JSON object.
      final args = function['arguments'];
      out.add(
        LanguageModelV3ToolCallPart(
          toolCallId: raw['id']?.toString() ?? _generateId(),
          toolName: function['name']?.toString() ?? 'unknown_tool',
          input: args ?? <String, dynamic>{},
        ),
      );
    }
    return out;
  }

  /// Read real token usage from an Ollama response / final stream chunk.
  ///
  /// Ollama reports `prompt_eval_count` (input) and `eval_count` (output).
  LanguageModelV3Usage _usageFrom(Map<String, dynamic> data) {
    final input = (data['prompt_eval_count'] as num?)?.toInt();
    final output = (data['eval_count'] as num?)?.toInt();
    return LanguageModelV3Usage(
      inputTokens: input,
      outputTokens: output,
      totalTokens: (input != null && output != null) ? input + output : null,
    );
  }

  String _generateId() =>
      'ollama-tool-${DateTime.now().microsecondsSinceEpoch}';

  /// Resolve raw base64 image data (no `data:` prefix) from data content.
  String? _imageBase64(LanguageModelV3DataContent data) {
    return switch (data) {
      DataContentBytes(:final bytes) => base64Encode(bytes),
      DataContentBase64(:final base64) => base64,
      // Ollama embeds images inline; remote URLs are not supported here.
      DataContentUrl() => null,
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

    final body = <String, dynamic>{'model': model, 'input': options.values};

    final Response<Map<String, dynamic>> response;
    try {
      response = await client.post<Map<String, dynamic>>('/embed', data: body);
    } on DioException catch (e) {
      throw await _apiCallError(e, provider);
    }
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

/// Maps a [DioException] from a non-2xx response to a typed [AiApiCallError]
/// carrying the provider's message/status/code. Drains a streamed error body
/// (`ResponseType.stream`) when present so the message is recoverable.
Future<AiApiCallError> _apiCallError(
  DioException error,
  String provider,
) async {
  final data = error.response?.data;
  Object? body = data;
  if (data is ResponseBody) {
    final bytes = <int>[];
    await for (final chunk in data.stream) {
      bytes.addAll(chunk);
    }
    body = bytes;
  }
  return AiApiCallError.fromResponse(
    statusCode: error.response?.statusCode,
    url: error.requestOptions.uri.toString(),
    body: body ?? error.message,
    provider: provider,
    cause: error,
  );
}
