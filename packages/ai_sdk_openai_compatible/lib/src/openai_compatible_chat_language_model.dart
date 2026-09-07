import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';

import 'api_error.dart';
import 'openai_compatible_config.dart';

/// A [LanguageModelV4] implementing the full OpenAI Chat Completions wire
/// format, parameterized for per-provider quirks via [OpenAICompatibleConfig].
///
/// Owns: multimodal message building (text + image + audio + file), `tools` /
/// `tool_choice` serialization (with `strict`), `response_format` JSON-schema,
/// SSE streaming (text deltas + an index-based tool-call delta state machine +
/// finish + usage), non-streaming tool-call parsing, and finish-reason mapping.
///
/// Providers wrap this behind their own factory; see `ai_sdk_groq`,
/// `ai_sdk_azure`, `ai_sdk_mistral`, and `ai_sdk_openai`.
class OpenAICompatibleChatLanguageModel extends LanguageModelV4 {
  /// Creates a model for [modelId] driven by [config].
  const OpenAICompatibleChatLanguageModel({
    required this.config,
    required this.modelId,
  });

  /// Per-provider configuration (auth, base URL, field names, feature flags).
  final OpenAICompatibleConfig config;

  @override
  final String modelId;

  @override
  String get provider => config.provider;

  @override
  String get specificationVersion => 'v4';

  Future<Map<String, String>> _resolvedHeaders() async {
    final headers = await config.headers();
    return Map<String, String>.unmodifiable(headers);
  }

  Options _requestOptions(
    Map<String, String> headers,
    LanguageModelV4CallOptions options, {
    ResponseType? responseType,
  }) {
    return Options(
      responseType: responseType,
      headers: {...?options.headers, ...headers},
    );
  }

  Map<String, dynamic> _buildBody(
    LanguageModelV4CallOptions options, {
    required bool stream,
  }) {
    final body = <String, dynamic>{
      'model': modelId,
      'messages': _toMessages(options.prompt),
      if (stream) 'stream': true,
      if (stream && config.includeStreamUsageOption)
        'stream_options': {'include_usage': true},
      if (config.supportsTools && options.tools.isNotEmpty)
        'tools': options.tools.map(_toToolJson).toList(),
      if (config.supportsTools && options.toolChoice != null)
        'tool_choice': _toToolChoice(options.toolChoice!),
      if (options.maxOutputTokens != null)
        config.maxTokensKey: options.maxOutputTokens,
      if (options.temperature != null) 'temperature': options.temperature,
      if (options.topP != null) 'top_p': options.topP,
      if (options.presencePenalty != null)
        'presence_penalty': options.presencePenalty,
      if (options.frequencyPenalty != null)
        'frequency_penalty': options.frequencyPenalty,
      if (options.stopSequences.isNotEmpty) 'stop': options.stopSequences,
      if (options.seed != null) config.seedKey: options.seed,
    };

    final responseFormat = options.responseFormat;
    if (config.supportsResponseFormatJsonSchema &&
        responseFormat is LanguageModelV4JsonResponseFormat) {
      body['response_format'] = {
        'type': 'json_schema',
        'json_schema': {
          'name': responseFormat.name ?? 'response',
          'schema': responseFormat.schema,
          if (responseFormat.description != null)
            'description': responseFormat.description,
          'strict': true,
        },
      };
    }

    final extra = config.extraBody?.call(options);
    if (extra != null) {
      body.addAll(extra);
    }
    return body;
  }

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    final headers = await _resolvedHeaders();
    final requestBody = _buildBody(options, stream: false);
    final cancelToken = _cancelTokenFor(options.abortSignal);
    final Response<Map<String, dynamic>> response;
    try {
      response = await config.client.post<Map<String, dynamic>>(
        providerEndpoint(config.baseUrl, '/chat/completions'),
        data: requestBody,
        queryParameters: config.queryParameters,
        options: _requestOptions(headers, options),
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      throw await apiErrorFromDioException(e, provider: provider);
    }

    final data = response.data ?? <String, dynamic>{};
    final choices = (data['choices'] as List?) ?? const [];
    final firstChoice = choices.isNotEmpty
        ? (choices.first as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    final message =
        (firstChoice['message'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};

    final content = <LanguageModelV4ContentPart>[];
    final reasoning = _extractReasoning(message);
    if (reasoning != null) {
      content.add(LanguageModelV4ReasoningPart(text: reasoning));
    }

    final text = message['content'];
    if (text is String && text.isNotEmpty) {
      content.add(LanguageModelV4TextPart(text: text));
    }

    final toolCalls = (message['tool_calls'] as List?) ?? const [];
    for (final call in toolCalls) {
      final callMap = (call as Map).cast<String, dynamic>();
      final function =
          (callMap['function'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      final rawInput = function['arguments']?.toString() ?? '{}';
      content.add(
        LanguageModelV4ToolCallPart(
          toolCallId: callMap['id']?.toString() ?? _generateId('call'),
          toolName: function['name']?.toString() ?? 'unknown_tool',
          input: _safeParseJson(rawInput),
        ),
      );
    }

    _appendAnnotationParts(
      (message['annotations'] as List?) ?? const [],
      onSource: content.add,
      onFile: content.add,
    );

    final usageMap = (data['usage'] as Map?)?.cast<String, dynamic>();
    final warnings = _readWarnings(data['warnings']);
    return LanguageModelV4GenerateResult(
      content: content,
      finishReason: _mapFinishReason(firstChoice['finish_reason']?.toString()),
      rawFinishReason: firstChoice['finish_reason']?.toString(),
      usage: usageMap == null ? null : _usageFrom(usageMap),
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
    final headers = await _resolvedHeaders();
    final requestBody = _buildBody(options, stream: true);
    final cancelToken = _cancelTokenFor(options.abortSignal);
    final Response<ResponseBody> response;
    try {
      response = await config.client.post<ResponseBody>(
        providerEndpoint(config.baseUrl, '/chat/completions'),
        data: requestBody,
        queryParameters: config.queryParameters,
        options: _requestOptions(
          headers,
          options,
          responseType: ResponseType.stream,
        ),
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      throw await apiErrorFromDioException(e, provider: provider);
    }

    final body = response.data;
    if (body == null) {
      throw StateError('$provider stream response body is null.');
    }

    final controller = StreamController<LanguageModelV4StreamPart>();
    final toolState = <int, _ToolStreamState>{};
    var textStarted = false;
    var reasoningStarted = false;
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
          if (dataLine == '[DONE]') {
            break;
          }

          final json = _safeParseJsonMap(dataLine);
          if (json == null) {
            continue;
          }
          lastChunk = json;
          responseId ??= json['id']?.toString();
          responseModel ??= json['model']?.toString();
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
          final usageMap = (json['usage'] as Map?)?.cast<String, dynamic>();
          if (usageMap != null) {
            streamUsage = _usageFrom(usageMap);
          }

          final choices = (json['choices'] as List?) ?? const [];
          if (choices.isEmpty) continue;
          final choice = (choices.first as Map).cast<String, dynamic>();

          final delta =
              (choice['delta'] as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{};

          // Reasoning/thinking precedes visible output; emit it first so the
          // consumer's reasoning span opens before any text/tool deltas.
          final reasoningDelta = _extractReasoning(delta);
          if (reasoningDelta != null) {
            if (!reasoningStarted) {
              reasoningStarted = true;
              controller.add(const StreamPartReasoningStart(id: 'reasoning-0'));
            }
            controller.add(
              StreamPartReasoningDelta(
                id: 'reasoning-0',
                delta: reasoningDelta,
              ),
            );
          }

          _appendAnnotationParts(
            (delta['annotations'] as List?) ?? const [],
            onSource: (part) => controller.add(StreamPartSource(source: part)),
            onFile: (part) => controller.add(StreamPartFile(file: part)),
          );

          final textDelta = delta['content'];
          if (textDelta is String && textDelta.isNotEmpty) {
            if (!textStarted) {
              textStarted = true;
              controller.add(const StreamPartTextStart(id: 'text-0'));
            }
            controller.add(StreamPartTextDelta(id: 'text-0', delta: textDelta));
          }

          final toolCalls = (delta['tool_calls'] as List?) ?? const [];
          for (final rawToolCall in toolCalls) {
            final call = (rawToolCall as Map).cast<String, dynamic>();
            final index = _intOrNull(call['index']) ?? 0;
            final function =
                (call['function'] as Map?)?.cast<String, dynamic>() ??
                <String, dynamic>{};

            final state = toolState.putIfAbsent(index, () {
              final id = call['id']?.toString() ?? _generateId('tool');
              final name = function['name']?.toString() ?? 'unknown_tool';
              controller.add(StreamPartToolInputStart(id: id, toolName: name));
              return _ToolStreamState(id: id, name: name);
            });

            if (function['name'] != null) {
              state.name = function['name'].toString();
            }
            final argDelta = function['arguments'];
            if (argDelta is String && argDelta.isNotEmpty) {
              state.argumentsBuffer.write(argDelta);
              controller.add(
                StreamPartToolInputDelta(id: state.id, delta: argDelta),
              );
            }
          }

          final finishReason = choice['finish_reason']?.toString();
          if (finishReason != null) {
            if (textStarted) {
              controller.add(const StreamPartTextEnd(id: 'text-0'));
            }
            if (reasoningStarted) {
              controller.add(const StreamPartReasoningEnd(id: 'reasoning-0'));
            }
            for (final state in toolState.values) {
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
                finishReason: _mapFinishReason(finishReason),
                rawFinishReason: finishReason,
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

  // ── message building ──────────────────────────────────────────────────

  List<Map<String, dynamic>> _toMessages(LanguageModelV4Prompt prompt) {
    final out = <Map<String, dynamic>>[];
    if (prompt.system != null && prompt.system!.isNotEmpty) {
      out.add({'role': 'system', 'content': prompt.system});
    }

    for (final message in prompt.messages) {
      final role = switch (message.role) {
        LanguageModelV4Role.system => 'system',
        LanguageModelV4Role.user => 'user',
        LanguageModelV4Role.assistant => 'assistant',
        LanguageModelV4Role.tool => 'tool',
      };

      final text = message.content
          .whereType<LanguageModelV4TextPart>()
          .map((part) => part.text)
          .join('\n');

      final toolCalls = message.content
          .whereType<LanguageModelV4ToolCallPart>()
          .map(
            (tool) => {
              'id': tool.toolCallId,
              'type': 'function',
              'function': {
                'name': tool.toolName,
                'arguments': jsonEncode(tool.input),
              },
            },
          )
          .toList();

      if (role == 'tool') {
        final toolParts = message.content
            .whereType<LanguageModelV4ToolResultPart>();
        for (final toolPart in toolParts) {
          out.add({
            'role': 'tool',
            'tool_call_id': toolPart.toolCallId,
            'content': _toToolResultText(toolPart),
          });
        }
        if (toolParts.isNotEmpty) continue;
      }

      if (role == 'assistant' && toolCalls.isNotEmpty) {
        out.add({
          'role': role,
          'content': text.isEmpty ? null : text,
          'tool_calls': toolCalls,
        });
        continue;
      }

      if (config.supportsMultimodal) {
        final contentParts = _toContentParts(message.content);
        if (contentParts.isNotEmpty) {
          out.add({'role': role, 'content': contentParts});
          continue;
        }
      }

      out.add({'role': role, 'content': text});
    }

    return out;
  }

  List<Map<String, dynamic>> _toContentParts(
    List<LanguageModelV4ContentPart> parts,
  ) {
    final out = <Map<String, dynamic>>[];
    for (final part in parts) {
      if (part is LanguageModelV4TextPart) {
        out.add({'type': 'text', 'text': part.text});
        continue;
      }
      if (part is LanguageModelV4ImagePart) {
        final imageUrl = _toImageUrl(part.image, part.mediaType);
        if (imageUrl != null) {
          out.add({
            'type': 'image_url',
            'image_url': {'url': imageUrl},
          });
        }
        continue;
      }
      if (part is LanguageModelV4FilePart &&
          part.mediaType.startsWith('audio/')) {
        final audioData = _toBase64(part.data);
        if (audioData != null) {
          out.add({
            'type': 'input_audio',
            'input_audio': {
              'data': audioData,
              'format': part.mediaType.split('/').last,
            },
          });
        }
        continue;
      }
      if (part is LanguageModelV4FilePart &&
          part.mediaType.startsWith('image/')) {
        final imageUrl = _toImageUrl(part.data, part.mediaType);
        if (imageUrl != null) {
          out.add({
            'type': 'image_url',
            'image_url': {'url': imageUrl},
          });
        }
        continue;
      }
      if (part is LanguageModelV4FilePart) {
        final fileData = _toBase64(part.data);
        if (fileData != null) {
          out.add({
            'type': 'file',
            'file': {
              'file_data': 'data:${part.mediaType};base64,$fileData',
              if (part.filename != null) 'filename': part.filename,
            },
          });
        }
      }
    }
    return out;
  }

  // ── tool serialization ────────────────────────────────────────────────

  Map<String, dynamic> _toToolJson(LanguageModelV4Tool tool) => switch (tool) {
    LanguageModelV4FunctionTool() => {
      'type': 'function',
      'function': {
        'name': tool.name,
        if (tool.description != null) 'description': tool.description,
        'parameters': tool.inputSchema,
        if (tool.strict != null) 'strict': tool.strict,
      },
    },
    LanguageModelV4ProviderDefinedTool() => {
      'type': tool.id,
      'name': tool.name,
      if (tool.description != null) 'description': tool.description,
      ...tool.args,
    },
  };

  Object _toToolChoice(LanguageModelV4ToolChoice choice) {
    return switch (choice) {
      ToolChoiceAuto() => 'auto',
      ToolChoiceNone() => 'none',
      ToolChoiceRequired() => 'required',
      ToolChoiceSpecific(:final toolName) => {
        'type': 'function',
        'function': {'name': toolName},
      },
    };
  }

  // ── annotations → source/file parts ───────────────────────────────────

  void _appendAnnotationParts(
    List<Object?> annotations, {
    required void Function(LanguageModelV4SourcePart) onSource,
    required void Function(LanguageModelV4FilePart) onFile,
  }) {
    for (final (i, rawAnnotation) in annotations.indexed) {
      if (rawAnnotation is! Map) continue;
      final annotation = rawAnnotation.cast<String, dynamic>();
      final type = annotation['type']?.toString();
      if (type == 'url_citation') {
        final url = annotation['url']?.toString();
        if (url != null && url.isNotEmpty) {
          onSource(
            LanguageModelV4SourcePart(
              id: '${provider}_source_$i',
              url: url,
              title: annotation['title']?.toString(),
              providerMetadata: annotation,
            ),
          );
        }
      }
      if (type == 'file_citation') {
        final fileId = annotation['file_id']?.toString();
        if (fileId != null && fileId.isNotEmpty) {
          onFile(
            LanguageModelV4FilePart(
              data: DataContentUrl(Uri.parse('$provider://file/$fileId')),
              mediaType: 'application/octet-stream',
              filename: fileId,
            ),
          );
        }
      }
    }
  }

  // ── tool result serialization ─────────────────────────────────────────

  String _toToolResultText(LanguageModelV4ToolResultPart result) {
    if (result.output case ToolResultOutputText(
      :final text,
    ) when !result.isError) {
      return text;
    }
    return jsonEncode({
      'toolCallId': result.toolCallId,
      'toolName': result.toolName,
      'isError': result.isError,
      'output': _toToolResultOutputJson(result.output),
    });
  }

  Object _toToolResultOutputJson(LanguageModelV4ToolResultOutput output) {
    return switch (output) {
      ToolResultOutputText(:final text) => {'type': 'text', 'text': text},
      ToolResultOutputContent(:final parts) => {
        'type': 'content',
        'parts': parts.map(_toGenericContentPartJson).toList(),
      },
    };
  }

  Map<String, dynamic> _toGenericContentPartJson(
    LanguageModelV4ContentPart part,
  ) {
    if (part is LanguageModelV4TextPart) {
      return {'type': 'text', 'text': part.text};
    }
    if (part is LanguageModelV4ImagePart) {
      final data = _toBase64(part.image);
      return {
        'type': 'image',
        'mediaType': ?part.mediaType,
        if (part.image is DataContentUrl)
          'url': (part.image as DataContentUrl).url.toString(),
        'base64': ?data,
      };
    }
    if (part is LanguageModelV4FilePart) {
      return {
        'type': 'file',
        'mediaType': part.mediaType,
        if (part.filename != null) 'filename': part.filename,
        if (part.data is DataContentUrl)
          'url': (part.data as DataContentUrl).url.toString(),
        'base64': ?_toBase64(part.data),
      };
    }
    return {'type': 'unsupported'};
  }

  // ── reasoning / thinking extraction ───────────────────────────────────

  /// Returns the first non-empty reasoning string found in [source] under one
  /// of [OpenAICompatibleConfig.reasoningKeys], or `null` when none is present.
  ///
  /// Shared by the streaming `delta` and non-streaming `message` paths so both
  /// honor the same provider-specific field names.
  String? _extractReasoning(Map<String, dynamic> source) {
    for (final key in config.reasoningKeys) {
      final value = source[key];
      if (value is String && value.isNotEmpty) return value;
    }
    return null;
  }

  // ── finish reason ─────────────────────────────────────────────────────

  LanguageModelV4FinishReason _mapFinishReason(String? reason) {
    return switch (reason) {
      'stop' => LanguageModelV4FinishReason.stop,
      'length' => LanguageModelV4FinishReason.length,
      'content_filter' => LanguageModelV4FinishReason.contentFilter,
      'tool_calls' => LanguageModelV4FinishReason.toolCalls,
      'error' => LanguageModelV4FinishReason.error,
      null => LanguageModelV4FinishReason.unknown,
      _ => LanguageModelV4FinishReason.other,
    };
  }
}

// ── shared helpers ────────────────────────────────────────────────────────

LanguageModelV4Usage _usageFrom(Map<String, dynamic> usage) {
  final inputTokens = _intOrNull(usage['prompt_tokens']);
  // OpenAI's `prompt_tokens` already includes cache hits; `cached_tokens` is a
  // subset of it, so `total` stays as reported and the uncached remainder is
  // surfaced via `noCache`.
  final promptDetails = (usage['prompt_tokens_details'] as Map?)
      ?.cast<String, dynamic>();
  final cacheRead = _intOrNull(promptDetails?['cached_tokens']);
  return LanguageModelV4Usage(
    inputTokens: LanguageModelV4InputTokenUsage(
      total: inputTokens,
      noCache: cacheRead == null || inputTokens == null
          ? null
          : inputTokens - cacheRead,
      cacheRead: cacheRead,
    ),
    outputTokens: LanguageModelV4OutputTokenUsage(
      total: _intOrNull(usage['completion_tokens']),
    ),
  );
}

String? _toImageUrl(LanguageModelV4DataContent data, String? mediaType) {
  if (data is DataContentUrl) return data.url.toString();
  final b64 = _toBase64(data);
  if (b64 == null) return null;
  final resolvedMediaType = mediaType ?? 'image/png';
  return 'data:$resolvedMediaType;base64,$b64';
}

String? _toBase64(LanguageModelV4DataContent data) {
  return switch (data) {
    DataContentBytes(:final bytes) => base64Encode(bytes),
    DataContentBase64(:final base64) => base64,
    DataContentUrl() => null,
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

Map<String, dynamic>? _safeParseJsonMap(String input) {
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

String _generateId(String prefix) {
  final micros = DateTime.now().microsecondsSinceEpoch;
  return '$prefix-$micros';
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

LanguageModelV4Warning? _parseWarning(Object? item) {
  if (item == null) {
    return null;
  }
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

class _ToolStreamState {
  _ToolStreamState({required this.id, required this.name});

  final String id;
  String name;
  final StringBuffer argumentsBuffer = StringBuffer();
}
