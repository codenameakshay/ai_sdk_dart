import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';

/// OpenAI provider for language models, embeddings, images, speech, and transcription.
///
/// Use [call] for language models, [embedding] for embeddings, [image] for image
/// generation, [speech] for text-to-speech, [transcription] for speech-to-text.
///
/// Example:
/// ```dart
/// final model = openai('gpt-4o');
/// final result = await generateText(model: model, prompt: 'Hello');
/// ```
class OpenAIProvider {
  const OpenAIProvider({this.apiKey, this.baseUrl});

  /// API key (defaults to `OPENAI_API_KEY` environment variable).
  final String? apiKey;

  /// Base URL (defaults to `https://api.openai.com/v1`).
  final String? baseUrl;

  /// Returns a language model for the given [modelId].
  LanguageModelV3 call(String modelId) =>
      _OpenAILanguageModel(modelId: modelId, apiKey: apiKey, baseUrl: baseUrl);

  /// Returns an embedding model for the given [modelId].
  EmbeddingModelV2<String> embedding(String modelId) =>
      _OpenAIEmbeddingModel(modelId: modelId, apiKey: apiKey, baseUrl: baseUrl);

  /// Returns an image generation model for the given [modelId].
  ImageModelV3 image(String modelId) =>
      _OpenAIImageModel(modelId: modelId, apiKey: apiKey, baseUrl: baseUrl);

  /// Returns a speech (text-to-speech) model for the given [modelId].
  SpeechModelV1 speech(String modelId) =>
      _OpenAISpeechModel(modelId: modelId, apiKey: apiKey, baseUrl: baseUrl);

  /// Returns a transcription (speech-to-text) model for the given [modelId].
  TranscriptionModelV1 transcription(String modelId) =>
      _OpenAITranscriptionModel(
        modelId: modelId,
        apiKey: apiKey,
        baseUrl: baseUrl,
      );
}

/// Default OpenAI provider instance.
///
/// Uses `OPENAI_API_KEY` from the environment when [apiKey] is not set.
const openai = OpenAIProvider();

class _OpenAILanguageModel implements LanguageModelV3 {
  const _OpenAILanguageModel({
    required this.modelId,
    this.apiKey,
    this.baseUrl,
  });

  @override
  final String modelId;
  final String? apiKey;
  final String? baseUrl;

  @override
  String get provider => 'openai';

  @override
  String get specificationVersion => 'v3';

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async {
    final client = _openAiDio(apiKey: apiKey, baseUrl: baseUrl);
    final po = options.providerOptions != null
        ? options.providerOptions![provider]
        : null;
    final (reasoningEffort, reasoningSummary, cleanedPo) =
        _extractReasoningOptions(po);
    final requestBody = {
      'model': modelId,
      'messages': _toOpenAiMessages(options.prompt),
      if (options.tools.isNotEmpty)
        'tools': options.tools
            .map(
              (tool) => {
                'type': 'function',
                'function': {
                  'name': tool.name,
                  if (tool.description != null) 'description': tool.description,
                  'parameters': tool.inputSchema,
                  if (tool.strict != null) 'strict': tool.strict,
                },
              },
            )
            .toList(),
      if (options.toolChoice != null)
        'tool_choice': _toOpenAiToolChoice(options.toolChoice!),
      if (options.maxOutputTokens != null)
        'max_completion_tokens': options.maxOutputTokens,
      if (options.temperature != null) 'temperature': options.temperature,
      if (options.topP != null) 'top_p': options.topP,
      if (options.presencePenalty != null)
        'presence_penalty': options.presencePenalty,
      if (options.frequencyPenalty != null)
        'frequency_penalty': options.frequencyPenalty,
      if (options.stopSequences.isNotEmpty) 'stop': options.stopSequences,
      if (options.seed != null) 'seed': options.seed,
      if (reasoningEffort != null) 'reasoning_effort': reasoningEffort,
      if (reasoningSummary != null) 'reasoning_summary': reasoningSummary,
      ...?cleanedPo,
    };
    final response = await client.post<Map<String, dynamic>>(
      '/chat/completions',
      data: requestBody,
      options: Options(headers: options.headers),
    );

    final data = response.data ?? <String, dynamic>{};
    final choices = (data['choices'] as List?) ?? const [];
    final firstChoice = choices.isNotEmpty
        ? (choices.first as Map<String, dynamic>)
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

    final annotations = (message['annotations'] as List?) ?? const [];
    for (var i = 0; i < annotations.length; i++) {
      final annotation = (annotations[i] as Map).cast<String, dynamic>();
      final type = annotation['type']?.toString();
      if (type == 'url_citation') {
        final url = annotation['url']?.toString();
        if (url != null && url.isNotEmpty) {
          content.add(
            LanguageModelV3SourcePart(
              id: 'openai_source_$i',
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
          content.add(
            LanguageModelV3FilePart(
              data: DataContentUrl(Uri.parse('openai://file/$fileId')),
              mediaType: 'application/octet-stream',
              filename: fileId,
            ),
          );
        }
      }
    }

    final usageMap = (data['usage'] as Map?)?.cast<String, dynamic>();
    final warnings = _readWarnings(data['warnings']);
    return LanguageModelV3GenerateResult(
      content: content,
      finishReason: _mapOpenAiFinishReason(
        firstChoice['finish_reason']?.toString(),
      ),
      rawFinishReason: firstChoice['finish_reason']?.toString(),
      usage: usageMap == null
          ? null
          : LanguageModelV3Usage(
              inputTokens: _intOrNull(usageMap['prompt_tokens']),
              outputTokens: _intOrNull(usageMap['completion_tokens']),
              totalTokens: _intOrNull(usageMap['total_tokens']),
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
    final client = _openAiDio(apiKey: apiKey, baseUrl: baseUrl);
    final po = options.providerOptions != null
        ? options.providerOptions![provider]
        : null;
    final (reasoningEffort, reasoningSummary, cleanedPo) =
        _extractReasoningOptions(po);
    final requestBody = {
      'model': modelId,
      'messages': _toOpenAiMessages(options.prompt),
      'stream': true,
      'stream_options': {'include_usage': true},
      if (options.tools.isNotEmpty)
        'tools': options.tools
            .map(
              (tool) => {
                'type': 'function',
                'function': {
                  'name': tool.name,
                  if (tool.description != null) 'description': tool.description,
                  'parameters': tool.inputSchema,
                  if (tool.strict != null) 'strict': tool.strict,
                },
              },
            )
            .toList(),
      if (options.toolChoice != null)
        'tool_choice': _toOpenAiToolChoice(options.toolChoice!),
      if (options.maxOutputTokens != null)
        'max_completion_tokens': options.maxOutputTokens,
      if (options.temperature != null) 'temperature': options.temperature,
      if (options.topP != null) 'top_p': options.topP,
      if (reasoningEffort != null) 'reasoning_effort': reasoningEffort,
      if (reasoningSummary != null) 'reasoning_summary': reasoningSummary,
      ...?cleanedPo,
    };
    final response = await client.post<ResponseBody>(
      '/chat/completions',
      data: requestBody,
      options: Options(
        responseType: ResponseType.stream,
        headers: options.headers,
      ),
    );

    final body = response.data;
    if (body == null) {
      throw StateError('OpenAI stream response body is null.');
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
            streamUsage = LanguageModelV3Usage(
              inputTokens: _intOrNull(usageMap['prompt_tokens']),
              outputTokens: _intOrNull(usageMap['completion_tokens']),
              totalTokens: _intOrNull(usageMap['total_tokens']),
            );
          }

          final choices = (json['choices'] as List?) ?? const [];
          if (choices.isEmpty) continue;
          final choice = (choices.first as Map).cast<String, dynamic>();

          final delta =
              (choice['delta'] as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{};

          final annotations = (delta['annotations'] as List?) ?? const [];
          for (var i = 0; i < annotations.length; i++) {
            final annotation = (annotations[i] as Map).cast<String, dynamic>();
            final type = annotation['type']?.toString();
            if (type == 'url_citation') {
              final url = annotation['url']?.toString();
              if (url != null && url.isNotEmpty) {
                controller.add(
                  StreamPartSource(
                    source: LanguageModelV3SourcePart(
                      id: 'openai_source_$i',
                      url: url,
                      title: annotation['title']?.toString(),
                      providerMetadata: annotation,
                    ),
                  ),
                );
              }
            }
            if (type == 'file_citation') {
              final fileId = annotation['file_id']?.toString();
              if (fileId != null && fileId.isNotEmpty) {
                controller.add(
                  StreamPartFile(
                    file: LanguageModelV3FilePart(
                      data: DataContentUrl(Uri.parse('openai://file/$fileId')),
                      mediaType: 'application/octet-stream',
                      filename: fileId,
                    ),
                  ),
                );
              }
            }
          }

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
                finishReason: _mapOpenAiFinishReason(finishReason),
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
}

class _OpenAIEmbeddingModel implements EmbeddingModelV2<String> {
  const _OpenAIEmbeddingModel({
    required this.modelId,
    this.apiKey,
    this.baseUrl,
  });

  @override
  final String modelId;

  final String? apiKey;
  final String? baseUrl;

  @override
  String get provider => 'openai';

  @override
  String get specificationVersion => 'v2';

  @override
  Future<EmbeddingModelV2GenerateResult<String>> doEmbed(
    EmbeddingModelV2CallOptions<String> options,
  ) async {
    final client = _openAiDio(apiKey: apiKey, baseUrl: baseUrl);
    final providerOptions = options.providerOptions != null
        ? options.providerOptions![provider]
        : null;
    final response = await client.post<Map<String, dynamic>>(
      '/embeddings',
      data: {'model': modelId, 'input': options.values, ...?providerOptions},
      options: Options(headers: options.headers),
    );

    final data = response.data ?? <String, dynamic>{};
    final rawEmbeddings = (data['data'] as List?) ?? const [];

    final embeddings = <EmbeddingModelV2Embedding<String>>[];
    for (
      var i = 0;
      i < rawEmbeddings.length && i < options.values.length;
      i++
    ) {
      final row = (rawEmbeddings[i] as Map).cast<String, dynamic>();
      final vector = ((row['embedding'] as List?) ?? const [])
          .map((v) => (v as num).toDouble())
          .toList();
      embeddings.add(
        EmbeddingModelV2Embedding<String>(
          value: options.values[i],
          embedding: vector,
        ),
      );
    }

    final usage = (data['usage'] as Map?)?.cast<String, dynamic>();
    return EmbeddingModelV2GenerateResult<String>(
      embeddings: embeddings,
      usage: EmbeddingModelV2Usage(tokens: _intOrNull(usage?['total_tokens'])),
    );
  }
}

class _OpenAIImageModel implements ImageModelV3 {
  const _OpenAIImageModel({required this.modelId, this.apiKey, this.baseUrl});

  @override
  final String modelId;

  final String? apiKey;
  final String? baseUrl;

  @override
  String get provider => 'openai';

  @override
  String get specificationVersion => 'v3';

  @override
  Future<ImageModelV3GenerateResult> doGenerate(
    ImageModelV3CallOptions options,
  ) async {
    final client = _openAiDio(apiKey: apiKey, baseUrl: baseUrl);
    final providerOptions = options.providerOptions != null
        ? options.providerOptions![provider]
        : null;
    final response = await client.post<Map<String, dynamic>>(
      '/images/generations',
      data: {
        'model': modelId,
        'prompt': options.prompt ?? options.promptObject?.text ?? '',
        if (options.n != null) 'n': options.n,
        if (options.size != null) 'size': options.size,
        'response_format': 'b64_json',
        ...?providerOptions,
      },
      options: Options(headers: options.headers),
    );

    final data = response.data ?? <String, dynamic>{};
    final imagesData = (data['data'] as List?) ?? const [];
    final images = <GeneratedImage>[];
    for (final item in imagesData) {
      final map = (item as Map).cast<String, dynamic>();
      final b64 = map['b64_json']?.toString();
      if (b64 == null || b64.isEmpty) continue;
      images.add(
        GeneratedImage(
          bytes: Uint8List.fromList(base64Decode(b64)),
          mediaType: 'image/png',
        ),
      );
    }

    return ImageModelV3GenerateResult(
      images: images,
      usage: ImageModelV3Usage(imagesGenerated: images.length),
      responses: [
        ImageModelV3ResponseMetadata(
          timestamp: DateTime.now().toUtc(),
          modelId: modelId,
        ),
      ],
    );
  }
}

Dio _openAiDio({String? apiKey, String? baseUrl}) {
  final resolvedApiKey =
      apiKey ?? const String.fromEnvironment('OPENAI_API_KEY');
  final client = Dio(
    BaseOptions(
      baseUrl: baseUrl ?? 'https://api.openai.com/v1',
      headers: {
        if (resolvedApiKey.isNotEmpty)
          'Authorization': 'Bearer $resolvedApiKey',
        'Content-Type': 'application/json',
      },
      responseType: ResponseType.json,
    ),
  );
  return client;
}

List<Map<String, dynamic>> _toOpenAiMessages(LanguageModelV3Prompt prompt) {
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
          'content': _toOpenAiToolResultText(toolPart),
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

    final contentParts = _toOpenAiContentParts(message.content);
    if (contentParts != null && contentParts.isNotEmpty) {
      out.add({'role': role, 'content': contentParts});
      continue;
    }

    out.add({'role': role, 'content': text});
  }

  return out;
}

Object _toOpenAiToolChoice(LanguageModelV3ToolChoice choice) {
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

LanguageModelV3FinishReason _mapOpenAiFinishReason(String? reason) {
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

List<Map<String, dynamic>>? _toOpenAiContentParts(
  List<LanguageModelV3ContentPart> parts,
) {
  final out = <Map<String, dynamic>>[];
  for (final part in parts) {
    if (part is LanguageModelV3TextPart) {
      out.add({'type': 'text', 'text': part.text});
      continue;
    }
    if (part is LanguageModelV3ImagePart) {
      final imageUrl = _toOpenAiImageUrl(part.image, part.mediaType);
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
      final imageUrl = _toOpenAiImageUrl(part.data, part.mediaType);
      if (imageUrl != null) {
        out.add({
          'type': 'image_url',
          'image_url': {'url': imageUrl},
        });
      }
    }
  }
  return out.isEmpty ? null : out;
}

String? _toOpenAiImageUrl(LanguageModelV3DataContent data, String? mediaType) {
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

String _toOpenAiToolResultText(LanguageModelV3ToolResultPart result) {
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

  return {'type': 'unknown'};
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

class _OpenAISpeechModel implements SpeechModelV1 {
  const _OpenAISpeechModel({required this.modelId, this.apiKey, this.baseUrl});

  @override
  final String modelId;
  final String? apiKey;
  final String? baseUrl;

  @override
  String get provider => 'openai';

  @override
  String get specificationVersion => 'v1';

  @override
  Future<SpeechModelV1GenerateResult> doGenerate(
    SpeechModelV1CallOptions options,
  ) async {
    final client = _openAiDio(apiKey: apiKey, baseUrl: baseUrl);
    final providerOptions = options.providerOptions?['openai'];
    final requestBody = {
      'model': modelId,
      'input': options.text,
      if (options.voice != null) 'voice': options.voice,
      if (options.format != null) 'response_format': options.format,
      if (options.speed != null) 'speed': options.speed,
      ...?providerOptions,
    };
    final response = await client.post<Uint8List>(
      '/audio/speech',
      data: requestBody,
      options: Options(
        responseType: ResponseType.bytes,
        headers: options.headers,
      ),
    );
    final contentType = response.headers.value('content-type') ?? 'audio/mpeg';
    final mediaType = contentType.split(';').first.trim();
    return SpeechModelV1GenerateResult(
      audio: response.data ?? Uint8List(0),
      mediaType: mediaType,
    );
  }
}

class _OpenAITranscriptionModel implements TranscriptionModelV1 {
  const _OpenAITranscriptionModel({
    required this.modelId,
    this.apiKey,
    this.baseUrl,
  });

  @override
  final String modelId;
  final String? apiKey;
  final String? baseUrl;

  @override
  String get provider => 'openai';

  @override
  String get specificationVersion => 'v1';

  @override
  Future<TranscriptionModelV1GenerateResult> doGenerate(
    TranscriptionModelV1CallOptions options,
  ) async {
    final client = _openAiDio(apiKey: apiKey, baseUrl: baseUrl);
    final formData = FormData.fromMap({
      'model': modelId,
      'file': MultipartFile.fromBytes(
        options.audio,
        filename: 'audio.${_audioExtension(options.audioMediaType)}',
        contentType: DioMediaType.parse(options.audioMediaType ?? 'audio/mpeg'),
      ),
      'response_format': 'json',
      if (options.language != null) 'language': options.language,
      if (options.prompt != null) 'prompt': options.prompt,
    });
    final response = await client.post<Map<String, dynamic>>(
      '/audio/transcriptions',
      data: formData,
      options: Options(headers: options.headers),
    );
    final data = response.data ?? <String, dynamic>{};
    return TranscriptionModelV1GenerateResult(
      text: data['text']?.toString() ?? '',
    );
  }

  String _audioExtension(String? mediaType) {
    return switch (mediaType) {
      'audio/mpeg' || 'audio/mp3' => 'mp3',
      'audio/wav' => 'wav',
      'audio/ogg' => 'ogg',
      'audio/flac' => 'flac',
      'audio/mp4' || 'audio/m4a' => 'm4a',
      'audio/webm' => 'webm',
      _ => 'mp3',
    };
  }
}

/// Extracts [reasoningEffort] and [reasoningSummary] from raw [providerOptions],
/// accepting both camelCase (typed class) and snake_case (raw map) keys.
///
/// Returns a record of the two typed values plus the cleaned map with the
/// handled keys removed (so they are not double-written).
(String?, String?, Map<String, dynamic>?) _extractReasoningOptions(
  Map<String, dynamic>? po,
) {
  if (po == null) return (null, null, null);

  final reasoningEffort =
      po['reasoning_effort'] as String? ?? po['reasoningEffort'] as String?;
  final reasoningSummary =
      po['reasoning_summary'] as String? ?? po['reasoningSummary'] as String?;

  final cleaned = Map<String, dynamic>.from(po)
    ..remove('reasoning_effort')
    ..remove('reasoningEffort')
    ..remove('reasoning_summary')
    ..remove('reasoningSummary');

  return (
    reasoningEffort,
    reasoningSummary,
    cleaned.isEmpty ? null : cleaned,
  );
}

extension IterableX<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
