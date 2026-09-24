import 'dart:async';
import 'dart:convert';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';

/// Google Generative AI provider for Gemini and embedding models.
///
/// Use [call] for language models, [embedding] for embeddings.
///
/// Example:
/// ```dart
/// final model = google('gemini-1.5-flash');
/// final result = await generateText(model: model, prompt: 'Hello');
/// ```
class GoogleGenerativeAIProvider {
  GoogleGenerativeAIProvider({
    this.apiKey,
    this.baseUrl,
    CredentialProvider? credentialProvider,
    Dio? client,
  }) : _credentialProvider =
           credentialProvider ??
           (() => apiKey ?? const String.fromEnvironment('GOOGLE_API_KEY')),
       _client = client ?? _googleDio(baseUrl: baseUrl),
       _ownsClient = client == null;

  /// API key (defaults to `GOOGLE_API_KEY` environment variable).
  final String? apiKey;

  /// Base URL for the API.
  final String? baseUrl;

  final CredentialProvider _credentialProvider;
  final Dio _client;
  final bool _ownsClient;

  Future<String> _apiKey() async {
    final key = await _credentialProvider();
    if (key == null || key.isEmpty) {
      throw StateError('Missing GOOGLE_API_KEY for Google provider.');
    }
    return key;
  }

  void dispose({bool force = true}) {
    if (_ownsClient) {
      _client.close(force: force);
    }
  }

  /// Returns a language model for the given [modelId].
  LanguageModelV4 call(String modelId) =>
      _GoogleLanguageModel(modelId: modelId, client: _client, apiKey: _apiKey);

  /// Returns an embedding model for the given [modelId].
  EmbeddingModelV2<String> embedding(String modelId) =>
      _GoogleEmbeddingModel(modelId: modelId, client: _client, apiKey: _apiKey);
}

/// Default Google Generative AI provider instance.
final google = GoogleGenerativeAIProvider();

class _GoogleLanguageModel extends LanguageModelV4 {
  _GoogleLanguageModel({
    required this.modelId,
    required this.client,
    required this.apiKey,
  });

  @override
  final String modelId;
  final Dio client;
  final CredentialProvider apiKey;

  @override
  String get provider => 'google';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    final cancellation = DioCancellationScope(options.abortSignal);
    late final String resolvedApiKey;
    try {
      resolvedApiKey = await runWithAbortSignal(
        () async => (await apiKey())!,
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
    final modelPath = _modelPath(modelId);
    final providerOptions = _googleProviderOptions(options.providerOptions);
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
        if (options.responseFormat
            case final LanguageModelV4JsonResponseFormat format) ...{
          'responseMimeType': 'application/json',
          if (format.schema != null) 'responseJsonSchema': format.schema,
        },
        if (_googleThinkingConfig(modelId, options) case final config?)
          'thinkingConfig': config,
      },
      if (options.tools.isNotEmpty) ...{
        'tools': _buildGoogleTools(options.tools),
      },
      ..._googleToolChoicePayload(options.toolChoice),
      ...?providerOptions,
    };

    final Response<Map<String, dynamic>> response;
    try {
      response = await client.post<Map<String, dynamic>>(
        '/$modelPath:generateContent',
        queryParameters: {'key': resolvedApiKey},
        data: requestBody,
        options: Options(headers: options.headers),
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
      final rawCandidates = data['candidates'];
      if (rawCandidates is List) {
        for (final candidate in rawCandidates) {
          if (candidate is! Map) throw StateError('candidate is not an object');
          final content = candidate['content'];
          if (content is Map) {
            final parts = content['parts'];
            if (parts is List && parts.any((part) => part is! Map)) {
              throw StateError('content part is not an object');
            }
            if (parts != null && parts is! List) {
              throw StateError('content parts are not a list');
            }
          } else if (content != null) {
            throw StateError('candidate content is not an object');
          }
        }
      } else if (rawCandidates != null) {
        throw StateError('candidates are not a list');
      }
      final usage = data['usageMetadata'];
      if (usage != null && usage is! Map) {
        throw StateError('usage metadata is not an object');
      }
    } on Object catch (error) {
      throw _invalidResponse(response, error);
    }
    try {
      final candidates = (data['candidates'] as List?) ?? const [];
      final first = candidates.isNotEmpty
          ? (candidates.first as Map).cast<String, dynamic>()
          : <String, dynamic>{};

      final content = <LanguageModelV4ContentPart>[];
      final contentObj =
          (first['content'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      final parts = (contentObj['parts'] as List?) ?? const [];
      for (final part in parts) {
        final partMap = (part as Map).cast<String, dynamic>();
        if (partMap['text'] is String) {
          final text = partMap['text'].toString();
          if (text.isNotEmpty) {
            if (partMap['thought'] == true) {
              content.add(
                LanguageModelV4ReasoningPart(
                  text: text,
                  providerOptions: {
                    provider: {
                      'thought': true,
                      if (partMap['thoughtSignature'] != null)
                        'thoughtSignature': partMap['thoughtSignature'],
                    },
                  },
                ),
              );
            } else {
              content.add(LanguageModelV4TextPart(text: text));
            }
          }
        }
        final functionCall = (partMap['functionCall'] as Map?)
            ?.cast<String, dynamic>();
        if (functionCall != null) {
          final toolCall = _parseGoogleFunctionCall(functionCall);
          content.add(
            LanguageModelV4ToolCallPart(
              toolCallId: toolCall.id ?? prefixedId('tool'),
              toolName: toolCall.toolName,
              input: toolCall.input,
              providerOptions: _googleThoughtOptions(partMap),
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
                LanguageModelV4FilePart(
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
              LanguageModelV4FilePart(
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
          LanguageModelV4SourcePart(
            id: 'google_source_$i',
            url: url,
            title: web['title']?.toString(),
            providerMetadata: chunk,
          ),
        );
      }

      final usage = (data['usageMetadata'] as Map?)?.cast<String, dynamic>();
      final warnings = _readGoogleWarnings(data);
      return LanguageModelV4GenerateResult(
        content: content,
        finishReason: _mapGoogleFinishReason(first['finishReason']?.toString()),
        rawFinishReason: first['finishReason']?.toString(),
        usage: usage == null ? null : _googleUsageFrom(usage),
        warnings: warnings,
        request: LanguageModelV4RequestMetadata(body: requestBody),
        response: LanguageModelV4ResponseMetadata(
          modelId: modelId,
          timestamp: DateTime.now().toUtc(),
          headers: response.headers.map.map(
            (key, value) => MapEntry(key, value.join(',')),
          ),
          body: data,
        ),
      );
    } on Object catch (error) {
      throw _invalidResponse(response, error);
    }
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    final cancellation = DioCancellationScope(options.abortSignal);
    late final String resolvedApiKey;
    try {
      resolvedApiKey = await runWithAbortSignal(
        () async => (await apiKey())!,
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
    final modelPath = _modelPath(modelId);
    final providerOptions = _googleProviderOptions(options.providerOptions);
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
        if (options.responseFormat
            case final LanguageModelV4JsonResponseFormat format) ...{
          'responseMimeType': 'application/json',
          if (format.schema != null) 'responseJsonSchema': format.schema,
        },
        if (_googleThinkingConfig(modelId, options) case final config?)
          'thinkingConfig': config,
      },
      if (options.tools.isNotEmpty) ...{
        'tools': _buildGoogleTools(options.tools),
      },
      ..._googleToolChoicePayload(options.toolChoice),
      ...?providerOptions,
    };
    final Response<ResponseBody> response;
    try {
      response = await client.post<ResponseBody>(
        '/$modelPath:streamGenerateContent',
        queryParameters: {'alt': 'sse', 'key': resolvedApiKey},
        data: requestBody,
        options: Options(
          responseType: ResponseType.stream,
          headers: options.headers,
        ),
        cancelToken: cancellation.token,
      );
    } on DioException catch (e) {
      await cancellation.dispose();
      throw await apiErrorFromDioException(e, provider: provider);
    }

    final body = response.data;
    if (body == null) {
      // Defensive; Dio stream body is never null on a 200 streaming response.
      // coverage:ignore-start
      await cancellation.dispose();
      throw StateError('Google stream response body is null.');
      // coverage:ignore-end
    }

    final controller = StreamController<LanguageModelV4StreamPart>();
    controller.onCancel = () async {
      final token = cancellation.token;
      if (token != null && !token.isCancelled) {
        token.cancel('stream subscription cancelled');
      }
      await cancellation.dispose();
    };
    var textStarted = false;
    var streamStarted = false;
    final activeToolCalls = <int, _GoogleStreamFunctionCallState>{};
    final activeReasoning = <int, _GoogleStreamReasoningState>{};
    LanguageModelV4Usage? streamUsage;
    final warnings = <LanguageModelV4Warning>[];
    Map<String, dynamic>? lastChunk;
    final responseHeaders = response.headers.map.map(
      (key, value) => MapEntry(key, value.join(',')),
    );
    final responseTimestamp = DateTime.now().toUtc();

    unawaited(() async {
      try {
        await for (final payload in sseDataLines(body.stream)) {
          final json = _safeParseMap(payload);
          if (json == null) continue;
          lastChunk = json;
          warnings.addAll(_readGoogleWarnings(json));
          if (!streamStarted) {
            streamStarted = true;
            controller.add(
              StreamPartStreamStart(warnings: List.unmodifiable(warnings)),
            );
          }
          if (options.includeRawChunks) {
            controller.add(StreamPartRaw(rawValue: json));
          }
          final usage = (json['usageMetadata'] as Map?)
              ?.cast<String, dynamic>();
          if (usage != null) {
            streamUsage = _googleUsageFrom(usage);
          }
          final candidates = (json['candidates'] as List?) ?? const [];
          if (candidates.isEmpty) continue;
          final first = (candidates.first as Map).cast<String, dynamic>();
          final content =
              (first['content'] as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{};
          final parts = (content['parts'] as List?) ?? const [];
          for (var partIndex = 0; partIndex < parts.length; partIndex++) {
            final part = parts[partIndex];
            final map = (part as Map).cast<String, dynamic>();
            final text = map['text']?.toString();
            if (text != null && text.isNotEmpty) {
              if (map['thought'] == true) {
                final id = 'reasoning-$partIndex';
                activeReasoning.putIfAbsent(partIndex, () {
                  controller.add(
                    StreamPartReasoningStart(
                      id: id,
                      providerMetadata: {
                        provider: {
                          'thought': true,
                          if (map['thoughtSignature'] != null)
                            'thoughtSignature': map['thoughtSignature'],
                        },
                      },
                    ),
                  );
                  return _GoogleStreamReasoningState(id);
                });
                controller.add(StreamPartReasoningDelta(id: id, delta: text));
              } else {
                if (!textStarted) {
                  textStarted = true;
                  controller.add(const StreamPartTextStart(id: 'text-0'));
                }
                controller.add(StreamPartTextDelta(id: 'text-0', delta: text));
              }
            }

            final functionCall = (map['functionCall'] as Map?)
                ?.cast<String, dynamic>();
            if (functionCall != null) {
              final toolCall = _parseGoogleFunctionCall(functionCall);
              var state = activeToolCalls[partIndex];
              if (state == null || state.toolName != toolCall.toolName) {
                if (state != null) {
                  _emitGoogleToolCall(controller, state);
                }
                state = _GoogleStreamFunctionCallState(
                  toolCallId: toolCall.id ?? prefixedId('tool'),
                  toolName: toolCall.toolName,
                  input: toolCall.input,
                  providerOptions: _googleThoughtOptions(map),
                );
                activeToolCalls[partIndex] = state;
                controller.add(
                  StreamPartToolInputStart(
                    id: state.toolCallId,
                    toolName: state.toolName,
                  ),
                );
              }

              final argsDelta = _googleFunctionArgsDelta(
                previous: state.argsText,
                current: toolCall.argsText,
              );
              state
                ..input = toolCall.input
                ..argsText = toolCall.argsText;
              if (argsDelta.isNotEmpty) {
                controller.add(
                  StreamPartToolInputDelta(
                    id: state.toolCallId,
                    delta: argsDelta,
                  ),
                );
              }
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
                    file: LanguageModelV4FilePart(
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
                    file: LanguageModelV4FilePart(
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
                source: LanguageModelV4SourcePart(
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
            for (final state in activeToolCalls.values.toList()) {
              _emitGoogleToolCall(controller, state);
            }
            activeToolCalls.clear();
            for (final state in activeReasoning.values) {
              controller.add(StreamPartReasoningEnd(id: state.id));
            }
            activeReasoning.clear();
            controller.add(
              StreamPartResponseMetadata(
                metadata: LanguageModelV4ResponseMetadata(
                  modelId: modelId,
                  timestamp: responseTimestamp,
                  headers: responseHeaders,
                  body: lastChunk,
                ),
              ),
            );
            controller.add(
              StreamPartFinish(
                finishReason: _mapGoogleFinishReason(finishReason),
                rawFinishReason: finishReason,
                usage: streamUsage ?? const LanguageModelV4Usage(),
                providerMetadata: {
                  provider: {
                    'model': modelId,
                    'timestamp': DateTime.now().toUtc().toIso8601String(),
                    if (warnings.isNotEmpty)
                      'warnings': warnings
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
        await cancellation.dispose();
      }
    }());

    return LanguageModelV4StreamResult(
      stream: controller.stream,
      warnings: List.unmodifiable(warnings),
      request: LanguageModelV4RequestMetadata(body: requestBody),
      response: LanguageModelV4ResponseMetadata(
        modelId: modelId,
        timestamp: responseTimestamp,
        headers: responseHeaders,
        body: lastChunk,
      ),
    );
  }
}

class _GoogleEmbeddingModel implements EmbeddingModelV2<String> {
  @override
  int? get maxEmbeddingsPerCall => null;

  @override
  bool get supportsParallelCalls => true;

  _GoogleEmbeddingModel({
    required this.modelId,
    required this.client,
    required this.apiKey,
  });

  @override
  final String modelId;
  final Dio client;
  final CredentialProvider apiKey;

  @override
  String get provider => 'google';

  @override
  String get specificationVersion => 'v2';

  @override
  Future<EmbeddingModelV2GenerateResult<String>> doEmbed(
    EmbeddingModelV2CallOptions<String> options,
  ) async {
    final cancellation = DioCancellationScope(options.abortSignal);
    late final String resolvedApiKey;
    try {
      resolvedApiKey = await runWithAbortSignal(
        () async => (await apiKey())!,
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
    final modelPath = _modelPath(modelId);
    final providerOptions = options.providerOptions != null
        ? options.providerOptions![provider]
        : null;
    final embedRequest = <String, dynamic>{
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
    };
    final Response<Map<String, dynamic>> response;
    try {
      response = await client.post<Map<String, dynamic>>(
        '/$modelPath:batchEmbedContents',
        queryParameters: {'key': resolvedApiKey},
        data: embedRequest,
        options: Options(headers: options.headers),
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
      final rawEmbeddings = data['embeddings'];
      if (rawEmbeddings is! List ||
          rawEmbeddings.length != options.values.length) {
        throw const FormatException(
          'Expected one embedding row for each input.',
        );
      }
      for (final row in rawEmbeddings) {
        if (row is! Map) throw StateError('embedding is not an object');
        final values = row['values'];
        if (values is! List || values.any((value) => value is! num)) {
          throw StateError('embedding values are not numeric');
        }
      }
    } on Object catch (error) {
      throw _invalidResponse(response, error);
    }
    final embeddings = (data['embeddings'] as List?) ?? const [];

    final out = <EmbeddingModelV2Embedding<String>>[];
    for (var i = 0; i < embeddings.length; i++) {
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

Dio _googleDio({String? baseUrl}) => createProviderDio(
  baseUrl: baseUrl ?? 'https://generativelanguage.googleapis.com/v1beta',
  headers: {'content-type': 'application/json'},
);

AiApiCallError _invalidResponse<T>(Response<T> response, [Object? cause]) =>
    AiApiCallError(
      'Google returned an invalid 2xx response body.',
      statusCode: response.statusCode,
      url: response.requestOptions.uri.toString(),
      cause: cause,
    );

String _modelPath(String modelId) {
  if (modelId.startsWith('models/')) return modelId;
  return 'models/$modelId';
}

Map<String, dynamic>? _googleThinkingConfig(
  String modelId,
  LanguageModelV4CallOptions options,
) {
  final model = options.providerOptions?['google'];
  final configured = model is Map ? (model as Map)['thinkingConfig'] : null;
  if (configured is Map) {
    return configured.cast<String, dynamic>();
  }
  final reasoning = options.reasoning;
  if (reasoning == LanguageModelV4Reasoning.providerDefault) return null;
  return _thinkingConfigForModel(
    modelId,
    reasoning,
    maxOutputTokens: options.maxOutputTokens,
  );
}

Map<String, dynamic>? _googleProviderOptions(ProviderOptions? options) {
  final providerOptions = options?["google"];
  if (providerOptions == null) return null;
  final cleaned = Map<String, dynamic>.from(providerOptions)
    ..remove('thinkingConfig');
  return cleaned.isEmpty ? null : cleaned;
}

Map<String, dynamic>? _thinkingConfigForModel(
  String modelId,
  LanguageModelV4Reasoning reasoning, {
  required int? maxOutputTokens,
}) {
  final lower = modelId.toLowerCase();
  final gemini3 = lower.contains('gemini-3');
  if (gemini3) {
    final minimum = lower.contains('flash') ? 'low' : 'minimal';
    final level = switch (reasoning) {
      LanguageModelV4Reasoning.none => minimum,
      LanguageModelV4Reasoning.minimal => minimum,
      LanguageModelV4Reasoning.low => 'low',
      LanguageModelV4Reasoning.medium => 'medium',
      LanguageModelV4Reasoning.high || LanguageModelV4Reasoning.xhigh => 'high',
      LanguageModelV4Reasoning.providerDefault => null,
    };
    return level == null ? null : {'thinkingLevel': level};
  }
  if (reasoning == LanguageModelV4Reasoning.none) {
    return {'thinkingBudget': 0};
  }
  final maximum = lower.contains('2.5-pro') ? 32768 : 24576;
  final output = maxOutputTokens ?? 65536;
  final fraction = switch (reasoning) {
    LanguageModelV4Reasoning.minimal => 0.02,
    LanguageModelV4Reasoning.low => 0.10,
    LanguageModelV4Reasoning.medium => 0.30,
    LanguageModelV4Reasoning.high => 0.60,
    LanguageModelV4Reasoning.xhigh => 0.90,
    LanguageModelV4Reasoning.providerDefault ||
    LanguageModelV4Reasoning.none => 0,
  };
  return {'thinkingBudget': (output * fraction).round().clamp(0, maximum)};
}

List<Map<String, dynamic>> _buildGoogleTools(List<LanguageModelV4Tool> tools) {
  final entries = <Map<String, dynamic>>[];
  final declarations = <Map<String, dynamic>>[];

  void flushDeclarations() {
    if (declarations.isNotEmpty) {
      entries.add({'functionDeclarations': List.of(declarations)});
      declarations.clear();
    }
  }

  for (final tool in tools) {
    switch (tool) {
      case LanguageModelV4FunctionTool():
        declarations.add({
          'name': tool.name,
          if (tool.description != null) 'description': tool.description,
          'parameters': tool.inputSchema,
        });
      case LanguageModelV4ProviderDefinedTool():
        flushDeclarations();
        entries.add({_googleToolKey(tool.id): tool.args});
    }
  }
  flushDeclarations();
  return entries;
}

String _googleToolKey(String id) {
  final raw = id.split('.').last;
  return raw.replaceAllMapped(
    RegExp(r'_([a-z])'),
    (match) => match.group(1)!.toUpperCase(),
  );
}

List<Map<String, dynamic>> _toGoogleContents(
  List<LanguageModelV4Message> messages,
) {
  return messages.map((message) {
    final role = switch (message.role) {
      LanguageModelV4Role.system => 'user',
      LanguageModelV4Role.user => 'user',
      LanguageModelV4Role.assistant => 'model',
      LanguageModelV4Role.tool => 'user',
    };

    final parts = <Map<String, dynamic>>[];
    for (final part in message.content) {
      if (part is LanguageModelV4TextPart) {
        parts.add({'text': part.text});
      } else if (part is LanguageModelV4ImagePart) {
        final imagePart = _toGoogleInlinePart(part.image, part.mediaType);
        if (imagePart != null) {
          parts.add(imagePart);
        }
      } else if (part is LanguageModelV4FilePart) {
        final filePart = _toGoogleInlinePart(part.data, part.mediaType);
        if (filePart != null) {
          parts.add(filePart);
        }
      } else if (part is LanguageModelV4ReasoningFilePart ||
          part is LanguageModelV4DocumentSourcePart) {
        throw UnsupportedError(
          'Google cannot serialize ${part.runtimeType} in a prompt.',
        );
      } else if (part is LanguageModelV4ToolCallPart) {
        final thought = part.providerOptions?['google'];
        parts.add({
          'functionCall': {
            if (part.toolCallId.isNotEmpty) 'id': part.toolCallId,
            'name': part.toolName,
            'args': part.input,
          },
          if (thought is Map && thought['thoughtSignature'] != null)
            'thoughtSignature': thought['thoughtSignature'],
        });
      } else if (part is LanguageModelV4ReasoningPart) {
        final thought = part.providerOptions?['google'];
        parts.add({
          'text': part.text,
          'thought': true,
          if (thought is Map && thought['thoughtSignature'] != null)
            'thoughtSignature': thought['thoughtSignature'],
        });
      } else if (part is LanguageModelV4ToolResultPart) {
        parts.add({
          'functionResponse': {
            if (part.toolCallId.isNotEmpty) 'id': part.toolCallId,
            'name': part.toolName,
            'response': {
              'isError': part.isError,
              'output': _toGoogleToolResultOutput(part.output),
            },
          },
        });
      }
    }

    if (parts.isEmpty) {
      final fallbackText = message.content
          .whereType<LanguageModelV4TextPart>()
          .map((e) => e.text)
          .join('\n');
      parts.add({'text': fallbackText});
    }

    return {'role': role, 'parts': parts};
  }).toList();
}

LanguageModelV4FinishReason _mapGoogleFinishReason(String? reason) {
  return switch (reason) {
    'STOP' => LanguageModelV4FinishReason.stop,
    'MAX_TOKENS' => LanguageModelV4FinishReason.length,
    'SAFETY' => LanguageModelV4FinishReason.contentFilter,
    'RECITATION' => LanguageModelV4FinishReason.contentFilter,
    'OTHER' => LanguageModelV4FinishReason.other,
    null => LanguageModelV4FinishReason.unknown,
    _ => LanguageModelV4FinishReason.other,
  };
}

Map<String, dynamic>? _safeParseMap(String input) {
  try {
    final decoded = jsonDecode(input);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

_GoogleFunctionCall _parseGoogleFunctionCall(
  Map<String, dynamic> functionCall,
) {
  final rawArgs = functionCall['args'];
  final input = rawArgs is Map
      ? rawArgs.cast<String, dynamic>()
      : (rawArgs ?? const {});
  return _GoogleFunctionCall(
    id: functionCall['id']?.toString(),
    toolName: functionCall['name']?.toString() ?? 'unknown_tool',
    input: input,
    argsText: _googleFunctionArgsText(rawArgs, input),
  );
}

String _googleFunctionArgsText(Object? rawArgs, Object input) =>
    switch (rawArgs) {
      String value => value,
      null => jsonEncode(input),
      _ => jsonEncode(rawArgs),
    };

String _googleFunctionArgsDelta({
  required String previous,
  required String current,
}) {
  if (current.isEmpty || current == previous) return '';
  if (current.startsWith(previous)) {
    return current.substring(previous.length);
  }
  return current;
}

void _emitGoogleToolCall(
  StreamController<LanguageModelV4StreamPart> controller,
  _GoogleStreamFunctionCallState state,
) {
  controller.add(StreamPartToolInputEnd(id: state.toolCallId));
  controller.add(
    StreamPartToolCall(
      toolCall: LanguageModelV4ToolCallPart(
        toolCallId: state.toolCallId,
        toolName: state.toolName,
        input: state.input,
        providerOptions: state.providerOptions,
      ),
    ),
  );
}

/// Gemini's `promptTokenCount` already includes cached tokens, so `total`
/// remains the reported prompt total and the uncached remainder is surfaced via
/// `noCache`.
LanguageModelV4Usage _googleUsageFrom(Map<String, dynamic> usage) {
  final inputTokens = intOrNull(usage['promptTokenCount']);
  final cacheRead = intOrNull(usage['cachedContentTokenCount']);
  return LanguageModelV4Usage(
    inputTokens: LanguageModelV4InputTokenUsage(
      total: inputTokens,
      noCache: cacheRead == null || inputTokens == null
          ? null
          : inputTokens - cacheRead,
      cacheRead: cacheRead,
    ),
    outputTokens: LanguageModelV4OutputTokenUsage(
      total: intOrNull(usage['candidatesTokenCount']),
    ),
    raw: usage,
  );
}

class _GoogleFunctionCall {
  const _GoogleFunctionCall({
    this.id,
    required this.toolName,
    required this.input,
    required this.argsText,
  });

  final String? id;
  final String toolName;
  final Object input;
  final String argsText;
}

class _GoogleStreamFunctionCallState {
  _GoogleStreamFunctionCallState({
    required this.toolCallId,
    required this.toolName,
    required this.input,
    this.providerOptions,
  });

  final String toolCallId;
  final String toolName;
  Object input;
  final Map<String, dynamic>? providerOptions;
  String argsText = '';
}

class _GoogleStreamReasoningState {
  _GoogleStreamReasoningState(this.id);

  final String id;
}

Map<String, dynamic>? _toGoogleInlinePart(
  LanguageModelV4DataContent data,
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

  final b64 = dataContentToBase64(data);
  if (b64 == null) return null;
  return {
    'inlineData': {
      'mimeType': mediaType ?? 'application/octet-stream',
      'data': b64,
    },
  };
}

Object _toGoogleToolResultOutput(LanguageModelV4ToolResultOutput output) {
  return switch (output) {
    ToolResultOutputText(:final text) => {'type': 'text', 'text': text},
    ToolResultOutputErrorText(:final text) => {
      'type': 'error-text',
      'text': text,
    },
    ToolResultOutputJson(:final value) => {'type': 'json', 'value': value},
    ToolResultOutputErrorJson(:final value) => {
      'type': 'error-json',
      'value': value,
    },
    ToolResultOutputExecutionDenied(:final reason, :final approvalId) => {
      'type': 'execution-denied',
      'reason': reason,
      if (approvalId != null) 'approvalId': approvalId,
    },
    ToolResultOutputContent(:final parts) => {
      'type': 'content',
      'parts': parts.map(_toGoogleToolResultPart).toList(),
    },
  };
}

Map<String, dynamic> _toGoogleToolResultPart(LanguageModelV4ContentPart part) {
  if (part is LanguageModelV4TextPart) {
    return {'type': 'text', 'text': part.text};
  }
  if (part is LanguageModelV4ImagePart) {
    final inline = _toGoogleInlinePart(part.image, part.mediaType);
    if (inline == null) {
      throw UnsupportedError(
        'Google cannot serialize this tool image content.',
      );
    }
    return {'type': 'image', ...inline};
  }
  if (part is LanguageModelV4FilePart) {
    final inline = _toGoogleInlinePart(part.data, part.mediaType);
    if (inline == null) {
      throw UnsupportedError('Google cannot serialize this tool file content.');
    }
    return {
      'type': 'file',
      'mediaType': part.mediaType,
      if (part.filename != null) 'filename': part.filename,
      ...inline,
    };
  }
  throw UnsupportedError(
    'Google cannot serialize ${part.runtimeType} tool result content.',
  );
}

List<LanguageModelV4Warning> _readGoogleWarnings(Map<String, dynamic> payload) {
  final warnings = <LanguageModelV4Warning>[];
  final promptFeedback = payload['promptFeedback'];
  if (promptFeedback != null) {
    warnings.add(
      LanguageModelV4OtherWarning(
        message: 'promptFeedback: ${jsonEncode(promptFeedback)}',
      ),
    );
  }
  final list = payload['warnings'];
  if (list is List) {
    for (final item in list) {
      final warning = _parseGoogleWarning(item);
      if (warning != null) warnings.add(warning);
    }
  }
  return warnings;
}

LanguageModelV4Warning? _parseGoogleWarning(Object? item) {
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

Map<String, dynamic> _googleToolChoicePayload(
  LanguageModelV4ToolChoice? choice,
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

/// Maps a [DioException] from a non-2xx response to a typed [AiApiCallError]
/// carrying the provider's message/status/code. Drains a streamed error body
/// (`ResponseType.stream`) when present so the message is recoverable.
Map<String, dynamic>? _googleThoughtOptions(Map<String, dynamic> functionCall) {
  final signature = functionCall['thoughtSignature'];
  if (signature == null) return null;
  return {
    'google': {'thoughtSignature': signature},
  };
}
