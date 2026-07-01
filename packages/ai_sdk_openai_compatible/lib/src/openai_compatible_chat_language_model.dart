import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';

import 'api_error.dart';
import 'openai_compatible_config.dart';

/// A [LanguageModelV3] implementing the full OpenAI Chat Completions wire
/// format, parameterized for per-provider quirks via [OpenAICompatibleConfig].
///
/// Owns: multimodal message building (text + image + audio + file), `tools` /
/// `tool_choice` serialization (with `strict`), `response_format` JSON-schema,
/// SSE streaming (text deltas + an index-based tool-call delta state machine +
/// finish + usage), non-streaming tool-call parsing, and finish-reason mapping.
///
/// Providers wrap this behind their own factory; see `ai_sdk_groq`,
/// `ai_sdk_azure`, `ai_sdk_mistral`, and `ai_sdk_openai`.
class OpenAICompatibleChatLanguageModel implements LanguageModelV3 {
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
  String get specificationVersion => 'v3';

  Dio _client() =>
      config.clientFactory(baseUrl: config.baseUrl, headers: config.headers());

  Options _requestOptions(
    LanguageModelV3CallOptions options, {
    ResponseType? responseType,
  }) {
    return Options(responseType: responseType, headers: options.headers);
  }

  Map<String, dynamic> _buildBody(
    LanguageModelV3CallOptions options, {
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
      if (config.supportsResponseFormatJsonSchema &&
          options.outputSchema != null)
        'response_format': {
          'type': 'json_schema',
          'json_schema': {
            'name': 'response',
            'schema': options.outputSchema,
            'strict': true,
          },
        },
    };

    final extra = config.extraBody?.call(options);
    if (extra != null) {
      body.addAll(extra);
    }
    return body;
  }

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async {
    final client = _client();
    final requestBody = _buildBody(options, stream: false);
    final Response<Map<String, dynamic>> response;
    try {
      response = await client.post<Map<String, dynamic>>(
        '/chat/completions',
        data: requestBody,
        queryParameters: config.queryParameters,
        options: _requestOptions(options),
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

    final content = <LanguageModelV3ContentPart>[];
    final text = message['content'];
    if (text is String && text.isNotEmpty) {
      content.add(LanguageModelV3TextPart(text: text));
    }

    final toolCalls = (message['tool_calls'] as List?) ?? const [];
    for (final call in toolCalls) {
      final callMap = (call as Map).cast<String, dynamic>();
      final function =
          (callMap['function'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      final rawInput = function['arguments']?.toString() ?? '{}';
      content.add(
        LanguageModelV3ToolCallPart(
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
    return LanguageModelV3GenerateResult(
      content: content,
      finishReason: _mapFinishReason(firstChoice['finish_reason']?.toString()),
      rawFinishReason: firstChoice['finish_reason']?.toString(),
      usage: usageMap == null ? null : _usageFrom(usageMap),
      warnings: warnings,
      response: LanguageModelV3ResponseMetadata(
        id: data['id']?.toString(),
        modelId: data['model']?.toString() ?? modelId,
        timestamp: DateTime.now().toUtc(),
        headers: response.headers.map.map(
          (key, value) => MapEntry(key, value.join(',')),
        ),
        body: data,
        requestBody: requestBody,
      ),
    );
  }

  @override
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  ) async {
    final client = _client();
    final requestBody = _buildBody(options, stream: true);
    final Response<ResponseBody> response;
    try {
      response = await client.post<ResponseBody>(
        '/chat/completions',
        data: requestBody,
        queryParameters: config.queryParameters,
        options: _requestOptions(options, responseType: ResponseType.stream),
      );
    } on DioException catch (e) {
      throw await apiErrorFromDioException(e, provider: provider);
    }

    final body = response.data;
    if (body == null) {
      throw StateError('$provider stream response body is null.');
    }

    final controller = StreamController<LanguageModelV3StreamPart>();
    final toolState = <int, _ToolStreamState>{};
    var textStarted = false;
    LanguageModelV3Usage? streamUsage;
    final streamWarnings = <String>[];
    String? responseId;
    String? responseModel;
    Map<String, dynamic>? lastChunk;
    final rawResponse = <String, Object?>{
      'requestBody': requestBody,
      'statusCode': response.statusCode,
      'headers': response.headers.map.map(
        (key, value) => MapEntry(key, value.join(',')),
      ),
    };

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
              controller.add(
                StreamPartToolCallStart(toolCallId: id, toolName: name),
              );
              return _ToolStreamState(id: id, name: name);
            });

            if (function['name'] != null) {
              state.name = function['name'].toString();
            }
            final argDelta = function['arguments'];
            if (argDelta is String && argDelta.isNotEmpty) {
              state.argumentsBuffer.write(argDelta);
              controller.add(
                StreamPartToolCallDelta(
                  toolCallId: state.id,
                  toolName: state.name,
                  argsTextDelta: argDelta,
                ),
              );
            }
          }

          final finishReason = choice['finish_reason']?.toString();
          if (finishReason != null) {
            if (textStarted) {
              controller.add(const StreamPartTextEnd(id: 'text-0'));
            }
            for (final state in toolState.values) {
              controller.add(
                StreamPartToolCallEnd(
                  toolCallId: state.id,
                  toolName: state.name,
                  input: _safeParseJson(state.argumentsBuffer.toString()),
                ),
              );
            }
            controller.add(
              StreamPartFinish(
                finishReason: _mapFinishReason(finishReason),
                rawFinishReason: finishReason,
                usage: streamUsage,
                providerMetadata: {
                  provider: {
                    if (responseId != null) 'id': responseId,
                    if (responseModel != null) 'model': responseModel,
                    'timestamp': DateTime.now().toUtc().toIso8601String(),
                    if (streamWarnings.isNotEmpty) 'warnings': streamWarnings,
                  },
                },
              ),
            );
          }

          rawResponse['responseMetadata'] = {
            if (responseId != null) 'id': responseId,
            if (responseModel != null) 'modelId': responseModel,
            'timestamp': DateTime.now().toUtc().toIso8601String(),
          };
          rawResponse['warnings'] = List<String>.from(streamWarnings);
          rawResponse['body'] = lastChunk;
        }
      } catch (error) {
        controller.add(StreamPartError(error: error));
      } finally {
        await controller.close();
      }
    }());

    return LanguageModelV3StreamResult(
      stream: controller.stream,
      rawResponse: rawResponse,
    );
  }

  // ── message building ──────────────────────────────────────────────────

  List<Map<String, dynamic>> _toMessages(LanguageModelV3Prompt prompt) {
    final out = <Map<String, dynamic>>[];
    if (prompt.system != null && prompt.system!.isNotEmpty) {
      out.add({'role': 'system', 'content': prompt.system});
    }

    for (final message in prompt.messages) {
      final role = switch (message.role) {
        LanguageModelV3Role.system => 'system',
        LanguageModelV3Role.user => 'user',
        LanguageModelV3Role.assistant => 'assistant',
        LanguageModelV3Role.tool => 'tool',
      };

      final text = message.content
          .whereType<LanguageModelV3TextPart>()
          .map((part) => part.text)
          .join('\n');

      final toolCalls = message.content
          .whereType<LanguageModelV3ToolCallPart>()
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
            .whereType<LanguageModelV3ToolResultPart>();
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
        if (contentParts != null && contentParts.isNotEmpty) {
          out.add({'role': role, 'content': contentParts});
          continue;
        }
      }

      out.add({'role': role, 'content': text});
    }

    return out;
  }

  List<Map<String, dynamic>>? _toContentParts(
    List<LanguageModelV3ContentPart> parts,
  ) {
    final out = <Map<String, dynamic>>[];
    for (final part in parts) {
      if (part is LanguageModelV3TextPart) {
        out.add({'type': 'text', 'text': part.text});
        continue;
      }
      if (part is LanguageModelV3ImagePart) {
        final imageUrl = _toImageUrl(part.image, part.mediaType);
        if (imageUrl != null) {
          out.add({
            'type': 'image_url',
            'image_url': {'url': imageUrl},
          });
        }
        continue;
      }
      if (part is LanguageModelV3FilePart &&
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
      if (part is LanguageModelV3FilePart &&
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
      if (part is LanguageModelV3FilePart) {
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
    return out.isEmpty ? null : out;
  }

  // ── tool serialization ────────────────────────────────────────────────

  Map<String, dynamic> _toToolJson(LanguageModelV3FunctionTool tool) {
    return {
      'type': 'function',
      'function': {
        'name': tool.name,
        if (tool.description != null) 'description': tool.description,
        'parameters': tool.inputSchema,
        if (tool.strict != null) 'strict': tool.strict,
      },
    };
  }

  Object _toToolChoice(LanguageModelV3ToolChoice choice) {
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
    required void Function(LanguageModelV3SourcePart) onSource,
    required void Function(LanguageModelV3FilePart) onFile,
  }) {
    for (var i = 0; i < annotations.length; i++) {
      final annotation = (annotations[i] as Map).cast<String, dynamic>();
      final type = annotation['type']?.toString();
      if (type == 'url_citation') {
        final url = annotation['url']?.toString();
        if (url != null && url.isNotEmpty) {
          onSource(
            LanguageModelV3SourcePart(
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
            LanguageModelV3FilePart(
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

  String _toToolResultText(LanguageModelV3ToolResultPart result) {
    if (result.output is ToolResultOutputText && !result.isError) {
      return (result.output as ToolResultOutputText).text;
    }
    return jsonEncode({
      'toolCallId': result.toolCallId,
      'toolName': result.toolName,
      'isError': result.isError,
      'output': _toToolResultOutputJson(result.output),
    });
  }

  Object _toToolResultOutputJson(LanguageModelV3ToolResultOutput output) {
    if (output is ToolResultOutputText) {
      return {'type': 'text', 'text': output.text};
    }
    if (output is ToolResultOutputContent) {
      return {
        'type': 'content',
        'parts': output.parts.map(_toGenericContentPartJson).toList(),
      };
    }
    // Unreachable: LanguageModelV3ToolResultOutput is a sealed class with only
    // ToolResultOutputText and ToolResultOutputContent, both handled above.
    return {'type': 'unknown'}; // coverage:ignore-line
  }

  Map<String, dynamic> _toGenericContentPartJson(
    LanguageModelV3ContentPart part,
  ) {
    if (part is LanguageModelV3TextPart) {
      return {'type': 'text', 'text': part.text};
    }
    if (part is LanguageModelV3ImagePart) {
      final data = _toBase64(part.image);
      return {
        'type': 'image',
        if (part.mediaType != null) 'mediaType': part.mediaType,
        if (part.image is DataContentUrl)
          'url': (part.image as DataContentUrl).url.toString(),
        if (data != null) 'base64': data,
      };
    }
    if (part is LanguageModelV3FilePart) {
      return {
        'type': 'file',
        'mediaType': part.mediaType,
        if (part.filename != null) 'filename': part.filename,
        if (part.data is DataContentUrl)
          'url': (part.data as DataContentUrl).url.toString(),
        if (_toBase64(part.data) case final data?) 'base64': data,
      };
    }
    return {'type': 'unsupported'};
  }

  // ── finish reason ─────────────────────────────────────────────────────

  LanguageModelV3FinishReason _mapFinishReason(String? reason) {
    return switch (reason) {
      'stop' => LanguageModelV3FinishReason.stop,
      'length' => LanguageModelV3FinishReason.length,
      'content_filter' => LanguageModelV3FinishReason.contentFilter,
      'tool_calls' => LanguageModelV3FinishReason.toolCalls,
      'error' => LanguageModelV3FinishReason.error,
      null => LanguageModelV3FinishReason.unknown,
      _ => LanguageModelV3FinishReason.other,
    };
  }
}

// ── shared helpers ────────────────────────────────────────────────────────

LanguageModelV3Usage _usageFrom(Map<String, dynamic> usage) {
  return LanguageModelV3Usage(
    inputTokens: _intOrNull(usage['prompt_tokens']),
    outputTokens: _intOrNull(usage['completion_tokens']),
    totalTokens: _intOrNull(usage['total_tokens']),
  );
}

String? _toImageUrl(LanguageModelV3DataContent data, String? mediaType) {
  if (data is DataContentUrl) return data.url.toString();
  final b64 = _toBase64(data);
  if (b64 == null) return null;
  final resolvedMediaType = mediaType ?? 'image/png';
  return 'data:$resolvedMediaType;base64,$b64';
}

String? _toBase64(LanguageModelV3DataContent data) {
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
  if (parsed is Map<String, dynamic>) return parsed;
  // Unreachable: jsonDecode always produces a Map<String, dynamic> for JSON
  // objects, so the typed check above always matches first; this guards a
  // hypothetical differently-typed Map without crashing.
  if (parsed is Map) return parsed.cast<String, dynamic>(); // coverage:ignore-line
  return null;
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

List<String> _readWarnings(Object? warningsRaw) {
  if (warningsRaw is! List) return const [];
  return warningsRaw
      .map((item) => item?.toString())
      .whereType<String>()
      .where((item) => item.isNotEmpty)
      .toList();
}

class _ToolStreamState {
  _ToolStreamState({required this.id, required this.name});

  final String id;
  String name;
  final StringBuffer argumentsBuffer = StringBuffer();
}
