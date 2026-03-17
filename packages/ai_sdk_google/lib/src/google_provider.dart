import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';

class GoogleGenerativeAIProvider {
  const GoogleGenerativeAIProvider({this.apiKey, this.baseUrl});

  final String? apiKey;
  final String? baseUrl;

  LanguageModelV3 call(String modelId) =>
      _GoogleLanguageModel(modelId: modelId, apiKey: apiKey, baseUrl: baseUrl);

  EmbeddingModelV2<String> embedding(String modelId) =>
      _GoogleEmbeddingModel(modelId: modelId, apiKey: apiKey, baseUrl: baseUrl);
}

const google = GoogleGenerativeAIProvider();

class _GoogleLanguageModel implements LanguageModelV3 {
  const _GoogleLanguageModel({
    required this.modelId,
    this.apiKey,
    this.baseUrl,
  });

  @override
  final String modelId;
  final String? apiKey;
  final String? baseUrl;

  @override
  String get provider => 'google';

  @override
  String get specificationVersion => 'v3';

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async {
    final client = _googleDio(baseUrl: baseUrl);
    final modelPath = _modelPath(modelId);
    final providerOptions = options.providerOptions != null
        ? options.providerOptions![provider]
        : null;
    final requestBody = {
      'contents': _toGoogleContents(options.prompt.messages),
      if (options.prompt.system != null)
        'systemInstruction': {
          'parts': [
            {'text': options.prompt.system},
          ],
        },
      'generationConfig': {
        if (options.maxOutputTokens != null)
          'maxOutputTokens': options.maxOutputTokens,
        if (options.temperature != null) 'temperature': options.temperature,
        if (options.topP != null) 'topP': options.topP,
        if (options.topK != null) 'topK': options.topK,
        if (options.stopSequences.isNotEmpty)
          'stopSequences': options.stopSequences,
      },
      if (options.tools.isNotEmpty) ...{
        'tools': [
          {
            'functionDeclarations': options.tools
                .map(
                  (tool) => {
                    'name': tool.name,
                    if (tool.description != null)
                      'description': tool.description,
                    'parameters': tool.inputSchema,
                  },
                )
                .toList(),
          },
        ],
      },
      ..._googleToolChoicePayload(options.toolChoice),
      ...?providerOptions,
    };

    final response = await client.post<Map<String, dynamic>>(
      '/$modelPath:generateContent',
      queryParameters: {'key': _resolvedApiKey(apiKey)},
      data: requestBody,
      options: Options(headers: options.headers),
    );

    final data = response.data ?? <String, dynamic>{};
    final candidates = (data['candidates'] as List?) ?? const [];
    final first = candidates.isNotEmpty
        ? (candidates.first as Map).cast<String, dynamic>()
        : <String, dynamic>{};

    final content = <LanguageModelV3ContentPart>[];
    final contentObj =
        (first['content'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final parts = (contentObj['parts'] as List?) ?? const [];
    for (final part in parts) {
      final partMap = (part as Map).cast<String, dynamic>();
      if (partMap['text'] is String) {
        final text = partMap['text'].toString();
        if (text.isNotEmpty) {
          content.add(LanguageModelV3TextPart(text: text));
        }
      }
      final functionCall = (partMap['functionCall'] as Map?)
          ?.cast<String, dynamic>();
      if (functionCall != null) {
        final rawArgs = functionCall['args'];
        content.add(
          LanguageModelV3ToolCallPart(
            toolCallId: _generateId('tool'),
            toolName: functionCall['name']?.toString() ?? 'unknown_tool',
            input: rawArgs is Map
                ? rawArgs.cast<String, dynamic>()
                : (rawArgs ?? const {}),
          ),
        );
      }

      final fileData = (partMap['fileData'] as Map?)?.cast<String, dynamic>();
      if (fileData != null) {
        final uri = fileData['fileUri']?.toString();
        final mime =
            fileData['mimeType']?.toString() ?? 'application/octet-stream';
        if (uri != null && uri.isNotEmpty) {
          final parsed = Uri.tryParse(uri);
          if (parsed != null) {
            content.add(
              LanguageModelV3FilePart(
                data: DataContentUrl(parsed),
                mediaType: mime,
              ),
            );
          }
        }
      }

      final inlineData = (partMap['inlineData'] as Map?)
          ?.cast<String, dynamic>();
      if (inlineData != null) {
        final mime =
            inlineData['mimeType']?.toString() ?? 'application/octet-stream';
        final data = inlineData['data']?.toString();
        if (data != null && data.isNotEmpty) {
          content.add(
            LanguageModelV3FilePart(
              data: DataContentBase64(data),
              mediaType: mime,
            ),
          );
        }
      }
    }

    final grounding =
        (first['groundingMetadata'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final chunks = (grounding['groundingChunks'] as List?) ?? const [];
    for (var i = 0; i < chunks.length; i++) {
      final chunk = (chunks[i] as Map).cast<String, dynamic>();
      final web = (chunk['web'] as Map?)?.cast<String, dynamic>();
      if (web == null) continue;
      final url = web['uri']?.toString();
      if (url == null || url.isEmpty) continue;
      content.add(
        LanguageModelV3SourcePart(
          id: 'google_source_$i',
          url: url,
          title: web['title']?.toString(),
          providerMetadata: chunk,
        ),
      );
    }

    final usage = (data['usageMetadata'] as Map?)?.cast<String, dynamic>();
    final warnings = _readGoogleWarnings(data);
    return LanguageModelV3GenerateResult(
      content: content,
      finishReason: _mapGoogleFinishReason(first['finishReason']?.toString()),
      rawFinishReason: first['finishReason']?.toString(),
      usage: usage == null
          ? null
          : LanguageModelV3Usage(
              inputTokens: _intOrNull(usage['promptTokenCount']),
              outputTokens: _intOrNull(usage['candidatesTokenCount']),
              totalTokens: _intOrNull(usage['totalTokenCount']),
            ),
      warnings: warnings,
      response: LanguageModelV3ResponseMetadata(
        modelId: modelId,
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
    final client = _googleDio(baseUrl: baseUrl);
    final modelPath = _modelPath(modelId);
    final providerOptions = options.providerOptions != null
        ? options.providerOptions![provider]
        : null;
    final requestBody = {
      'contents': _toGoogleContents(options.prompt.messages),
      if (options.prompt.system != null)
        'systemInstruction': {
          'parts': [
            {'text': options.prompt.system},
          ],
        },
      'generationConfig': {
        if (options.maxOutputTokens != null)
          'maxOutputTokens': options.maxOutputTokens,
        if (options.temperature != null) 'temperature': options.temperature,
        if (options.topP != null) 'topP': options.topP,
        if (options.topK != null) 'topK': options.topK,
      },
      if (options.tools.isNotEmpty) ...{
        'tools': [
          {
            'functionDeclarations': options.tools
                .map(
                  (tool) => {
                    'name': tool.name,
                    if (tool.description != null)
                      'description': tool.description,
                    'parameters': tool.inputSchema,
                  },
                )
                .toList(),
          },
        ],
      },
      ..._googleToolChoicePayload(options.toolChoice),
      ...?providerOptions,
    };
    final response = await client.post<ResponseBody>(
      '/$modelPath:streamGenerateContent',
      queryParameters: {'alt': 'sse', 'key': _resolvedApiKey(apiKey)},
      data: requestBody,
      options: Options(
        responseType: ResponseType.stream,
        headers: options.headers,
      ),
    );

    final body = response.data;
    if (body == null) {
      throw StateError('Google stream response body is null.');
    }

    final controller = StreamController<LanguageModelV3StreamPart>();
    var textStarted = false;
    LanguageModelV3Usage? streamUsage;
    final warnings = <String>[];
    Map<String, dynamic>? lastChunk;
    final rawResponse = <String, Object?>{
      'requestBody': requestBody,
      'statusCode': response.statusCode,
      'headers': response.headers.map.map(
        (key, value) => MapEntry(key, value.join(',')),
      ),
      'responseMetadata': {
        'modelId': modelId,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      },
    };

    unawaited(() async {
      try {
        await for (final payload in _readSseDataLines(body.stream)) {
          final json = _safeParseMap(payload);
          if (json == null) continue;
          lastChunk = json;
          warnings.addAll(_readGoogleWarnings(json));
          final usage = (json['usageMetadata'] as Map?)
              ?.cast<String, dynamic>();
          if (usage != null) {
            streamUsage = LanguageModelV3Usage(
              inputTokens: _intOrNull(usage['promptTokenCount']),
              outputTokens: _intOrNull(usage['candidatesTokenCount']),
              totalTokens: _intOrNull(usage['totalTokenCount']),
            );
          }
          final candidates = (json['candidates'] as List?) ?? const [];
          if (candidates.isEmpty) continue;
          final first = (candidates.first as Map).cast<String, dynamic>();
          final content =
              (first['content'] as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{};
          final parts = (content['parts'] as List?) ?? const [];
          for (final part in parts) {
            final map = (part as Map).cast<String, dynamic>();
            final text = map['text']?.toString();
            if (text != null && text.isNotEmpty) {
              if (!textStarted) {
                textStarted = true;
                controller.add(const StreamPartTextStart(id: 'text-0'));
              }
              controller.add(StreamPartTextDelta(id: 'text-0', delta: text));
            }

            final fileData = (map['fileData'] as Map?)?.cast<String, dynamic>();
            if (fileData != null) {
              final uri = fileData['fileUri']?.toString();
              final mime =
                  fileData['mimeType']?.toString() ??
                  'application/octet-stream';
              final parsed = uri == null ? null : Uri.tryParse(uri);
              if (parsed != null) {
                controller.add(
                  StreamPartFile(
                    file: LanguageModelV3FilePart(
                      data: DataContentUrl(parsed),
                      mediaType: mime,
                    ),
                  ),
                );
              }
            }

            final inlineData = (map['inlineData'] as Map?)
                ?.cast<String, dynamic>();
            if (inlineData != null) {
              final mime =
                  inlineData['mimeType']?.toString() ??
                  'application/octet-stream';
              final data = inlineData['data']?.toString();
              if (data != null && data.isNotEmpty) {
                controller.add(
                  StreamPartFile(
                    file: LanguageModelV3FilePart(
                      data: DataContentBase64(data),
                      mediaType: mime,
                    ),
                  ),
                );
              }
            }
          }

          final grounding =
              (first['groundingMetadata'] as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{};
          final chunks = (grounding['groundingChunks'] as List?) ?? const [];
          for (var i = 0; i < chunks.length; i++) {
            final chunk = (chunks[i] as Map).cast<String, dynamic>();
            final web = (chunk['web'] as Map?)?.cast<String, dynamic>();
            if (web == null) continue;
            final url = web['uri']?.toString();
            if (url == null || url.isEmpty) continue;
            controller.add(
              StreamPartSource(
                source: LanguageModelV3SourcePart(
                  id: 'google_source_$i',
                  url: url,
                  title: web['title']?.toString(),
                  providerMetadata: chunk,
                ),
              ),
            );
          }

          final finishReason = first['finishReason']?.toString();
          if (finishReason != null) {
            if (textStarted) {
              controller.add(const StreamPartTextEnd(id: 'text-0'));
            }
            controller.add(
              StreamPartFinish(
                finishReason: _mapGoogleFinishReason(finishReason),
                rawFinishReason: finishReason,
                usage: streamUsage,
                providerMetadata: {
                  provider: {
                    'model': modelId,
                    'timestamp': DateTime.now().toUtc().toIso8601String(),
                    if (warnings.isNotEmpty) 'warnings': warnings,
                  },
                },
              ),
            );
          }

          rawResponse['warnings'] = List<String>.from(warnings);
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

class _GoogleEmbeddingModel implements EmbeddingModelV2<String> {
  const _GoogleEmbeddingModel({
    required this.modelId,
    this.apiKey,
    this.baseUrl,
  });

  @override
  final String modelId;
  final String? apiKey;
  final String? baseUrl;

  @override
  String get provider => 'google';

  @override
  String get specificationVersion => 'v2';

  @override
  Future<EmbeddingModelV2GenerateResult<String>> doEmbed(
    EmbeddingModelV2CallOptions<String> options,
  ) async {
    final client = _googleDio(baseUrl: baseUrl);
    final modelPath = _modelPath(modelId);
    final providerOptions = options.providerOptions != null
        ? options.providerOptions![provider]
        : null;
    final response = await client.post<Map<String, dynamic>>(
      '/$modelPath:batchEmbedContents',
      queryParameters: {'key': _resolvedApiKey(apiKey)},
      data: {
        'requests': options.values
            .map(
              (value) => {
                'model': modelPath,
                'content': {
                  'parts': [
                    {'text': value},
                  ],
                },
              },
            )
            .toList(),
        ...?providerOptions,
      },
      options: Options(headers: options.headers),
    );

    final data = response.data ?? <String, dynamic>{};
    final embeddings = (data['embeddings'] as List?) ?? const [];

    final out = <EmbeddingModelV2Embedding<String>>[];
    for (var i = 0; i < embeddings.length && i < options.values.length; i++) {
      final row = (embeddings[i] as Map).cast<String, dynamic>();
      final values = ((row['values'] as List?) ?? const [])
          .map((e) => (e as num).toDouble())
          .toList();
      out.add(
        EmbeddingModelV2Embedding<String>(
          value: options.values[i],
          embedding: values,
        ),
      );
    }

    return EmbeddingModelV2GenerateResult<String>(embeddings: out);
  }
}

Dio _googleDio({String? baseUrl}) {
  return Dio(
    BaseOptions(
      baseUrl: baseUrl ?? 'https://generativelanguage.googleapis.com/v1beta',
      headers: {'content-type': 'application/json'},
    ),
  );
}

String _resolvedApiKey(String? apiKey) {
  final resolved = apiKey ?? const String.fromEnvironment('GOOGLE_API_KEY');
  if (resolved.isEmpty) {
    throw StateError('Missing GOOGLE_API_KEY for Google provider.');
  }
  return resolved;
}

String _modelPath(String modelId) {
  if (modelId.startsWith('models/')) return modelId;
  return 'models/$modelId';
}

List<Map<String, dynamic>> _toGoogleContents(
  List<LanguageModelV3Message> messages,
) {
  return messages.map((message) {
    final role = switch (message.role) {
      LanguageModelV3Role.system => 'user',
      LanguageModelV3Role.user => 'user',
      LanguageModelV3Role.assistant => 'model',
      LanguageModelV3Role.tool => 'user',
    };

    final parts = <Map<String, dynamic>>[];
    for (final part in message.content) {
      if (part is LanguageModelV3TextPart) {
        parts.add({'text': part.text});
      } else if (part is LanguageModelV3ImagePart) {
        final imagePart = _toGoogleInlinePart(part.image, part.mediaType);
        if (imagePart != null) {
          parts.add(imagePart);
        }
      } else if (part is LanguageModelV3FilePart) {
        final filePart = _toGoogleInlinePart(part.data, part.mediaType);
        if (filePart != null) {
          parts.add(filePart);
        }
      } else if (part is LanguageModelV3ToolCallPart) {
        parts.add({
          'functionCall': {'name': part.toolName, 'args': part.input},
        });
      } else if (part is LanguageModelV3ToolResultPart) {
        parts.add({
          'functionResponse': {
            'name': part.toolName,
            'response': {
              'toolCallId': part.toolCallId,
              'isError': part.isError,
              'output': _toGoogleToolResultOutput(part.output),
            },
          },
        });
      }
    }

    if (parts.isEmpty) {
      final fallbackText = message.content
          .whereType<LanguageModelV3TextPart>()
          .map((e) => e.text)
          .join('\n');
      parts.add({'text': fallbackText});
    }

    return {'role': role, 'parts': parts};
  }).toList();
}

LanguageModelV3FinishReason _mapGoogleFinishReason(String? reason) {
  return switch (reason) {
    'STOP' => LanguageModelV3FinishReason.stop,
    'MAX_TOKENS' => LanguageModelV3FinishReason.length,
    'SAFETY' => LanguageModelV3FinishReason.contentFilter,
    'RECITATION' => LanguageModelV3FinishReason.contentFilter,
    'OTHER' => LanguageModelV3FinishReason.other,
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
  try {
    final decoded = jsonDecode(input);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return decoded.cast<String, dynamic>();
    return null;
  } catch (_) {
    return null;
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

Map<String, dynamic>? _toGoogleInlinePart(
  LanguageModelV3DataContent data,
  String? mediaType,
) {
  if (data is DataContentUrl) {
    return {
      'fileData': {
        'mimeType': mediaType ?? 'application/octet-stream',
        'fileUri': data.url.toString(),
      },
    };
  }

  final b64 = _toBase64(data);
  if (b64 == null) return null;
  return {
    'inlineData': {
      'mimeType': mediaType ?? 'application/octet-stream',
      'data': b64,
    },
  };
}

Object _toGoogleToolResultOutput(LanguageModelV3ToolResultOutput output) {
  if (output is ToolResultOutputText) {
    return {'type': 'text', 'text': output.text};
  }
  if (output is ToolResultOutputContent) {
    return {
      'type': 'content',
      'parts': output.parts.map(_toGoogleToolResultPart).toList(),
    };
  }
  return {'type': 'unknown'};
}

Map<String, dynamic> _toGoogleToolResultPart(LanguageModelV3ContentPart part) {
  if (part is LanguageModelV3TextPart) {
    return {'type': 'text', 'text': part.text};
  }
  if (part is LanguageModelV3ImagePart) {
    return {
      'type': 'image',
      ...?_toGoogleInlinePart(part.image, part.mediaType),
    };
  }
  if (part is LanguageModelV3FilePart) {
    return {
      'type': 'file',
      'mediaType': part.mediaType,
      if (part.filename != null) 'filename': part.filename,
      ...?_toGoogleInlinePart(part.data, part.mediaType),
    };
  }
  return {'type': 'unsupported'};
}

String? _toBase64(LanguageModelV3DataContent data) {
  return switch (data) {
    DataContentBytes(:final bytes) => base64Encode(bytes),
    DataContentBase64(:final base64) => base64,
    DataContentUrl() => null,
  };
}

List<String> _readGoogleWarnings(Map<String, dynamic> payload) {
  final warnings = <String>[];
  final promptFeedback = payload['promptFeedback'];
  if (promptFeedback != null) {
    warnings.add('promptFeedback: ${jsonEncode(promptFeedback)}');
  }
  final list = payload['warnings'];
  if (list is List) {
    for (final item in list) {
      final warning = item?.toString();
      if (warning != null && warning.isNotEmpty) {
        warnings.add(warning);
      }
    }
  }
  return warnings;
}

Map<String, dynamic> _googleToolChoicePayload(
  LanguageModelV3ToolChoice? choice,
) {
  if (choice == null) {
    return const {};
  }
  return {
    'toolConfig': {
      'functionCallingConfig': switch (choice) {
        ToolChoiceAuto() => {'mode': 'AUTO'},
        ToolChoiceNone() => {'mode': 'NONE'},
        ToolChoiceRequired() => {'mode': 'ANY'},
        ToolChoiceSpecific(:final toolName) => {
          'mode': 'ANY',
          'allowedFunctionNames': [toolName],
        },
      },
    },
  };
}
