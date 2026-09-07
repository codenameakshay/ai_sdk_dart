import 'dart:convert';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';

import '../messages/model_message.dart';
import '../tools/tool.dart';
import 'shared/common_helpers.dart';

/// Result returned by [generateObject].
///
/// Contains the parsed [object], the raw [response], and [rawJson].
/// Throws [AiNoObjectGeneratedError] when the model output cannot be parsed.
class GenerateObjectResult<T> {
  const GenerateObjectResult({
    required this.object,
    required this.response,
    required this.rawJson,
  });

  final T object;
  final LanguageModelV4GenerateResult response;
  final Map<String, dynamic> rawJson;
}

/// Generates a structured JSON object from a schema.
///
/// Dart convenience API for object-only generation. For combined text + tools
/// or structured output in [generateText]/[streamText], use [Output.object]
/// instead. Mirrors the deprecated `generateObject` from the JS AI SDK v6.
///
/// Throws [AiNoObjectGeneratedError] when the model output cannot be parsed.
///
/// Example:
/// ```dart
/// final result = await generateObject(
///   model: model,
///   schema: mySchema,
///   prompt: 'Generate a recipe.',
/// );
/// print(result.object);
/// ```
Future<GenerateObjectResult<T>> generateObject<T>({
  required LanguageModelV4 model,
  required Schema<T> schema,
  String? system,
  String? prompt,
  List<ModelMessage>? messages,
  int? maxOutputTokens,
  double? temperature,
  double? topP,
  Duration? timeout,
}) async {
  final normalizedMessages = <LanguageModelV4Message>[
    if (prompt != null)
      LanguageModelV4Message(
        role: LanguageModelV4Role.user,
        content: [LanguageModelV4TextPart(text: prompt)],
      ),
    ...?messages?.map(toLanguageModelMessage),
  ];

  final instruction = [
    if (system != null && system.isNotEmpty) system,
    'Return a single JSON object that matches this schema exactly:',
    jsonEncode(schema.jsonSchema),
    'Do not include markdown fences or extra text.',
  ].join('\n');

  final generateCall = model.doGenerate(
    LanguageModelV4CallOptions(
      prompt: LanguageModelV4Prompt(
        system: instruction,
        messages: normalizedMessages,
      ),
      maxOutputTokens: maxOutputTokens,
      temperature: temperature,
      topP: topP,
      responseFormat: LanguageModelV4JsonResponseFormat(
        schema: schema.jsonSchema,
      ),
    ),
  );
  final response = await (timeout != null
      ? generateCall.timeout(timeout)
      : generateCall);

  final text = response.content
      .whereType<LanguageModelV4TextPart>()
      .map((part) => part.text)
      .join();

  late final Map<String, dynamic> jsonMap;
  late final T object;
  try {
    jsonMap = _extractJsonObject(response.content);
    object = schema.fromJson(jsonMap);
  } catch (error) {
    throw AiNoObjectGeneratedError(
      message: 'Failed to generate a valid object.',
      text: text,
      response: response.response,
      usage: response.usage,
      cause: error,
    );
  }
  return GenerateObjectResult<T>(
    object: object,
    response: response,
    rawJson: jsonMap,
  );
}

Map<String, dynamic> _extractJsonObject(
  List<LanguageModelV4ContentPart> parts,
) {
  final text = parts
      .whereType<LanguageModelV4TextPart>()
      .map((part) => part.text)
      .join();
  if (text.isEmpty) {
    throw const AiNoContentGeneratedError('No JSON content was generated.');
  }

  final parsed = _safeParseJson(text.trim());
  if (parsed is Map<String, dynamic>) {
    return parsed;
  }

  throw AiInvalidToolInputError('Model did not return a JSON object: $text');
}

Object? _safeParseJson(String text) {
  try {
    return jsonDecode(text);
  } catch (_) {
    final fenceMatch = RegExp(
      r'```(?:json)?\s*([\s\S]+?)\s*```',
    ).firstMatch(text);
    if (fenceMatch != null) {
      final fenced = fenceMatch.group(1);
      if (fenced != null) {
        try {
          return jsonDecode(fenced);
        } catch (_) {
          return null;
        }
      }
    }
    return null;
  }
}
