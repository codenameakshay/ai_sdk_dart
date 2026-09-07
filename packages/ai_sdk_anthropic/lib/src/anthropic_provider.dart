import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';

/// Anthropic provider for Claude language models.
///
/// Use [call] to get a language model for the given [modelId].
///
/// Example:
/// ```dart
/// final model = anthropic('claude-3-5-sonnet-20241022');
/// final result = await generateText(model: model, prompt: 'Hello');
/// ```
class AnthropicProvider {
  AnthropicProvider({
    this.apiKey,
    this.baseUrl,
    CredentialProvider? credentialProvider,
    Dio? client,
  }) : _credentialProvider =
           credentialProvider ??
           (() => apiKey ?? const String.fromEnvironment('ANTHROPIC_API_KEY')),
       _client = client ?? _anthropicDio(baseUrl: baseUrl),
       _ownsClient = client == null;

  /// API key (defaults to `ANTHROPIC_API_KEY` environment variable).
  final String? apiKey;

  /// Base URL for the API.
  final String? baseUrl;

  final CredentialProvider _credentialProvider;
  final Dio _client;
  final bool _ownsClient;

  Future<Map<String, String>> _headers() async {
    final key = await _credentialProvider();
    return {
      if (key != null && key.isNotEmpty) 'x-api-key': key,
      'anthropic-version': '2023-06-01',
    };
  }

  void dispose({bool force = true}) {
    if (_ownsClient) {
      _client.close(force: force);
    }
  }

  /// Returns a language model for the given [modelId].
  LanguageModelV4 call(String modelId) => _AnthropicLanguageModel(
    modelId: modelId,
    client: _client,
    headers: _headers,
  );
}

/// Default Anthropic provider instance.
final anthropic = AnthropicProvider();

class _AnthropicLanguageModel extends LanguageModelV4 {
  _AnthropicLanguageModel({
    required this.modelId,
    required this.client,
    required this.headers,
  });

  @override
  final String modelId;
  final Dio client;
  final RequestHeadersProvider headers;

  @override
  String get provider => 'anthropic';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    final resolvedHeaders = await headers();
    final cancelToken = _cancelTokenFor(options.abortSignal);
    final po = options.providerOptions != null
        ? options.providerOptions![provider]
        : null;
    final (thinking, cleanedPo) = _extractThinkingOptions(po);
    final requestBody = {
      'model': modelId,
      'max_tokens': options.maxOutputTokens ?? 1024,
      'system': options.prompt.system,
      'messages': _toAnthropicMessages(options.prompt),
      if (options.temperature != null) 'temperature': options.temperature,
      if (options.topP != null) 'top_p': options.topP,
      if (options.stopSequences.isNotEmpty)
        'stop_sequences': options.stopSequences,
      if (options.tools.isNotEmpty)
        'tools': options.tools.map(_toAnthropicTool).toList(),
      if (options.toolChoice != null)
        'tool_choice': _toAnthropicToolChoice(options.toolChoice!),
      'thinking': ?thinking,
      ...?cleanedPo,
    };
    final Response<Map<String, dynamic>> response;
    try {
      response = await client.post<Map<String, dynamic>>(
        '/messages',
        data: requestBody,
        options: Options(headers: {...?options.headers, ...resolvedHeaders}),
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      throw await _apiCallError(e, provider);
    }

    final data = response.data ?? <String, dynamic>{};
    final content = <LanguageModelV4ContentPart>[];

    final parts = (data['content'] as List?) ?? const [];
    for (final part in parts) {
      final map = (part as Map).cast<String, dynamic>();
      final type = map['type']?.toString();
      if (type == 'text') {
        final text = map['text']?.toString();
        if (text != null && text.isNotEmpty) {
          content.add(LanguageModelV4TextPart(text: text));
        }

        final citations = (map['citations'] as List?) ?? const [];
        for (var i = 0; i < citations.length; i++) {
          final citation = (citations[i] as Map).cast<String, dynamic>();
          final url = citation['url']?.toString();
          if (url != null && url.isNotEmpty) {
            content.add(
              LanguageModelV4SourcePart(
                id: 'anthropic_source_$i',
                url: url,
                title: citation['title']?.toString(),
                providerMetadata: citation,
              ),
            );
          }
        }
      } else if (type == 'tool_use') {
        final rawInput = map['input'];
        content.add(
          LanguageModelV4ToolCallPart(
            toolCallId: map['id']?.toString() ?? _generateId('tool'),
            toolName: map['name']?.toString() ?? 'unknown_tool',
            input: rawInput is Map
                ? rawInput.cast<String, dynamic>()
                : (rawInput ?? const {}),
          ),
        );
      } else if (type == 'thinking') {
        final text = map['thinking']?.toString() ?? '';
        if (text.isNotEmpty) {
          content.add(
            LanguageModelV4ReasoningPart(
              text: text,
              signature: map['signature']?.toString(),
            ),
          );
        }
      } else if (type == 'redacted_thinking') {
        final redacted = map['data']?.toString();
        if (redacted != null && redacted.isNotEmpty) {
          content.add(
            LanguageModelV4RedactedReasoningPart(
              data: Uint8List.fromList(utf8.encode(redacted)),
            ),
          );
        }
      }
    }

    final usage = (data['usage'] as Map?)?.cast<String, dynamic>();
    final warnings = _readWarnings(data['warnings']);
    return LanguageModelV4GenerateResult(
      content: content,
      finishReason: _mapAnthropicFinishReason(data['stop_reason']?.toString()),
      rawFinishReason: data['stop_reason']?.toString(),
      usage: usage == null ? null : _anthropicUsageFrom(usage),
      warnings: warnings,
      request: LanguageModelV4RequestMetadata(body: requestBody),
      response: LanguageModelV4ResponseMetadata(
        id: data['id']?.toString(),
        modelId: data['model']?.toString() ?? modelId,
        timestamp: DateTime.now().toUtc(),
        headers: response.headers.map.map(
          (key, value) => MapEntry(key, value.join(',')),
        ),
        body: data,
      ),
    );
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    final resolvedHeaders = await headers();
    final cancelToken = _cancelTokenFor(options.abortSignal);
    final po = options.providerOptions != null
        ? options.providerOptions![provider]
        : null;
    final (thinking, cleanedPo) = _extractThinkingOptions(po);
    final requestBody = {
      'model': modelId,
      'max_tokens': options.maxOutputTokens ?? 1024,
      'system': options.prompt.system,
      'messages': _toAnthropicMessages(options.prompt),
      'stream': true,
      if (options.temperature != null) 'temperature': options.temperature,
      if (options.topP != null) 'top_p': options.topP,
      if (options.tools.isNotEmpty)
        'tools': options.tools.map(_toAnthropicTool).toList(),
      if (options.toolChoice != null)
        'tool_choice': _toAnthropicToolChoice(options.toolChoice!),
      'thinking': ?thinking,
      ...?cleanedPo,
    };
    final Response<ResponseBody> response;
    try {
      response = await client.post<ResponseBody>(
        '/messages',
        data: requestBody,
        options: Options(
          responseType: ResponseType.stream,
          headers: {...?options.headers, ...resolvedHeaders},
        ),
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      throw await _apiCallError(e, provider);
    }

    final body = response.data;
    // Defensive: Dio always supplies a ResponseBody for a successful streamed
    // response, so this guard is unreachable under normal operation.
    // coverage:ignore-start
    if (body == null) {
      throw StateError('Anthropic stream response body is null.');
    }
    // coverage:ignore-end

    final controller = StreamController<LanguageModelV4StreamPart>();
    final toolState = <int, _ToolState>{};
    final reasoningState = <int, _ReasoningState>{};
    var textStarted = false;
    var streamStarted = false;
    LanguageModelV4Usage? streamUsage;
    final streamWarnings = <LanguageModelV4Warning>[];
    String? responseId;
    String? responseModel;
    Map<String, dynamic>? lastChunk;
    final responseHeaders = response.headers.map.map(
      (key, value) => MapEntry(key, value.join(',')),
    );
    final responseTimestamp = DateTime.now().toUtc();

    unawaited(() async {
      try {
        await for (final dataLine in _readSseDataLines(body.stream)) {
          final json = _safeParseMap(dataLine);
          if (json == null) continue;
          lastChunk = json;
          final type = json['type']?.toString();
          streamWarnings.addAll(_readWarnings(json['warnings']));
          if (!streamStarted) {
            streamStarted = true;
            controller.add(
              StreamPartStreamStart(
                warnings: List.unmodifiable(streamWarnings),
              ),
            );
          }
          if (options.includeRawChunks) {
            controller.add(StreamPartRaw(rawValue: json));
          }

          switch (type) {
            case 'message_start':
              final message =
                  (json['message'] as Map?)?.cast<String, dynamic>() ??
                  <String, dynamic>{};
              responseId ??= message['id']?.toString();
              responseModel ??= message['model']?.toString();
              final usage =
                  (message['usage'] as Map?)?.cast<String, dynamic>() ??
                  <String, dynamic>{};
              streamUsage = _anthropicUsageFrom(usage, previous: streamUsage);
              break;
            case 'content_block_start':
              final index = _intOrNull(json['index']) ?? 0;
              final block =
                  (json['content_block'] as Map?)?.cast<String, dynamic>() ??
                  <String, dynamic>{};
              final blockType = block['type']?.toString();
              if (blockType == 'text') {
                if (!textStarted) {
                  textStarted = true;
                  controller.add(const StreamPartTextStart(id: 'text-0'));
                }
              } else if (blockType == 'tool_use') {
                final id = block['id']?.toString() ?? _generateId('tool');
                final name = block['name']?.toString() ?? 'unknown_tool';
                toolState[index] = _ToolState(id: id, name: name);
                controller.add(
                  StreamPartToolInputStart(id: id, toolName: name),
                );
              } else if (blockType == 'thinking') {
                final id = block['id']?.toString() ?? 'reasoning-$index';
                reasoningState[index] = _ReasoningState(id: id);
                controller.add(StreamPartReasoningStart(id: id));
              }
              break;
            case 'content_block_delta':
              final index = _intOrNull(json['index']) ?? 0;
              final delta =
                  (json['delta'] as Map?)?.cast<String, dynamic>() ??
                  <String, dynamic>{};
              final deltaType = delta['type']?.toString();
              if (deltaType == 'text_delta') {
                final text = delta['text']?.toString();
                if (text != null && text.isNotEmpty) {
                  if (!textStarted) {
                    textStarted = true;
                    controller.add(const StreamPartTextStart(id: 'text-0'));
                  }
                  controller.add(
                    StreamPartTextDelta(id: 'text-0', delta: text),
                  );
                }
              } else if (deltaType == 'input_json_delta') {
                final chunk = delta['partial_json']?.toString();
                final state = toolState[index];
                if (state != null && chunk != null && chunk.isNotEmpty) {
                  state.argumentsBuffer.write(chunk);
                  controller.add(
                    StreamPartToolInputDelta(id: state.id, delta: chunk),
                  );
                }
              } else if (deltaType == 'thinking_delta') {
                final reasoning = delta['thinking']?.toString();
                if (reasoning != null && reasoning.isNotEmpty) {
                  final state = reasoningState.putIfAbsent(index, () {
                    final next = _ReasoningState(id: 'reasoning-$index');
                    controller.add(StreamPartReasoningStart(id: next.id));
                    return next;
                  });
                  controller.add(
                    StreamPartReasoningDelta(id: state.id, delta: reasoning),
                  );
                }
              }
              break;
            case 'content_block_stop':
              final index = _intOrNull(json['index']) ?? 0;
              final state = toolState.remove(index);
              if (state != null) {
                controller.add(StreamPartToolInputEnd(id: state.id));
                controller.add(
                  StreamPartToolCall(
                    toolCall: LanguageModelV4ToolCallPart(
                      toolCallId: state.id,
                      toolName: state.name,
                      input: _safeParseJson(state.argumentsBuffer.toString()),
                    ),
                  ),
                );
              }
              final reasoning = reasoningState.remove(index);
              if (reasoning != null) {
                controller.add(StreamPartReasoningEnd(id: reasoning.id));
              }
              break;
            case 'message_delta':
              final delta =
                  (json['delta'] as Map?)?.cast<String, dynamic>() ??
                  <String, dynamic>{};
              final usage =
                  (json['usage'] as Map?)?.cast<String, dynamic>() ??
                  <String, dynamic>{};
              if (usage.isNotEmpty) {
                streamUsage = _anthropicUsageFrom(usage, previous: streamUsage);
              }
              final stopReason = delta['stop_reason']?.toString();
              if (stopReason != null) {
                if (textStarted) {
                  controller.add(const StreamPartTextEnd(id: 'text-0'));
                }
                for (final state in toolState.values.toList()) {
                  controller.add(StreamPartToolInputEnd(id: state.id));
                  controller.add(
                    StreamPartToolCall(
                      toolCall: LanguageModelV4ToolCallPart(
                        toolCallId: state.id,
                        toolName: state.name,
                        input: _safeParseJson(state.argumentsBuffer.toString()),
                      ),
                    ),
                  );
                }
                toolState.clear();
                for (final state in reasoningState.values.toList()) {
                  controller.add(StreamPartReasoningEnd(id: state.id));
                }
                reasoningState.clear();
                controller.add(
                  StreamPartResponseMetadata(
                    metadata: LanguageModelV4ResponseMetadata(
                      id: responseId,
                      modelId: responseModel,
                      timestamp: responseTimestamp,
                      headers: responseHeaders,
                      body: lastChunk,
                    ),
                  ),
                );
                controller.add(
                  StreamPartFinish(
                    finishReason: _mapAnthropicFinishReason(stopReason),
                    rawFinishReason: stopReason,
                    usage: streamUsage ?? const LanguageModelV4Usage(),
                    providerMetadata: {
                      provider: {
                        'id': ?responseId,
                        'model': ?responseModel,
                        'timestamp': DateTime.now().toUtc().toIso8601String(),
                        if (streamWarnings.isNotEmpty)
                          'warnings': streamWarnings
                              .map((warning) => warning.type)
                              .toList(growable: false),
                      },
                    },
                  ),
                );
              }
              break;
            case 'error':
              controller.add(StreamPartError(error: json));
              break;
          }
        }
      } catch (error) {
        if (!streamStarted) {
          streamStarted = true;
          controller.add(const StreamPartStreamStart());
        }
        controller.add(StreamPartError(error: error));
      } finally {
        if (!streamStarted) {
          controller.add(const StreamPartStreamStart());
        }
        await controller.close();
      }
    }());

    return LanguageModelV4StreamResult(
      stream: controller.stream,
      warnings: List.unmodifiable(streamWarnings),
      request: LanguageModelV4RequestMetadata(body: requestBody),
      response: LanguageModelV4ResponseMetadata(
        id: responseId,
        modelId: responseModel,
        timestamp: responseTimestamp,
        headers: responseHeaders,
        body: lastChunk,
      ),
    );
  }
}

Dio _anthropicDio({String? baseUrl}) {
  return Dio(
    BaseOptions(
      baseUrl: baseUrl ?? 'https://api.anthropic.com/v1',
      headers: {
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
      },
    ),
  );
}

List<Map<String, dynamic>> _toAnthropicMessages(LanguageModelV4Prompt prompt) {
  final out = <Map<String, dynamic>>[];

  for (final message in prompt.messages) {
    final role = switch (message.role) {
      LanguageModelV4Role.system => 'user',
      LanguageModelV4Role.user => 'user',
      LanguageModelV4Role.assistant => 'assistant',
      LanguageModelV4Role.tool => 'user',
    };

    final contentParts = <Map<String, dynamic>>[];
    for (final part in message.content) {
      if (part is LanguageModelV4TextPart) {
        contentParts.add({'type': 'text', 'text': part.text});
      } else if (part is LanguageModelV4ImagePart) {
        final image = _toAnthropicImagePart(part);
        if (image != null) {
          contentParts.add(image);
        }
      } else if (part is LanguageModelV4FilePart) {
        final document = _toAnthropicFilePart(part);
        if (document != null) {
          contentParts.add(document);
        }
      } else if (part is LanguageModelV4ToolCallPart) {
        contentParts.add({
          'type': 'tool_use',
          'id': part.toolCallId,
          'name': part.toolName,
          'input': part.input,
        });
      } else if (part is LanguageModelV4ToolResultPart) {
        contentParts.add({
          'type': 'tool_result',
          'tool_use_id': part.toolCallId,
          'content': _toAnthropicToolResultContent(part.output),
          'is_error': part.isError,
        });
      }
    }

    if (contentParts.isEmpty) continue;
    out.add({'role': role, 'content': contentParts});
  }

  return out;
}

Map<String, dynamic> _toAnthropicToolChoice(LanguageModelV4ToolChoice choice) {
  return switch (choice) {
    ToolChoiceAuto() => {'type': 'auto'},
    ToolChoiceNone() => {'type': 'auto'},
    ToolChoiceRequired() => {'type': 'any'},
    ToolChoiceSpecific(:final toolName) => {'type': 'tool', 'name': toolName},
  };
}

LanguageModelV4FinishReason _mapAnthropicFinishReason(String? reason) {
  return switch (reason) {
    'end_turn' => LanguageModelV4FinishReason.stop,
    'max_tokens' => LanguageModelV4FinishReason.length,
    'tool_use' => LanguageModelV4FinishReason.toolCalls,
    'stop_sequence' => LanguageModelV4FinishReason.stop,
    null => LanguageModelV4FinishReason.unknown,
    _ => LanguageModelV4FinishReason.other,
  };
}

Stream<String> _readSseDataLines(Stream<Uint8List> bytesStream) async* {
  final lines = bytesStream
      .map<List<int>>((chunk) => chunk)
      .transform(utf8.decoder)
      .transform(const LineSplitter());
  await for (final line in lines) {
    if (!line.startsWith('data:')) continue;
    final payload = line.substring(5).trim();
    if (payload.isEmpty) continue;
    yield payload;
  }
}

Map<String, dynamic>? _safeParseMap(String input) {
  final parsed = _safeParseJson(input);
  return parsed is Map<String, dynamic> ? parsed : null;
}

Object _safeParseJson(String input) {
  try {
    return jsonDecode(input);
  } catch (_) {
    return input;
  }
}

int? _intOrNull(Object? value) => switch (value) {
  int v => v,
  num v => v.toInt(),
  String v => int.tryParse(v),
  _ => null,
};

/// Builds a [LanguageModelV4Usage] from an Anthropic `usage` object, mapping
/// the prompt-cache token fields into nested V4 input token usage fields.
///
/// Anthropic reports cache tokens *separately* from `input_tokens` (unlike
/// OpenAI/Google, where cached tokens are a subset of the prompt count), so
/// the reported [LanguageModelV4InputTokenUsage.total] is the sum of the fresh
/// input, cache-read, and cache-creation tokens. When the response carries no
/// cache fields the total collapses back to `input_tokens`, preserving prior
/// behaviour while leaving the cache breakdown unset.
///
/// [previous] carries usage forward across streaming events: `message_start`
/// reports the input/cache breakdown while later `message_delta` events report
/// only `output_tokens`.
LanguageModelV4Usage _anthropicUsageFrom(
  Map<String, dynamic> usage, {
  LanguageModelV4Usage? previous,
}) {
  final inputTokens = _intOrNull(usage['input_tokens']);
  final outputTokens = _intOrNull(usage['output_tokens']);
  final cacheRead = _intOrNull(usage['cache_read_input_tokens']);
  final cacheWrite = _intOrNull(usage['cache_creation_input_tokens']);
  final hasCache = cacheRead != null || cacheWrite != null;

  final int? totalInput;
  if (inputTokens != null || hasCache) {
    totalInput = (inputTokens ?? 0) + (cacheRead ?? 0) + (cacheWrite ?? 0);
  } else {
    totalInput = previous?.inputTokens.total;
  }

  return LanguageModelV4Usage(
    inputTokens: LanguageModelV4InputTokenUsage(
      total: totalInput,
      noCache: hasCache ? inputTokens : previous?.inputTokens.noCache,
      cacheRead: hasCache ? cacheRead : previous?.inputTokens.cacheRead,
      cacheWrite: hasCache ? cacheWrite : previous?.inputTokens.cacheWrite,
    ),
    outputTokens: LanguageModelV4OutputTokenUsage(
      total: outputTokens ?? previous?.outputTokens.total,
    ),
    raw: usage,
  );
}

String _generateId(String prefix) {
  final micros = DateTime.now().microsecondsSinceEpoch;
  return '$prefix-$micros';
}

Map<String, dynamic>? _toAnthropicImagePart(LanguageModelV4ImagePart part) {
  if (part.image is DataContentUrl) {
    return {
      'type': 'image',
      'source': {
        'type': 'url',
        'url': (part.image as DataContentUrl).url.toString(),
      },
    };
  }

  final b64 = _toBase64(part.image);
  if (b64 == null) return null;
  return {
    'type': 'image',
    'source': {
      'type': 'base64',
      'media_type': part.mediaType ?? 'image/png',
      'data': b64,
    },
  };
}

Map<String, dynamic>? _toAnthropicFilePart(LanguageModelV4FilePart part) {
  if (part.mediaType.startsWith('image/')) {
    return _toAnthropicImagePart(
      LanguageModelV4ImagePart(image: part.data, mediaType: part.mediaType),
    );
  }

  if (part.data is DataContentUrl) {
    return {
      'type': 'document',
      'source': {
        'type': 'url',
        'url': (part.data as DataContentUrl).url.toString(),
      },
      if (part.filename != null) 'title': part.filename,
    };
  }

  final b64 = _toBase64(part.data);
  if (b64 == null) return null;
  return {
    'type': 'document',
    'source': {'type': 'base64', 'media_type': part.mediaType, 'data': b64},
    if (part.filename != null) 'title': part.filename,
  };
}

Object _toAnthropicToolResultContent(LanguageModelV4ToolResultOutput output) {
  if (output is ToolResultOutputText) return output.text;
  if (output is! ToolResultOutputContent) return '';
  return output.parts.map(_toAnthropicToolResultPart).toList();
}

Map<String, dynamic> _toAnthropicToolResultPart(
  LanguageModelV4ContentPart part,
) {
  if (part is LanguageModelV4TextPart) {
    return {'type': 'text', 'text': part.text};
  }

  if (part is LanguageModelV4ImagePart) {
    final image = _toAnthropicImagePart(part);
    if (image != null) return image;
  }

  if (part is LanguageModelV4FilePart) {
    final file = _toAnthropicFilePart(part);
    if (file != null) return file;
  }

  return {'type': 'text', 'text': '[unsupported tool result content]'};
}

String? _toBase64(LanguageModelV4DataContent data) {
  return switch (data) {
    DataContentBytes(:final bytes) => base64Encode(bytes),
    DataContentBase64(:final base64) => base64,
    // Required for switch exhaustiveness over the sealed data-content type, but
    // unreachable in practice: both call sites (`_toAnthropicImagePart` and
    // `_toAnthropicFilePart`) handle `DataContentUrl` before reaching here.
    DataContentUrl() => null, // coverage:ignore-line
  };
}

Map<String, dynamic> _toAnthropicTool(LanguageModelV4Tool tool) =>
    switch (tool) {
      LanguageModelV4FunctionTool() => {
        'name': tool.name,
        if (tool.description != null) 'description': tool.description,
        'input_schema': tool.inputSchema,
        if (tool.inputExamples case final examples? when examples.isNotEmpty)
          'input_examples': examples,
      },
      LanguageModelV4ProviderDefinedTool() => {
        'type': tool.id.split('.').last,
        'name': tool.name,
        if (tool.description != null) 'description': tool.description,
        ...tool.args,
      },
    };

List<LanguageModelV4Warning> _readWarnings(Object? warningsRaw) {
  if (warningsRaw is! List) {
    return const [];
  }

  return warningsRaw
      .map(_parseWarning)
      .whereType<LanguageModelV4Warning>()
      .toList(growable: false);
}

LanguageModelV4Warning? _parseWarning(Object? item) {
  if (item == null) return null;
  if (item is String) {
    return item.isEmpty ? null : LanguageModelV4OtherWarning(message: item);
  }
  if (item is Map) {
    final map = item.cast<Object?, Object?>();
    final type = map['type']?.toString();
    final feature = map['feature']?.toString();
    final details = map['details']?.toString();
    return switch (type) {
      'unsupported' when feature != null => LanguageModelV4UnsupportedWarning(
        feature: feature,
        details: details,
      ),
      'compatibility' when feature != null =>
        LanguageModelV4CompatibilityWarning(feature: feature, details: details),
      'deprecated' when feature != null => LanguageModelV4DeprecatedWarning(
        setting: feature,
        message: details ?? 'This setting is deprecated.',
      ),
      'other' => LanguageModelV4OtherWarning(
        message: map['message']?.toString() ?? jsonEncode(item),
      ),
      _ => LanguageModelV4OtherWarning(message: jsonEncode(item)),
    };
  }
  final text = item.toString();
  return text.isEmpty ? null : LanguageModelV4OtherWarning(message: text);
}

class _ToolState {
  _ToolState({required this.id, required this.name});

  final String id;
  final String name;
  final StringBuffer argumentsBuffer = StringBuffer();
}

class _ReasoningState {
  _ReasoningState({required this.id});

  final String id;
}

/// Extracts the `thinking` configuration from raw [providerOptions].
///
/// Handles the following sources (in order of precedence):
/// 1. A `'thinking'` key whose value is already a Map (e.g. from
///    [AnthropicThinkingOptions.toMap]).
/// 2. A legacy `'speed'` key set to `'fast'` → `{type: disabled}`.
///
/// Returns the thinking map (or `null`) plus a cleaned copy of [po] with the
/// handled keys removed.
(Map<String, dynamic>?, Map<String, dynamic>?) _extractThinkingOptions(
  Map<String, dynamic>? po,
) {
  if (po == null) return (null, null);

  Map<String, dynamic>? thinking;
  final cleaned = Map<String, dynamic>.from(po);

  if (po['thinking'] is Map) {
    thinking = (po['thinking'] as Map).cast<String, dynamic>();
    cleaned.remove('thinking');
  } else if (po['speed'] == 'fast') {
    thinking = {'type': 'disabled'};
    cleaned.remove('speed');
  }

  return (thinking, cleaned.isEmpty ? null : cleaned);
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
