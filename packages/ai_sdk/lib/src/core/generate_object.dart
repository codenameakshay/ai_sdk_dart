import 'dart:convert';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';

import '../errors/ai_errors.dart';
import '../messages/model_message.dart';
import '../tools/tool.dart';

class GenerateObjectResult<T> {
  const GenerateObjectResult({
    required this.object,
    required this.response,
    required this.rawJson,
  });

  final T object;
  final LanguageModelV3GenerateResult response;
  final Map<String, dynamic> rawJson;
}

Future<GenerateObjectResult<T>> generateObject<T>({
  required LanguageModelV3 model,
  required Schema<T> schema,
  String? system,
  String? prompt,
  List<ModelMessage>? messages,
  int? maxOutputTokens,
  double? temperature,
  double? topP,
}) async {
  final normalizedMessages = <LanguageModelV3Message>[
    if (prompt != null)
      LanguageModelV3Message(
        role: LanguageModelV3Role.user,
        content: [LanguageModelV3TextPart(text: prompt)],
      ),
    ...?messages?.map(
      (m) => LanguageModelV3Message(
        role: switch (m.role) {
          ModelMessageRole.system => LanguageModelV3Role.system,
          ModelMessageRole.user => LanguageModelV3Role.user,
          ModelMessageRole.assistant => LanguageModelV3Role.assistant,
          ModelMessageRole.tool => LanguageModelV3Role.tool,
        },
        content: m.parts ?? [LanguageModelV3TextPart(text: m.content ?? '')],
      ),
    ),
  ];

  final instruction = [
    if (system != null && system.isNotEmpty) system,
    'Return a single JSON object that matches this schema exactly:',
    jsonEncode(schema.jsonSchema),
    'Do not include markdown fences or extra text.',
  ].join('\n');

  final response = await model.doGenerate(
    LanguageModelV3CallOptions(
      prompt: LanguageModelV3Prompt(
        system: instruction,
        messages: normalizedMessages,
      ),
      maxOutputTokens: maxOutputTokens,
      temperature: temperature,
      topP: topP,
    ),
  );

  final text = response.content
      .whereType<LanguageModelV3TextPart>()
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
  List<LanguageModelV3ContentPart> parts,
) {
  final text = parts
      .whereType<LanguageModelV3TextPart>()
      .map((part) => part.text)
      .join();
  if (text.isEmpty) {
    throw const AiNoContentGeneratedError('No JSON content was generated.');
  }

  final parsed = _safeParseJson(text.trim());
  if (parsed is Map<String, dynamic>) {
    return parsed;
  }
  if (parsed is Map) {
    return parsed.cast<String, dynamic>();
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
