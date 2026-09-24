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
    final cancellation = DioCancellationScope(options.abortSignal);
    late final Map<String, String> resolvedHeaders;
    try {
      resolvedHeaders = await runWithAbortSignal(
        () async => await headers(),
        options.abortSignal,
      );
    } catch (_) {
      await cancellation.dispose();
      rethrow;
    }
    if (options.abortSignal?.isCancelled == true) {
      await cancellation.dispose();
      throw const AiOperationCancelledError();
    }
    final po = options.providerOptions != null
        ? options.providerOptions![provider]
        : null;
    var (thinking, cacheControl, effort, cleanedPo) = _extractAnthropicOptions(
      po,
    );
    if (effort == null) {
      final mapped = _anthropicReasoning(
        options.reasoning,
        modelId: modelId,
        maxOutputTokens: options.maxOutputTokens,
      );
      if (mapped != null) {
        if (thinking == null) thinking = mapped.thinking;
        effort = mapped.effort;
      }
    }
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
      'cache_control': ?cacheControl,
      ..._anthropicOutputConfig(options.responseFormat, effort: effort),
      ...?cleanedPo,
    };
    final Response<Map<String, dynamic>> response;
    try {
      response = await client.post<Map<String, dynamic>>(
        '/messages',
        data: requestBody,
        options: Options(headers: {...?options.headers, ...resolvedHeaders}),
        cancelToken: cancellation.token,
      );
    } on DioException catch (e) {
      await cancellation.dispose();
      throw await apiErrorFromDioException(e, provider: provider);
    }
    await cancellation.dispose();

    final data = response.data;
    if (data == null) throw _invalidResponse(response);
    try {
      final rawContent = data['content'];
      if (rawContent is List) {
        for (final item in rawContent) {
          if (item is! Map) throw StateError('content item is not an object');
          final citations = item['citations'];
          if (citations is List && citations.any((item) => item is! Map)) {
            throw StateError('citation item is not an object');
          }
          if (citations != null && citations is! List) {
            throw StateError('citations are not a list');
          }
        }
      } else if (rawContent != null) {
        throw StateError('content is not a list');
      }
      final usage = data['usage'];
      if (usage != null && usage is! Map) {
        throw StateError('usage is not an object');
      }
    } on Object catch (error) {
      throw _invalidResponse(response, error);
    }
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
            toolCallId: map['id']?.toString() ?? prefixedId('tool'),
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
    final cancellation = DioCancellationScope(options.abortSignal);
    late final Map<String, String> resolvedHeaders;
    try {
      resolvedHeaders = await runWithAbortSignal(
        () async => await headers(),
        options.abortSignal,
      );
    } catch (_) {
      await cancellation.dispose();
      rethrow;
    }
    if (options.abortSignal?.isCancelled == true) {
      await cancellation.dispose();
      throw const AiOperationCancelledError();
    }
    final po = options.providerOptions != null
        ? options.providerOptions![provider]
        : null;
    var (thinking, cacheControl, effort, cleanedPo) = _extractAnthropicOptions(
      po,
    );
    if (effort == null) {
      final mapped = _anthropicReasoning(
        options.reasoning,
        modelId: modelId,
        maxOutputTokens: options.maxOutputTokens,
      );
      if (mapped != null) {
        if (thinking == null) thinking = mapped.thinking;
        effort = mapped.effort;
      }
    }
    final requestBody = {
      'model': modelId,
      'max_tokens': options.maxOutputTokens ?? 1024,
      'system': options.prompt.system,
      'messages': _toAnthropicMessages(options.prompt),
      'stream': true,
      if (options.temperature != null) 'temperature': options.temperature,
      if (options.topP != null) 'top_p': options.topP,
      if (options.stopSequences.isNotEmpty)
        'stop_sequences': options.stopSequences,
      if (options.tools.isNotEmpty)
        'tools': options.tools.map(_toAnthropicTool).toList(),
      if (options.toolChoice != null)
        'tool_choice': _toAnthropicToolChoice(options.toolChoice!),
      'thinking': ?thinking,
      'cache_control': ?cacheControl,
      ..._anthropicOutputConfig(options.responseFormat, effort: effort),
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
        cancelToken: cancellation.token,
      );
    } on DioException catch (e) {
      await cancellation.dispose();
      throw await apiErrorFromDioException(e, provider: provider);
    }

    final body = response.data;
    // Defensive: Dio always supplies a ResponseBody for a successful streamed
    // response, so this guard is unreachable under normal operation.
    // coverage:ignore-start
    if (body == null) {
      await cancellation.dispose();
      throw StateError('Anthropic stream response body is null.');
    }
    // coverage:ignore-end

    final controller = StreamController<LanguageModelV4StreamPart>();
    controller.onCancel = () async {
      final token = cancellation.token;
      if (token != null && !token.isCancelled) {
        token.cancel('stream subscription cancelled');
      }
      await cancellation.dispose();
    };
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
        await for (final dataLine in sseDataLines(body.stream)) {
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
              final index = intOrNull(json['index']) ?? 0;
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
                final id = block['id']?.toString() ?? prefixedId('tool');
                final name = block['name']?.toString() ?? 'unknown_tool';
                toolState[index] = _ToolState(id: id, name: name);
                controller.add(
                  StreamPartToolInputStart(id: id, toolName: name),
                );
              } else if (blockType == 'thinking') {
                final id = block['id']?.toString() ?? 'reasoning-$index';
                reasoningState[index] = _ReasoningState(id: id);
                controller.add(StreamPartReasoningStart(id: id));
              } else if (blockType == 'redacted_thinking') {
                final id = block['id']?.toString() ?? 'reasoning-$index';
                reasoningState[index] = _ReasoningState(id: id);
                final redacted = block['data']?.toString();
                controller.add(
                  StreamPartReasoningStart(
                    id: id,
                    providerMetadata: redacted == null || redacted.isEmpty
                        ? null
                        : {
                            provider: {'redactedData': redacted},
                          },
                  ),
                );
              }
              break;
            case 'content_block_delta':
              final index = intOrNull(json['index']) ?? 0;
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
              } else if (deltaType == 'signature_delta') {
                final signature = delta['signature']?.toString();
                if (signature != null && signature.isNotEmpty) {
                  final state = reasoningState[index];
                  if (state != null) {
                    state.signature = '${state.signature ?? ''}$signature';
                  }
                }
              }
              break;
            case 'content_block_stop':
              final index = intOrNull(json['index']) ?? 0;
              final state = toolState.remove(index);
              if (state != null) {
                controller.add(StreamPartToolInputEnd(id: state.id));
                controller.add(
                  StreamPartToolCall(
                    toolCall: LanguageModelV4ToolCallPart(
                      toolCallId: state.id,
                      toolName: state.name,
                      input: safeParseJson(state.argumentsBuffer.toString()),
                    ),
                  ),
                );
              }
              final reasoning = reasoningState.remove(index);
              if (reasoning != null) {
                controller.add(
                  StreamPartReasoningEnd(
                    id: reasoning.id,
                    signature: reasoning.signature,
                    providerMetadata: reasoning.signature == null
                        ? null
                        : {
                            provider: {'signature': reasoning.signature},
                          },
                  ),
                );
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
                        input: safeParseJson(state.argumentsBuffer.toString()),
                      ),
                    ),
                  );
                }
                toolState.clear();
                for (final state in reasoningState.values.toList()) {
                  controller.add(
                    StreamPartReasoningEnd(
                      id: state.id,
                      signature: state.signature,
                      providerMetadata: state.signature == null
                          ? null
                          : {
                              provider: {'signature': state.signature},
                            },
                    ),
                  );
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
        await cancellation.dispose();
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

Dio _anthropicDio({String? baseUrl}) => createProviderDio(
  baseUrl: baseUrl ?? 'https://api.anthropic.com/v1',
  headers: {
    'anthropic-version': '2023-06-01',
    'content-type': 'application/json',
  },
);

AiApiCallError _invalidResponse<T>(Response<T> response, [Object? cause]) =>
    AiApiCallError(
      'Anthropic returned an invalid 2xx response body.',
      statusCode: response.statusCode,
      url: response.requestOptions.uri.toString(),
      cause: cause,
    );

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
        contentParts.add(
          _withAnthropicCacheControl({
            'type': 'text',
            'text': part.text,
          }, part.providerOptions),
        );
      } else if (part is LanguageModelV4ImagePart) {
        final image = _toAnthropicImagePart(part);
        if (image != null) {
          contentParts.add(
            _withAnthropicCacheControl(image, part.providerOptions),
          );
        }
      } else if (part is LanguageModelV4FilePart) {
        final document = _toAnthropicFilePart(part);
        if (document != null) {
          contentParts.add(
            _withAnthropicCacheControl(document, part.providerOptions),
          );
        }
      } else if (part is LanguageModelV4ReasoningFilePart ||
          part is LanguageModelV4DocumentSourcePart) {
        throw UnsupportedError(
          'Anthropic cannot serialize ${part.runtimeType} in a prompt.',
        );
      } else if (part is LanguageModelV4ToolCallPart) {
        contentParts.add({
          'type': 'tool_use',
          'id': part.toolCallId,
          'name': part.toolName,
          'input': part.input,
        });
      } else if (part is LanguageModelV4ReasoningPart &&
          part.signature != null) {
        contentParts.add({
          'type': 'thinking',
          'thinking': part.text,
          'signature': part.signature,
        });
      } else if (part is LanguageModelV4RedactedReasoningPart) {
        contentParts.add({
          'type': 'redacted_thinking',
          'data': utf8.decode(part.data, allowMalformed: true),
        });
      } else if (part is LanguageModelV4ToolResultPart) {
        contentParts.add(
          _withAnthropicCacheControl({
            'type': 'tool_result',
            'tool_use_id': part.toolCallId,
            'content': _toAnthropicToolResultContent(part.output),
            'is_error': part.isError,
          }, part.providerOptions),
        );
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

Map<String, dynamic>? _safeParseMap(String input) {
  final parsed = safeParseJson(input);
  return parsed is Map<String, dynamic> ? parsed : null;
}

/// Builds a [LanguageModelV4Usage] from an Anthropic `usage` object, mapping
/// the prompt-cache token fields into nested V4 input token usage fields.
///
/// Anthropic reports cache tokens *separately* from `input_tokens` (unlike
/// OpenAI/Google, where cached tokens are a subset of the prompt count), so
/// the reported [LanguageModelV4InputTokenUsage.total] is the sum of the fresh
/// input, cache-read, and cache-creation tokens. When the response carries no
/// cache fields the total collapses back to `input_tokens`. For a later stream
/// update, that value is reported as uncached input while stale cache fields
/// are cleared; an initial response leaves the breakdown unset.
///
/// [previous] carries usage forward across streaming events: `message_start`
/// reports the input/cache breakdown while later `message_delta` events report
/// only `output_tokens`.
LanguageModelV4Usage _anthropicUsageFrom(
  Map<String, dynamic> usage, {
  LanguageModelV4Usage? previous,
}) {
  final inputTokens = intOrNull(usage['input_tokens']);
  final outputTokens = intOrNull(usage['output_tokens']);
  final cacheRead = intOrNull(usage['cache_read_input_tokens']);
  final cacheWrite = intOrNull(usage['cache_creation_input_tokens']);
  final hasCache = cacheRead != null || cacheWrite != null;

  final int? totalInput;
  final int? noCache;
  final int? effectiveCacheRead;
  final int? effectiveCacheWrite;
  if (inputTokens != null) {
    totalInput = inputTokens + (cacheRead ?? 0) + (cacheWrite ?? 0);
    noCache = hasCache || previous != null ? inputTokens : null;
    effectiveCacheRead = cacheRead;
    effectiveCacheWrite = cacheWrite;
  } else if (hasCache) {
    totalInput = (cacheRead ?? 0) + (cacheWrite ?? 0);
    noCache = null;
    effectiveCacheRead = cacheRead;
    effectiveCacheWrite = cacheWrite;
  } else {
    totalInput = previous?.inputTokens.total;
    noCache = previous?.inputTokens.noCache;
    effectiveCacheRead = previous?.inputTokens.cacheRead;
    effectiveCacheWrite = previous?.inputTokens.cacheWrite;
  }

  return LanguageModelV4Usage(
    inputTokens: LanguageModelV4InputTokenUsage(
      total: totalInput,
      noCache: noCache,
      cacheRead: effectiveCacheRead,
      cacheWrite: effectiveCacheWrite,
    ),
    outputTokens: LanguageModelV4OutputTokenUsage(
      total: outputTokens ?? previous?.outputTokens.total,
    ),
    raw: usage,
  );
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

  final b64 = dataContentToBase64(part.image);
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

  final b64 = dataContentToBase64(part.data);
  if (b64 == null) return null;
  return {
    'type': 'document',
    'source': {'type': 'base64', 'media_type': part.mediaType, 'data': b64},
    if (part.filename != null) 'title': part.filename,
  };
}

Object _toAnthropicToolResultContent(LanguageModelV4ToolResultOutput output) {
  if (output is ToolResultOutputText) return output.text;
  if (output is ToolResultOutputErrorText) return output.text;
  if (output is ToolResultOutputJson) return jsonEncode(output.value);
  if (output is ToolResultOutputErrorJson) return jsonEncode(output.value);
  if (output is ToolResultOutputExecutionDenied) return output.reason;
  if (output is! ToolResultOutputContent) {
    throw UnsupportedError(
      'Anthropic cannot serialize ${output.runtimeType} tool result output.',
    );
  }
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

  throw UnsupportedError(
    'Anthropic cannot serialize ${part.runtimeType} tool result content.',
  );
}

Map<String, dynamic> _toAnthropicTool(LanguageModelV4Tool tool) =>
    switch (tool) {
      LanguageModelV4FunctionTool() => {
        'name': tool.name,
        if (tool.description != null) 'description': tool.description,
        'input_schema': tool.inputSchema,
        if (tool.inputExamples case final examples? when examples.isNotEmpty)
          'input_examples': examples,
        ..._anthropicCacheControlEntry(tool.providerOptions),
      },
      LanguageModelV4ProviderDefinedTool() => {
        'type': tool.id.split('.').last,
        'name': tool.name,
        if (tool.description != null) 'description': tool.description,
        ...tool.args,
      },
    };

Map<String, dynamic> _withAnthropicCacheControl(
  Map<String, dynamic> content,
  Map<String, dynamic>? providerOptions,
) {
  final cacheControl = _anthropicCacheControl(providerOptions);
  return cacheControl == null
      ? content
      : {...content, 'cache_control': cacheControl};
}

Map<String, dynamic> _anthropicCacheControlEntry(
  Map<String, dynamic>? providerOptions,
) {
  final cacheControl = _anthropicCacheControl(providerOptions);
  return cacheControl == null ? const {} : {'cache_control': cacheControl};
}

Map<String, dynamic>? _anthropicCacheControl(
  Map<String, dynamic>? providerOptions,
) {
  final options = providerOptions?['anthropic'];
  final value = options?['cacheControl'] ?? options?['cache_control'];
  return value is Map ? value.cast<String, dynamic>() : null;
}

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
  String? signature;
}

/// Extracts Anthropic-specific request options from raw [providerOptions].
///
/// Handles the following sources (in order of precedence):
/// 1. A `'thinking'` key whose value is already a Map (e.g. from
///    [AnthropicThinkingOptions.toMap]).
/// 2. A legacy `'speed'` key set to `'fast'` → `{type: disabled}`.
/// 3. A `'cache_control'` or `'cacheControl'` key whose value is a Map.
///
/// Returns the thinking map, cache control map, and a cleaned copy of [po]
/// with the handled keys removed.
(Map<String, dynamic>?, Map<String, dynamic>?, String?, Map<String, dynamic>?)
_extractAnthropicOptions(Map<String, dynamic>? po) {
  if (po == null) return (null, null, null, null);

  Map<String, dynamic>? thinking;
  Map<String, dynamic>? cacheControl;
  String? effort;
  final cleaned = Map<String, dynamic>.from(po);

  if (po['thinking'] is Map) {
    thinking = (po['thinking'] as Map).cast<String, dynamic>();
    cleaned.remove('thinking');
  } else if (po['speed'] == 'fast') {
    thinking = {'type': 'disabled'};
    cleaned.remove('speed');
  }

  final rawCacheControl = po['cache_control'] ?? po['cacheControl'];
  if (rawCacheControl is Map) {
    cacheControl = rawCacheControl.cast<String, dynamic>();
    cleaned
      ..remove('cache_control')
      ..remove('cacheControl');
  }

  if (po['effort'] is String) {
    effort = po['effort'] as String;
    cleaned.remove('effort');
  }

  return (thinking, cacheControl, effort, cleaned.isEmpty ? null : cleaned);
}

Map<String, dynamic> _anthropicOutputConfig(
  LanguageModelV4ResponseFormat? responseFormat, {
  String? effort,
}) {
  if (responseFormat case final LanguageModelV4JsonResponseFormat format
      when format.schema != null) {
    return {
      'output_config': {
        if (effort != null) 'effort': effort,
        'format': {'type': 'json_schema', 'schema': format.schema},
      },
    };
  }
  return effort == null
      ? const {}
      : {
          'output_config': {'effort': effort},
        };
}

({Map<String, dynamic>? thinking, String? effort})? _anthropicReasoning(
  LanguageModelV4Reasoning reasoning, {
  required String modelId,
  required int? maxOutputTokens,
}) {
  if (reasoning == LanguageModelV4Reasoning.providerDefault) return null;
  final lower = modelId.toLowerCase();
  final adaptive =
      lower.contains('claude-') &&
      !lower.contains('claude-3') &&
      !lower.contains('claude-2') &&
      !lower.contains('claude-instant');
  if (reasoning == LanguageModelV4Reasoning.none) {
    return adaptive
        ? (thinking: null, effort: 'low')
        : (thinking: {'type': 'disabled'}, effort: null);
  }
  if (adaptive) {
    final effort = switch (reasoning) {
      LanguageModelV4Reasoning.minimal || LanguageModelV4Reasoning.low => 'low',
      LanguageModelV4Reasoning.medium => 'medium',
      LanguageModelV4Reasoning.high => 'high',
      LanguageModelV4Reasoning.xhigh => 'max',
      LanguageModelV4Reasoning.providerDefault ||
      LanguageModelV4Reasoning.none => null,
    };
    return (thinking: {'type': 'adaptive'}, effort: effort);
  }
  final maximum = maxOutputTokens ?? 4096;
  final fraction = switch (reasoning) {
    LanguageModelV4Reasoning.minimal => 0.02,
    LanguageModelV4Reasoning.low => 0.10,
    LanguageModelV4Reasoning.medium => 0.30,
    LanguageModelV4Reasoning.high => 0.60,
    LanguageModelV4Reasoning.xhigh => 0.90,
    LanguageModelV4Reasoning.providerDefault ||
    LanguageModelV4Reasoning.none => 0,
  };
  return (
    thinking: {
      'type': 'enabled',
      'budget_tokens': (maximum * fraction).round().clamp(1024, maximum),
    },
    effort: null,
  );
}

/// Maps a [DioException] from a non-2xx response to a typed [AiApiCallError]
/// carrying the provider's message/status/code. Drains a streamed error body
/// (`ResponseType.stream`) when present so the message is recoverable.
