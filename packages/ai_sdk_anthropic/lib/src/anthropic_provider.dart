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
  const AnthropicProvider({this.apiKey, this.baseUrl});

  /// API key (defaults to `ANTHROPIC_API_KEY` environment variable).
  final String? apiKey;

  /// Base URL for the API.
  final String? baseUrl;

  /// Returns a language model for the given [modelId].
  LanguageModelV3 call(String modelId) => _AnthropicLanguageModel(
    modelId: modelId,
    apiKey: apiKey,
    baseUrl: baseUrl,
  );
}

/// Default Anthropic provider instance.
const anthropic = AnthropicProvider();

class _AnthropicLanguageModel implements LanguageModelV3 {
  const _AnthropicLanguageModel({
    required this.modelId,
    this.apiKey,
    this.baseUrl,
  });

  @override
  final String modelId;
  final String? apiKey;
  final String? baseUrl;

  @override
  String get provider => 'anthropic';

  @override
  String get specificationVersion => 'v3';

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async {
    final client = _anthropicDio(apiKey: apiKey, baseUrl: baseUrl);
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
        'tools': options.tools
            .map(
              (tool) => {
                'name': tool.name,
                if (tool.description != null) 'description': tool.description,
                'input_schema': tool.inputSchema,
                if (tool.inputExamples != null &&
                    tool.inputExamples!.isNotEmpty)
                  'input_examples': tool.inputExamples,
              },
            )
            .toList(),
      if (options.toolChoice != null)
        'tool_choice': _toAnthropicToolChoice(options.toolChoice!),
      if (thinking != null) 'thinking': thinking,
      ...?cleanedPo,
    };
    final response = await client.post<Map<String, dynamic>>(
      '/messages',
      data: requestBody,
      options: Options(headers: options.headers),
    );

    final data = response.data ?? <String, dynamic>{};
    final content = <LanguageModelV3ContentPart>[];

    final parts = (data['content'] as List?) ?? const [];
    for (final part in parts) {
      final map = (part as Map).cast<String, dynamic>();
      final type = map['type']?.toString();
      if (type == 'text') {
        final text = map['text']?.toString();
        if (text != null && text.isNotEmpty) {
          content.add(LanguageModelV3TextPart(text: text));
        }

        final citations = (map['citations'] as List?) ?? const [];
        for (var i = 0; i < citations.length; i++) {
          final citation = (citations[i] as Map).cast<String, dynamic>();
          final url = citation['url']?.toString();
          if (url != null && url.isNotEmpty) {
            content.add(
              LanguageModelV3SourcePart(
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
          LanguageModelV3ToolCallPart(
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
            LanguageModelV3ReasoningPart(
              text: text,
              signature: map['signature']?.toString(),
            ),
          );
        }
      } else if (type == 'redacted_thinking') {
        final redacted = map['data']?.toString();
        if (redacted != null && redacted.isNotEmpty) {
          content.add(
            LanguageModelV3RedactedReasoningPart(
              data: Uint8List.fromList(utf8.encode(redacted)),
            ),
          );
        }
      }
    }

    final usage = (data['usage'] as Map?)?.cast<String, dynamic>();
    final warnings = _readWarnings(data['warnings']);
    return LanguageModelV3GenerateResult(
      content: content,
      finishReason: _mapAnthropicFinishReason(data['stop_reason']?.toString()),
      rawFinishReason: data['stop_reason']?.toString(),
      usage: usage == null
          ? null
          : LanguageModelV3Usage(
              inputTokens: _intOrNull(usage['input_tokens']),
              outputTokens: _intOrNull(usage['output_tokens']),
            ),
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
    final client = _anthropicDio(apiKey: apiKey, baseUrl: baseUrl);
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
        'tools': options.tools
            .map(
              (tool) => {
                'name': tool.name,
                if (tool.description != null) 'description': tool.description,
                'input_schema': tool.inputSchema,
                if (tool.inputExamples != null &&
                    tool.inputExamples!.isNotEmpty)
                  'input_examples': tool.inputExamples,
              },
            )
            .toList(),
      if (options.toolChoice != null)
        'tool_choice': _toAnthropicToolChoice(options.toolChoice!),
      if (thinking != null) 'thinking': thinking,
      ...?cleanedPo,
    };
    final response = await client.post<ResponseBody>(
      '/messages',
      data: requestBody,
      options: Options(
        responseType: ResponseType.stream,
        headers: options.headers,
      ),
    );

    final body = response.data;
    if (body == null) {
      throw StateError('Anthropic stream response body is null.');
    }

    final controller = StreamController<LanguageModelV3StreamPart>();
    final toolState = <int, _ToolState>{};
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
          final json = _safeParseMap(dataLine);
          if (json == null) continue;
          lastChunk = json;
          final type = json['type']?.toString();
          streamWarnings.addAll(_readWarnings(json['warnings']));

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
              streamUsage = LanguageModelV3Usage(
                inputTokens: _intOrNull(usage['input_tokens']),
                outputTokens: _intOrNull(usage['output_tokens']),
              );
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
                  StreamPartToolCallStart(toolCallId: id, toolName: name),
                );
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
                    StreamPartToolCallDelta(
                      toolCallId: state.id,
                      toolName: state.name,
                      argsTextDelta: chunk,
                    ),
                  );
                }
              } else if (deltaType == 'thinking_delta') {
                final reasoning = delta['thinking']?.toString();
                if (reasoning != null && reasoning.isNotEmpty) {
                  controller.add(StreamPartReasoningDelta(delta: reasoning));
                }
              }
              break;
            case 'content_block_stop':
              final index = _intOrNull(json['index']) ?? 0;
              final state = toolState.remove(index);
              if (state != null) {
                controller.add(
                  StreamPartToolCallEnd(
                    toolCallId: state.id,
                    toolName: state.name,
                    input: _safeParseJson(state.argumentsBuffer.toString()),
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
                streamUsage = LanguageModelV3Usage(
                  inputTokens:
                      _intOrNull(usage['input_tokens']) ??
                      streamUsage?.inputTokens,
                  outputTokens:
                      _intOrNull(usage['output_tokens']) ??
                      streamUsage?.outputTokens,
                );
              }
              final stopReason = delta['stop_reason']?.toString();
              if (stopReason != null) {
                if (textStarted) {
                  controller.add(const StreamPartTextEnd(id: 'text-0'));
                }
                controller.add(
                  StreamPartFinish(
                    finishReason: _mapAnthropicFinishReason(stopReason),
                    rawFinishReason: stopReason,
                    usage: streamUsage,
                    providerMetadata: {
                      provider: {
                        if (responseId != null) 'id': responseId,
                        if (responseModel != null) 'model': responseModel,
                        'timestamp': DateTime.now().toUtc().toIso8601String(),
                        if (streamWarnings.isNotEmpty)
                          'warnings': streamWarnings,
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
}

Dio _anthropicDio({String? apiKey, String? baseUrl}) {
  final resolvedApiKey =
      apiKey ?? const String.fromEnvironment('ANTHROPIC_API_KEY');
  return Dio(
    BaseOptions(
      baseUrl: baseUrl ?? 'https://api.anthropic.com/v1',
      headers: {
        if (resolvedApiKey.isNotEmpty) 'x-api-key': resolvedApiKey,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
      },
    ),
  );
}

List<Map<String, dynamic>> _toAnthropicMessages(LanguageModelV3Prompt prompt) {
  final out = <Map<String, dynamic>>[];

  for (final message in prompt.messages) {
    final role = switch (message.role) {
      LanguageModelV3Role.system => 'user',
      LanguageModelV3Role.user => 'user',
      LanguageModelV3Role.assistant => 'assistant',
      LanguageModelV3Role.tool => 'user',
    };

    final contentParts = <Map<String, dynamic>>[];
    for (final part in message.content) {
      if (part is LanguageModelV3TextPart) {
        contentParts.add({'type': 'text', 'text': part.text});
      } else if (part is LanguageModelV3ImagePart) {
        final image = _toAnthropicImagePart(part);
        if (image != null) {
          contentParts.add(image);
        }
      } else if (part is LanguageModelV3FilePart) {
        final document = _toAnthropicFilePart(part);
        if (document != null) {
          contentParts.add(document);
        }
      } else if (part is LanguageModelV3ToolCallPart) {
        contentParts.add({
          'type': 'tool_use',
          'id': part.toolCallId,
          'name': part.toolName,
          'input': part.input,
        });
      } else if (part is LanguageModelV3ToolResultPart) {
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

Map<String, dynamic> _toAnthropicToolChoice(LanguageModelV3ToolChoice choice) {
  return switch (choice) {
    ToolChoiceAuto() => {'type': 'auto'},
    ToolChoiceNone() => {'type': 'auto'},
    ToolChoiceRequired() => {'type': 'any'},
    ToolChoiceSpecific(:final toolName) => {'type': 'tool', 'name': toolName},
  };
}

LanguageModelV3FinishReason _mapAnthropicFinishReason(String? reason) {
  return switch (reason) {
    'end_turn' => LanguageModelV3FinishReason.stop,
    'max_tokens' => LanguageModelV3FinishReason.length,
    'tool_use' => LanguageModelV3FinishReason.toolCalls,
    'stop_sequence' => LanguageModelV3FinishReason.stop,
    null => LanguageModelV3FinishReason.unknown,
    _ => LanguageModelV3FinishReason.other,
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
  if (parsed is Map<String, dynamic>) return parsed;
  if (parsed is Map) return parsed.cast<String, dynamic>();
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

Map<String, dynamic>? _toAnthropicImagePart(LanguageModelV3ImagePart part) {
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

Map<String, dynamic>? _toAnthropicFilePart(LanguageModelV3FilePart part) {
  if (part.mediaType.startsWith('image/')) {
    return _toAnthropicImagePart(
      LanguageModelV3ImagePart(image: part.data, mediaType: part.mediaType),
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

Object _toAnthropicToolResultContent(LanguageModelV3ToolResultOutput output) {
  if (output is ToolResultOutputText) return output.text;
  if (output is! ToolResultOutputContent) return '';
  return output.parts.map(_toAnthropicToolResultPart).toList();
}

Map<String, dynamic> _toAnthropicToolResultPart(
  LanguageModelV3ContentPart part,
) {
  if (part is LanguageModelV3TextPart) {
    return {'type': 'text', 'text': part.text};
  }

  if (part is LanguageModelV3ImagePart) {
    final image = _toAnthropicImagePart(part);
    if (image != null) return image;
  }

  if (part is LanguageModelV3FilePart) {
    final file = _toAnthropicFilePart(part);
    if (file != null) return file;
  }

  return {'type': 'text', 'text': '[unsupported tool result content]'};
}

String? _toBase64(LanguageModelV3DataContent data) {
  return switch (data) {
    DataContentBytes(:final bytes) => base64Encode(bytes),
    DataContentBase64(:final base64) => base64,
    DataContentUrl() => null,
  };
}

List<String> _readWarnings(Object? warningsRaw) {
  if (warningsRaw is! List) return const [];
  return warningsRaw
      .map((item) => item?.toString())
      .whereType<String>()
      .where((item) => item.isNotEmpty)
      .toList();
}

class _ToolState {
  _ToolState({required this.id, required this.name});

  final String id;
  final String name;
  final StringBuffer argumentsBuffer = StringBuffer();
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
