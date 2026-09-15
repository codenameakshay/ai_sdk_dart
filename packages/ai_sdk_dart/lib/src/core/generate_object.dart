import 'package:ai_sdk_provider/ai_sdk_provider.dart';

import '../messages/model_message.dart';
import '../output/output.dart';
import '../tools/tool.dart';
import 'shared/common_helpers.dart';
import 'shared/output_instruction.dart';
import 'streaming/structured_output.dart';
import 'timeout_helpers.dart';

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

  final output = Output.object(schema: schema);

  final generateCall = model.doGenerate(
    LanguageModelV4CallOptions(
      prompt: LanguageModelV4Prompt(
        system: buildOutputSystemInstruction(system, output),
        messages: normalizedMessages,
      ),
      maxOutputTokens: maxOutputTokens,
      temperature: temperature,
      topP: topP,
      responseFormat: buildResponseFormat(output),
    ),
  );
  final response = await withOptionalTimeout(generateCall, timeout);

  final text = response.content
      .whereType<LanguageModelV4TextPart>()
      .map((part) => part.text)
      .join();

  late final Map<String, dynamic> jsonMap;
  late final T object;
  try {
    jsonMap = extractJsonObject(text);
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
