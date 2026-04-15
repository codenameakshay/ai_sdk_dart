import 'dart:async';
import 'dart:convert';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';

/// Groq provider for language models.
///
/// Use [call] to create a language model for a given model ID.
///
/// Example:
/// ```dart
/// final model = groq('llama3-8b-8192');
/// final result = await model.doGenerate(options);
/// ```
class GroqProvider {
  const GroqProvider({this.apiKey, this.baseUrl});

  /// Groq API key (defaults to `GROQ_API_KEY` env variable).
  final String? apiKey;

  /// Base URL — defaults to `https://api.groq.com/openai/v1`.
  final String? baseUrl;

  /// Returns a language model for the given [modelId].
  LanguageModelV3 call(String modelId) => _GroqLanguageModel(
    modelId: modelId,
    apiKey: apiKey,
    baseUrl: baseUrl,
  );
}

/// Default Groq provider instance.
const groq = GroqProvider();

// ---------------------------------------------------------------------------
// HTTP helper
// ---------------------------------------------------------------------------

Dio _groqDio({String? apiKey, String? baseUrl}) {
  final key = apiKey ?? const String.fromEnvironment('GROQ_API_KEY');
  return Dio(
    BaseOptions(
      baseUrl: baseUrl ?? 'https://api.groq.com/openai/v1',
      headers: {
        'Authorization': 'Bearer $key',
        'Content-Type': 'application/json',
      },
    ),
  );
}

// ---------------------------------------------------------------------------
// Language model
// ---------------------------------------------------------------------------

class _GroqLanguageModel implements LanguageModelV3 {
  const _GroqLanguageModel({
    required this.modelId,
    this.apiKey,
    this.baseUrl,
  });

  @override
  final String modelId;
  final String? apiKey;
  final String? baseUrl;

  @override
  String get provider => 'groq';

  @override
  String get specificationVersion => 'v3';

  List<Map<String, dynamic>> _buildMessages(LanguageModelV3Prompt prompt) {
    final messages = <Map<String, dynamic>>[];
    if (prompt.system != null) {
      messages.add({'role': 'system', 'content': prompt.system!});
    }
    for (final msg in prompt.messages) {
      final textContent = msg.content
          .whereType<LanguageModelV3TextPart>()
          .map((p) => p.text)
          .join('\n');
      final role = switch (msg.role) {
        LanguageModelV3Role.user => 'user',
        LanguageModelV3Role.assistant => 'assistant',
        LanguageModelV3Role.tool => 'tool',
        LanguageModelV3Role.system => 'system',
      };
      messages.add({'role': role, 'content': textContent});
    }
    return messages;
  }

  Map<String, dynamic> _buildBody(LanguageModelV3CallOptions options) {
    return <String, dynamic>{
      'model': modelId,
      'messages': _buildMessages(options.prompt),
      if (options.maxOutputTokens != null)
        'max_tokens': options.maxOutputTokens,
      if (options.temperature != null) 'temperature': options.temperature,
      if (options.topP != null) 'top_p': options.topP,
      if (options.seed != null) 'seed': options.seed,
      if (options.stopSequences.isNotEmpty) 'stop': options.stopSequences,
    };
  }

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async {
    final client = _groqDio(apiKey: apiKey, baseUrl: baseUrl);
    final body = _buildBody(options);

    final response = await client.post<Map<String, dynamic>>(
      '/chat/completions',
      data: body,
    );
    final data = response.data!;

    final choices = data['choices'] as List?;
    final firstChoice = choices?.isNotEmpty == true
        ? choices![0] as Map<String, dynamic>
        : null;
    final message = firstChoice?['message'] as Map<String, dynamic>?;
    final text = (message?['content'] as String?) ?? '';
    final rawFinishReason = firstChoice?['finish_reason'] as String?;

    final usage = data['usage'] as Map<String, dynamic>?;

    return LanguageModelV3GenerateResult(
      content: [LanguageModelV3TextPart(text: text)],
      finishReason: _mapFinishReason(rawFinishReason),
      rawFinishReason: rawFinishReason,
      usage: LanguageModelV3Usage(
        inputTokens: (usage?['prompt_tokens'] as num?)?.toInt() ?? 0,
        outputTokens: (usage?['completion_tokens'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  @override
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  ) async {
    final client = _groqDio(apiKey: apiKey, baseUrl: baseUrl);
    final body = _buildBody(options)..['stream'] = true;

    final response = await client.post<ResponseBody>(
      '/chat/completions',
      data: body,
      options: Options(responseType: ResponseType.stream),
    );

    final controller = StreamController<LanguageModelV3StreamPart>();
    unawaited(
      _processStream(response.data!.stream, controller).catchError((Object e) {
        if (!controller.isClosed) {
          controller.add(StreamPartError(error: e));
          controller.close();
        }
      }),
    );

    return LanguageModelV3StreamResult(stream: controller.stream);
  }

  Future<void> _processStream(
    Stream<List<int>> byteStream,
    StreamController<LanguageModelV3StreamPart> controller,
  ) async {
    var buffer = '';
    await for (final bytes in byteStream) {
      buffer += utf8.decode(bytes);
      final lines = buffer.split('\n');
      buffer = lines.removeLast();
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        if (!trimmed.startsWith('data:')) continue;
        final jsonStr = trimmed.substring(5).trim();
        if (jsonStr == '[DONE]') continue;
        try {
          final event = jsonDecode(jsonStr) as Map<String, dynamic>;
          final choices = event['choices'] as List?;
          if (choices == null || choices.isEmpty) continue;
          final choice = choices[0] as Map<String, dynamic>;
          final delta = choice['delta'] as Map<String, dynamic>?;
          final content = delta?['content'] as String?;
          if (content != null) {
            controller.add(StreamPartTextDelta(id: '0', delta: content));
          }
          final finishReason = choice['finish_reason'] as String?;
          if (finishReason != null) {
            final usage = event['usage'] as Map<String, dynamic>?;
            controller.add(
              StreamPartFinish(
                finishReason: _mapFinishReason(finishReason),
                rawFinishReason: finishReason,
                usage: usage != null
                    ? LanguageModelV3Usage(
                        inputTokens:
                            (usage['prompt_tokens'] as num?)?.toInt() ?? 0,
                        outputTokens:
                            (usage['completion_tokens'] as num?)?.toInt() ?? 0,
                      )
                    : null,
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

  LanguageModelV3FinishReason _mapFinishReason(String? reason) {
    return switch (reason) {
      'stop' => LanguageModelV3FinishReason.stop,
      'length' => LanguageModelV3FinishReason.length,
      'tool_calls' => LanguageModelV3FinishReason.toolCalls,
      _ => LanguageModelV3FinishReason.other,
    };
  }
}
