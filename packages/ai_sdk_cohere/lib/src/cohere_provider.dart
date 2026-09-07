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
/// final ranker = cohere.rerank('rerank-english-v4.0');
/// final ranked = await rerank(
///   model: ranker,
///   query: 'What is AI?',
///   documents: ['AI is...', 'Machines are...'],
/// );
/// ```
class CohereProvider {
  CohereProvider({
    this.apiKey,
    this.baseUrl,
    CredentialProvider? credentialProvider,
    Dio? client,
  }) : _credentialProvider =
           credentialProvider ??
           (() => apiKey ?? const String.fromEnvironment('COHERE_API_KEY')),
       _client = client ?? _cohereDio(baseUrl: baseUrl),
       _ownsClient = client == null;

  /// Cohere API key (defaults to `COHERE_API_KEY` env variable).
  final String? apiKey;

  /// Base URL — defaults to `https://api.cohere.com/v2`.
  final String? baseUrl;

  final CredentialProvider _credentialProvider;
  final Dio _client;
  final bool _ownsClient;

  Future<Map<String, String>> _headers() async {
    final key = await _credentialProvider();
    return {if (key != null && key.isNotEmpty) 'Authorization': 'Bearer $key'};
  }

  void dispose({bool force = true}) {
    if (_ownsClient) {
      _client.close(force: force);
    }
  }

  /// Returns a language model for the given [modelId].
  LanguageModelV4 call(String modelId) => _CohereLanguageModel(
    modelId: modelId,
    client: _client,
    headers: _headers,
  );

  /// Returns an embedding model for the given [modelId].
  EmbeddingModelV2<String> embedding(String modelId) => _CohereEmbeddingModel(
    modelId: modelId,
    client: _client,
    headers: _headers,
  );

  /// Returns a reranking model for the given [modelId].
  RerankModelV1 rerank(String modelId) =>
      _CohereRerankModel(modelId: modelId, client: _client, headers: _headers);
}

/// Default Cohere provider instance.
final cohere = CohereProvider();

// ---------------------------------------------------------------------------
// HTTP helper
// ---------------------------------------------------------------------------

Dio _cohereDio({String? baseUrl}) {
  return Dio(
    BaseOptions(
      baseUrl: baseUrl ?? 'https://api.cohere.com/v2',
      headers: {'Content-Type': 'application/json'},
    ),
  );
}

// ---------------------------------------------------------------------------
// Language model
// ---------------------------------------------------------------------------

class _CohereLanguageModel extends LanguageModelV4 {
  _CohereLanguageModel({
    required this.modelId,
    required this.client,
    required this.headers,
  });

  @override
  final String modelId;
  final Dio client;
  final RequestHeadersProvider headers;

  @override
  String get provider => 'cohere';

  @override
  String get specificationVersion => 'v4';

  /// Build Cohere v2 messages from a [LanguageModelV4Prompt].
  ///
  /// Serializes multimodal image content (as `content` arrays with
  /// `image_url` items), assistant tool calls, and `tool` result messages
  /// rather than flattening everything to plain text.
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

      // Tool result messages: one Cohere `tool` message per result part.
      if (role == 'tool') {
        final toolResults = msg.content
            .whereType<LanguageModelV4ToolResultPart>();
        var emitted = false;
        for (final result in toolResults) {
          messages.add({
            'role': 'tool',
            'tool_call_id': result.toolCallId,
            'content': _toolResultText(result),
          });
          emitted = true;
        }
        if (emitted) continue;
      }

      final text = msg.content
          .whereType<LanguageModelV4TextPart>()
          .map((p) => p.text)
          .join('\n');

      // Assistant messages may carry tool calls (and an optional tool plan).
      if (role == 'assistant') {
        final toolCalls = msg.content
            .whereType<LanguageModelV4ToolCallPart>()
            .map(
              (call) => {
                'id': call.toolCallId,
                'type': 'function',
                'function': {
                  'name': call.toolName,
                  'arguments': jsonEncode(call.input),
                },
              },
            )
            .toList();
        if (toolCalls.isNotEmpty) {
          messages.add({
            'role': 'assistant',
            if (text.isNotEmpty) 'tool_plan': text,
            'tool_calls': toolCalls,
          });
          continue;
        }
      }

      // Multimodal user/system content -> content array with image_url items.
      final hasImage = msg.content.any(
        (p) => p is LanguageModelV4ImagePart || p is LanguageModelV4FilePart,
      );
      if (hasImage) {
        final parts = _contentParts(msg.content);
        if (parts.isNotEmpty) {
          messages.add({'role': role, 'content': parts});
          continue;
        }
      }

      messages.add({'role': role, 'content': text});
    }
    return messages;
  }

  /// Convert message content parts into Cohere v2 content array entries.
  List<Map<String, dynamic>> _contentParts(
    List<LanguageModelV4ContentPart> parts,
  ) {
    final out = <Map<String, dynamic>>[];
    for (final part in parts) {
      if (part is LanguageModelV4TextPart) {
        out.add({'type': 'text', 'text': part.text});
      } else if (part is LanguageModelV4ImagePart) {
        final url = _imageUrl(part.image, part.mediaType);
        if (url != null) {
          out.add({
            'type': 'image_url',
            'image_url': {'url': url},
          });
        }
      } else if (part is LanguageModelV4FilePart &&
          part.mediaType.startsWith('image/')) {
        final url = _imageUrl(part.data, part.mediaType);
        if (url != null) {
          out.add({
            'type': 'image_url',
            'image_url': {'url': url},
          });
        }
      }
    }
    return out;
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

  /// Serialize function tools into the Cohere v2 `tools` field.
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

  /// Map a [LanguageModelV4ToolChoice] to the Cohere v2 `tool_choice` value.
  ///
  /// Cohere v2 only supports `REQUIRED` and `NONE`; `auto` is the default and
  /// is expressed by omitting the field. `specific` is approximated as
  /// `REQUIRED`.
  String? _toolChoice(LanguageModelV4ToolChoice choice) {
    return switch (choice) {
      ToolChoiceAuto() => null,
      ToolChoiceNone() => 'NONE',
      ToolChoiceRequired() => 'REQUIRED',
      ToolChoiceSpecific() => 'REQUIRED',
    };
  }

  Map<String, dynamic> _buildBody(LanguageModelV4CallOptions options) {
    final toolChoice = options.toolChoice == null
        ? null
        : _toolChoice(options.toolChoice!);
    return <String, dynamic>{
      'model': modelId,
      'messages': _buildMessages(options.prompt),
      if (options.functionTools.isNotEmpty)
        'tools': _buildTools(options.functionTools.toList()),
      'tool_choice': ?toolChoice,
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
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    final resolvedHeaders = await headers();
    final body = _buildBody(options);
    final cancelToken = _cancelTokenFor(options.abortSignal);

    final Response<Map<String, dynamic>> response;
    try {
      response = await client.post<Map<String, dynamic>>(
        '/chat',
        data: body,
        options: Options(headers: {...?options.headers, ...resolvedHeaders}),
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      throw await _apiCallError(e, provider);
    }
    final data = response.data!;

    final message = data['message'] as Map<String, dynamic>?;
    final contentList = message?['content'] as List?;
    final text =
        contentList
            ?.whereType<Map<String, dynamic>>()
            .where((c) => c['type'] == 'text')
            .map((c) => c['text'] as String)
            .join() ??
        '';

    final content = <LanguageModelV4ContentPart>[];
    if (text.isNotEmpty) {
      content.add(LanguageModelV4TextPart(text: text));
    }

    // Parse tool calls from the assistant message.
    final toolCalls = (message?['tool_calls'] as List?) ?? const [];
    for (final raw in toolCalls.whereType<Map<String, dynamic>>()) {
      final function = raw['function'] as Map<String, dynamic>?;
      content.add(
        LanguageModelV4ToolCallPart(
          toolCallId: raw['id']?.toString() ?? _generateId(),
          toolName: function?['name']?.toString() ?? 'unknown_tool',
          input: _safeParseJson(function?['arguments']?.toString() ?? '{}'),
        ),
      );
    }

    final usage = data['usage'] as Map<String, dynamic>?;
    final tokens = usage?['tokens'] as Map<String, dynamic>?;

    return LanguageModelV4GenerateResult(
      content: content,
      finishReason: _mapFinishReason(data['finish_reason'] as String?),
      rawFinishReason: data['finish_reason'] as String?,
      usage: LanguageModelV4Usage(
        inputTokens: LanguageModelV4InputTokenUsage(
          total: (tokens?['input_tokens'] as num?)?.toInt() ?? 0,
        ),
        outputTokens: LanguageModelV4OutputTokenUsage(
          total: (tokens?['output_tokens'] as num?)?.toInt() ?? 0,
        ),
      ),
    );
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    final resolvedHeaders = await headers();
    final body = _buildBody(options)..['stream'] = true;
    final cancelToken = _cancelTokenFor(options.abortSignal);

    final Response<ResponseBody> response;
    try {
      response = await client.post<ResponseBody>(
        '/chat',
        data: body,
        options: Options(
          responseType: ResponseType.stream,
          headers: {...?options.headers, ...resolvedHeaders},
        ),
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      throw await _apiCallError(e, provider);
    }

    final controller = StreamController<LanguageModelV4StreamPart>();
    final byteStream = response.data!.stream;
    final responseHeaders = response.headers.map.map(
      (key, value) => MapEntry(key, value.join(',')),
    );
    final responseTimestamp = DateTime.now().toUtc();

    unawaited(
      _processStream(
        byteStream,
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
        modelId: modelId,
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
    Map<String, dynamic>? lastEvent;
    // Per-index tool-call streaming state.
    final toolStates = <int, _CohereToolState>{};
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
          final type = event['type'] as String?;
          final delta = event['delta'] as Map<String, dynamic>?;
          final message = delta?['message'] as Map<String, dynamic>?;
          if (type == 'content-delta') {
            final content = message?['content'] as Map<String, dynamic>?;
            final text = content?['text'] as String?;
            if (text != null && text.isNotEmpty) {
              if (!textStarted) {
                textStarted = true;
                controller.add(const StreamPartTextStart(id: 'text-0'));
              }
              controller.add(StreamPartTextDelta(id: 'text-0', delta: text));
            }
          } else if (type == 'tool-call-start') {
            final index = (event['index'] as num?)?.toInt() ?? 0;
            final toolCall = message?['tool_calls'] as Map<String, dynamic>?;
            final function = toolCall?['function'] as Map<String, dynamic>?;
            final id = toolCall?['id']?.toString() ?? _generateId();
            final name = function?['name']?.toString() ?? 'unknown_tool';
            final state = _CohereToolState(id: id, name: name);
            toolStates[index] = state;
            controller.add(StreamPartToolInputStart(id: id, toolName: name));
            final args = function?['arguments']?.toString();
            if (args != null && args.isNotEmpty) {
              state.args.write(args);
              controller.add(StreamPartToolInputDelta(id: id, delta: args));
            }
          } else if (type == 'tool-call-delta') {
            final index = (event['index'] as num?)?.toInt() ?? 0;
            final state = toolStates[index];
            final toolCall = message?['tool_calls'] as Map<String, dynamic>?;
            final function = toolCall?['function'] as Map<String, dynamic>?;
            final args = function?['arguments']?.toString();
            if (state != null && args != null && args.isNotEmpty) {
              state.args.write(args);
              controller.add(
                StreamPartToolInputDelta(id: state.id, delta: args),
              );
            }
          } else if (type == 'tool-call-end') {
            final index = (event['index'] as num?)?.toInt() ?? 0;
            _finalizeToolCall(
              index: index,
              toolStates: toolStates,
              controller: controller,
            );
          } else if (type == 'message-end') {
            // Emit ends for any tool calls that never got an explicit end.
            final pendingIndexes = toolStates.keys.toList()..sort();
            for (final index in pendingIndexes) {
              _finalizeToolCall(
                index: index,
                toolStates: toolStates,
                controller: controller,
              );
            }
            if (textStarted) {
              controller.add(const StreamPartTextEnd(id: 'text-0'));
            }
            final usage = delta?['usage'] as Map<String, dynamic>?;
            final tokens = usage?['tokens'] as Map<String, dynamic>?;
            controller.add(
              StreamPartResponseMetadata(
                metadata: LanguageModelV4ResponseMetadata(
                  modelId: modelId,
                  timestamp: responseTimestamp,
                  headers: responseHeaders,
                  body: lastEvent,
                ),
              ),
            );
            controller.add(
              StreamPartFinish(
                finishReason: _mapFinishReason(
                  delta?['finish_reason'] as String?,
                ),
                rawFinishReason: delta?['finish_reason'] as String?,
                usage: LanguageModelV4Usage(
                  inputTokens: LanguageModelV4InputTokenUsage(
                    total: (tokens?['input_tokens'] as num?)?.toInt() ?? 0,
                  ),
                  outputTokens: LanguageModelV4OutputTokenUsage(
                    total: (tokens?['output_tokens'] as num?)?.toInt() ?? 0,
                  ),
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

  void _finalizeToolCall({
    required int index,
    required Map<int, _CohereToolState> toolStates,
    required StreamController<LanguageModelV4StreamPart> controller,
  }) {
    final state = toolStates.remove(index);
    if (state == null) return;
    controller.add(StreamPartToolInputEnd(id: state.id));
    controller.add(
      StreamPartToolCall(
        toolCall: LanguageModelV4ToolCallPart(
          toolCallId: state.id,
          toolName: state.name,
          input: _safeParseJson(state.args.toString()),
        ),
      ),
    );
  }

  LanguageModelV4FinishReason _mapFinishReason(String? reason) {
    return switch (reason) {
      'COMPLETE' || 'complete' => LanguageModelV4FinishReason.stop,
      'MAX_TOKENS' || 'max_tokens' => LanguageModelV4FinishReason.length,
      'STOP_SEQUENCE' || 'stop_sequence' => LanguageModelV4FinishReason.stop,
      'TOOL_CALL' || 'tool_call' => LanguageModelV4FinishReason.toolCalls,
      _ => LanguageModelV4FinishReason.other,
    };
  }
}

/// Per-index tool-call accumulation state during Cohere streaming.
class _CohereToolState {
  _CohereToolState({required this.id, required this.name});

  final String id;
  final String name;
  final StringBuffer args = StringBuffer();
}

/// Resolve a Cohere v2 image `url` from data content (URL or base64 data URI).
String? _imageUrl(LanguageModelV4DataContent data, String? mediaType) {
  if (data is DataContentUrl) return data.url.toString();
  final b64 = switch (data) {
    DataContentBytes(:final bytes) => base64Encode(bytes),
    DataContentBase64(:final base64) => base64,
    // coverage:ignore-start
    DataContentUrl() => null, // unreachable: URL data early-returns above
    // coverage:ignore-end
  };
  if (b64 == null) return null;
  return 'data:${mediaType ?? 'image/png'};base64,$b64';
}

Object _safeParseJson(String input) {
  try {
    return jsonDecode(input);
  } catch (_) {
    return input;
  }
}

String _generateId() => 'cohere-tool-${DateTime.now().microsecondsSinceEpoch}';

// ---------------------------------------------------------------------------
// Embedding model
// ---------------------------------------------------------------------------

class _CohereEmbeddingModel implements EmbeddingModelV2<String> {
  _CohereEmbeddingModel({
    required this.modelId,
    required this.client,
    required this.headers,
  });

  @override
  final String modelId;
  final Dio client;
  final RequestHeadersProvider headers;

  @override
  String get provider => 'cohere';

  @override
  String get specificationVersion => 'v2';

  @override
  Future<EmbeddingModelV2GenerateResult<String>> doEmbed(
    EmbeddingModelV2CallOptions<String> options,
  ) async {
    final resolvedHeaders = await headers();

    final body = <String, dynamic>{
      'model': modelId,
      'texts': options.values,
      'input_type': 'search_document',
      'embedding_types': ['float'],
    };

    final Response<Map<String, dynamic>> response;
    try {
      response = await client.post<Map<String, dynamic>>(
        '/embed',
        data: body,
        options: Options(headers: {...?options.headers, ...resolvedHeaders}),
      );
    } on DioException catch (e) {
      throw await _apiCallError(e, provider);
    }
    final data = response.data!;
    final embeddingsData = data['embeddings'] as Map<String, dynamic>?;
    final floats = (embeddingsData?['float'] as List?) ?? [];
    final embeddings = floats.take(options.values.length).indexed.map((entry) {
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

// ---------------------------------------------------------------------------
// Rerank model
// ---------------------------------------------------------------------------

class _CohereRerankModel implements RerankModelV1 {
  _CohereRerankModel({
    required this.modelId,
    required this.client,
    required this.headers,
  });

  @override
  final String modelId;
  final Dio client;
  final RequestHeadersProvider headers;

  @override
  String get provider => 'cohere';

  @override
  String get specificationVersion => 'v1';

  @override
  Future<RerankModelV1Result> doRerank(RerankModelV1CallOptions options) async {
    final resolvedHeaders = await headers();

    final body = <String, dynamic>{
      'model': modelId,
      'query': options.query,
      'documents': options.documents,
      if (options.topN != null) 'top_n': options.topN,
    };

    final Response<Map<String, dynamic>> response;
    try {
      response = await client.post<Map<String, dynamic>>(
        '/rerank',
        data: body,
        options: Options(headers: {...?options.headers, ...resolvedHeaders}),
      );
    } on DioException catch (e) {
      throw await _apiCallError(e, provider);
    }
    final data = response.data!;
    final results = (data['results'] as List?) ?? [];

    final documents = results.map((r) {
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
