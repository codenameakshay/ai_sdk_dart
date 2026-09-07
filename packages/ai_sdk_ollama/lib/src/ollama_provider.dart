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
  OllamaProvider({this.baseUrl, Dio? client})
    : _client = client ?? _ollamaDio(baseUrl: baseUrl),
      _ownsClient = client == null;

  /// Base URL — defaults to `http://localhost:11434/api`.
  final String? baseUrl;

  final Dio _client;
  final bool _ownsClient;

  void dispose({bool force = true}) {
    if (_ownsClient) {
      _client.close(force: force);
    }
  }

  /// Returns a language model for the given [model].
  LanguageModelV4 call(String model) =>
      _OllamaLanguageModel(model: model, client: _client);

  /// Returns an embedding model for the given [model].
  EmbeddingModelV2<String> embedding(String model) =>
      _OllamaEmbeddingModel(model: model, client: _client);
}

/// Default Ollama provider instance (connects to http://localhost:11434).
final ollama = OllamaProvider();

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

class _OllamaLanguageModel extends LanguageModelV4 {
  _OllamaLanguageModel({required this.model, required this.client});

  final String model;
  final Dio client;

  @override
  String get modelId => model;

  @override
  String get provider => 'ollama';

  @override
  String get specificationVersion => 'v4';

  /// Build Ollama `/api/chat` messages from a [LanguageModelV4Prompt].
  ///
  /// Image parts are attached to the message via the Ollama `images` field
  /// (base64 strings, no `data:` prefix). Assistant tool calls and `tool`
  /// result messages are preserved rather than dropped.
  List<Map<String, dynamic>> _buildMessages(LanguageModelV4Prompt prompt) {
    final messages = <Map<String, dynamic>>[];
    if (prompt.system != null) {
      messages.add({'role': 'system', 'content': prompt.system!});
    }
    for (final msg in prompt.messages) {
      final role = switch (msg.role) {
        LanguageModelV4Role.user => 'user',
        LanguageModelV4Role.assistant => 'assistant',
        LanguageModelV4Role.tool => 'tool',
        LanguageModelV4Role.system => 'system',
      };

      // Tool result messages: one Ollama `tool` message per result part.
      if (role == 'tool') {
        final toolResults = msg.content
            .whereType<LanguageModelV4ToolResultPart>();
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
          .whereType<LanguageModelV4TextPart>()
          .map((p) => p.text)
          .join('\n');

      // Assistant messages may carry tool calls.
      if (role == 'assistant') {
        final toolCalls = msg.content
            .whereType<LanguageModelV4ToolCallPart>()
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
        if (part is LanguageModelV4ImagePart) {
          final b64 = _imageBase64(part.image);
          if (b64 != null) images.add(b64);
        } else if (part is LanguageModelV4FilePart &&
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

  String _toolResultText(LanguageModelV4ToolResultPart result) {
    final output = result.output;
    if (output is ToolResultOutputText) return output.text;
    if (output is ToolResultOutputContent) {
      return output.parts
          .whereType<LanguageModelV4TextPart>()
          .map((p) => p.text)
          .join('\n');
    }
    return '';
  }

  /// Serialize function tools into Ollama's OpenAI-style `tools` field.
  List<Map<String, dynamic>> _buildTools(
    List<LanguageModelV4FunctionTool> tools,
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

  Map<String, dynamic> _buildBody(LanguageModelV4CallOptions options) {
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
      if (options.functionTools.isNotEmpty)
        'tools': _buildTools(options.functionTools.toList()),
      if (ollamaOptions.isNotEmpty) 'options': ollamaOptions,
      'stream': false,
    };
  }

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    final body = _buildBody(options);
    final cancelToken = _cancelTokenFor(options.abortSignal);

    final Response<Map<String, dynamic>> response;
    try {
      response = await client.post<Map<String, dynamic>>(
        '/chat',
        data: body,
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      throw await _apiCallError(e, provider);
    }
    final data = response.data!;

    final message = data['message'] as Map<String, dynamic>?;
    final text = (message?['content'] as String?) ?? '';
    final rawFinishReason = data['done_reason'] as String?;

    final content = <LanguageModelV4ContentPart>[];
    if (text.isNotEmpty) {
      content.add(LanguageModelV4TextPart(text: text));
    }
    content.addAll(_parseToolCalls(message?['tool_calls'] as List?));

    return LanguageModelV4GenerateResult(
      content: content,
      finishReason: content.any((p) => p is LanguageModelV4ToolCallPart)
          ? LanguageModelV4FinishReason.toolCalls
          : _mapFinishReason(rawFinishReason),
      rawFinishReason: rawFinishReason,
      usage: _usageFrom(data),
    );
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    // Override stream to true for streaming mode.
    final body = _buildBody(options);
    body['stream'] = true;
    final cancelToken = _cancelTokenFor(options.abortSignal);

    final Response<ResponseBody> response;
    try {
      response = await client.post<ResponseBody>(
        '/chat',
        data: body,
        options: Options(responseType: ResponseType.stream),
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      throw await _apiCallError(e, provider);
    }

    final controller = StreamController<LanguageModelV4StreamPart>();
    final responseHeaders = response.headers.map.map(
      (key, value) => MapEntry(key, value.join(',')),
    );
    final responseTimestamp = DateTime.now().toUtc();
    unawaited(
      _processStream(
        response.data!.stream,
        controller,
        includeRawChunks: options.includeRawChunks,
        responseHeaders: responseHeaders,
        responseTimestamp: responseTimestamp,
      ).catchError((Object e) {
        if (!controller.isClosed) {
          controller.add(StreamPartError(error: e));
          controller.close();
        }
      }),
    );

    return LanguageModelV4StreamResult(
      stream: controller.stream,
      request: LanguageModelV4RequestMetadata(body: body),
      response: LanguageModelV4ResponseMetadata(
        modelId: model,
        timestamp: responseTimestamp,
        headers: responseHeaders,
      ),
    );
  }

  Future<void> _processStream(
    Stream<List<int>> byteStream,
    StreamController<LanguageModelV4StreamPart> controller, {
    required bool includeRawChunks,
    required Map<String, String> responseHeaders,
    required DateTime responseTimestamp,
  }) async {
    var buffer = '';
    var textStarted = false;
    var sawAnyToolCall = false;
    Map<String, dynamic>? lastEvent;
    controller.add(const StreamPartStreamStart());
    await for (final bytes in byteStream) {
      buffer += utf8.decode(bytes);
      final lines = buffer.split('\n');
      buffer = lines.removeLast();
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        try {
          final event = jsonDecode(trimmed) as Map<String, dynamic>;
          lastEvent = event;
          if (includeRawChunks) {
            controller.add(StreamPartRaw(rawValue: event));
          }
          final message = event['message'] as Map<String, dynamic>?;
          final content = message?['content'] as String?;
          if (content != null && content.isNotEmpty) {
            if (!textStarted) {
              textStarted = true;
              controller.add(const StreamPartTextStart(id: 'text-0'));
            }
            controller.add(StreamPartTextDelta(id: 'text-0', delta: content));
          }

          // Ollama emits whole tool calls (not incremental deltas).
          final toolCalls = _parseToolCalls(message?['tool_calls'] as List?);
          for (final call in toolCalls) {
            sawAnyToolCall = true;
            controller.add(
              StreamPartToolInputStart(
                id: call.toolCallId,
                toolName: call.toolName,
              ),
            );
            controller.add(
              StreamPartToolInputDelta(
                id: call.toolCallId,
                delta: jsonEncode(call.input),
              ),
            );
            controller.add(StreamPartToolInputEnd(id: call.toolCallId));
            controller.add(StreamPartToolCall(toolCall: call));
          }

          final done = event['done'] as bool? ?? false;
          if (done) {
            final doneReason = event['done_reason'] as String?;
            if (textStarted) {
              controller.add(const StreamPartTextEnd(id: 'text-0'));
            }
            controller.add(
              StreamPartResponseMetadata(
                metadata: LanguageModelV4ResponseMetadata(
                  modelId: model,
                  timestamp: responseTimestamp,
                  headers: responseHeaders,
                  body: lastEvent,
                ),
              ),
            );
            controller.add(
              StreamPartFinish(
                finishReason: sawAnyToolCall
                    ? LanguageModelV4FinishReason.toolCalls
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

  LanguageModelV4FinishReason _mapFinishReason(String? reason) {
    return switch (reason) {
      'stop' => LanguageModelV4FinishReason.stop,
      'length' => LanguageModelV4FinishReason.length,
      _ => LanguageModelV4FinishReason.other,
    };
  }

  /// Parse `message.tool_calls` from an Ollama response into tool-call parts.
  List<LanguageModelV4ToolCallPart> _parseToolCalls(List? toolCalls) {
    if (toolCalls == null) return const [];
    final out = <LanguageModelV4ToolCallPart>[];
    for (final raw in toolCalls.whereType<Map<String, dynamic>>()) {
      final function = raw['function'] as Map<String, dynamic>?;
      if (function == null) continue;
      // Ollama returns arguments as an already-decoded JSON object.
      final args = function['arguments'];
      out.add(
        LanguageModelV4ToolCallPart(
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
  LanguageModelV4Usage _usageFrom(Map<String, dynamic> data) {
    final input = (data['prompt_eval_count'] as num?)?.toInt();
    final output = (data['eval_count'] as num?)?.toInt();
    return LanguageModelV4Usage(
      inputTokens: LanguageModelV4InputTokenUsage(total: input),
      outputTokens: LanguageModelV4OutputTokenUsage(total: output),
    );
  }

  String _generateId() =>
      'ollama-tool-${DateTime.now().microsecondsSinceEpoch}';

  /// Resolve raw base64 image data (no `data:` prefix) from data content.
  String? _imageBase64(LanguageModelV4DataContent data) {
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
  _OllamaEmbeddingModel({required this.model, required this.client});

  final String model;
  final Dio client;

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
    final body = <String, dynamic>{'model': model, 'input': options.values};

    final Response<Map<String, dynamic>> response;
    try {
      response = await client.post<Map<String, dynamic>>('/embed', data: body);
    } on DioException catch (e) {
      throw await _apiCallError(e, provider);
    }
    final data = response.data!;
    final embeddingsList = (data['embeddings'] as List?) ?? [];
    final embeddings = embeddingsList.take(options.values.length).indexed.map((
      entry,
    ) {
      final vector = (entry.$2 as List)
          .map((value) => (value as num).toDouble())
          .toList();
      return EmbeddingModelV2Embedding<String>(
        value: options.values[entry.$1],
        embedding: vector,
      );
    }).toList();

    return EmbeddingModelV2GenerateResult<String>(embeddings: embeddings);
  }
}

/// Maps a [DioException] from a non-2xx response to a typed [AiApiCallError]
/// carrying the provider's message/status/code. Drains a streamed error body
/// (`ResponseType.stream`) when present so the message is recoverable.
CancelToken? _cancelTokenFor(LanguageModelV4AbortSignal? abortSignal) {
  if (abortSignal == null) {
    return null;
  }

  final cancelToken = CancelToken();
  if (abortSignal.isCancelled) {
    cancelToken.cancel('abortSignal');
    return cancelToken;
  }

  unawaited(
    abortSignal.onCancelled.then((_) {
      if (!cancelToken.isCancelled) {
        cancelToken.cancel('abortSignal');
      }
    }),
  );
  return cancelToken;
}

Future<AiSdkError> _apiCallError(DioException error, String provider) async {
  if (error.type == DioExceptionType.cancel || CancelToken.isCancel(error)) {
    return const AiOperationCancelledError();
  }
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
