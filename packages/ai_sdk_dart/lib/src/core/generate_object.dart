import 'package:ai_sdk_provider/ai_sdk_provider.dart';

import '../messages/model_message.dart';
import '../output/output.dart';
import '../tools/tool.dart';
import 'shared/common_helpers.dart';
import 'shared/output_instruction.dart';
import 'shared/operation_scope.dart';
import 'shared/strict_json.dart';
import 'body_inclusion.dart';

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
  String? instructions,
  String? system,
  String? prompt,
  List<ModelMessage>? messages,
  int? maxOutputTokens,
  double? temperature,
  double? topP,
  Duration? timeout,
  CancellationToken? abortSignal,
  bool allowSystemInMessages = false,
  BodyInclusionPolicy bodyInclusion = const BodyInclusionPolicy.none(),
}) async {
  rejectSystemMessages(
    messages ?? const [],
    allowSystemInMessages: allowSystemInMessages,
  );
  final normalizedMessages = <LanguageModelV4Message>[
    if (prompt != null)
      LanguageModelV4Message(
        role: LanguageModelV4Role.user,
        content: [LanguageModelV4TextPart(text: prompt)],
      ),
    ...?messages?.map(toLanguageModelMessage),
  ];

  final output = Output.object(schema: schema);

  try {
    return await runOperation(
      abortSignal: abortSignal,
      timeout: timeout,
      operation: (signal) async {
        final response = await model.doGenerate(
          LanguageModelV4CallOptions(
            prompt: LanguageModelV4Prompt(
              system: buildOutputSystemInstruction(
                instructions ?? system,
                output,
              ),
              messages: normalizedMessages,
            ),
            maxOutputTokens: maxOutputTokens,
            temperature: temperature,
            topP: topP,
            responseFormat: buildResponseFormat(output),
            abortSignal: signal,
          ),
        );
        final text = response.content
            .whereType<LanguageModelV4TextPart>()
            .map((part) => part.text)
            .join();
        try {
          final jsonMap = parseCompleteJsonObject(text);
          return GenerateObjectResult<T>(
            object: schema.fromJson(jsonMap),
            response: _filterObjectResult(response, bodyInclusion),
            rawJson: jsonMap,
          );
        } catch (error) {
          throw AiNoObjectGeneratedError(
            message: 'Failed to generate a valid object.',
            text: text,
            response: _filterObjectMetadata(response.response, bodyInclusion),
            usage: response.usage,
            cause: error,
          );
        }
      },
    );
  } catch (error, stackTrace) {
    final filtered = filterBodyBearingError(error, bodyInclusion);
    Error.throwWithStackTrace(filtered, stackTrace);
  }
}

LanguageModelV4GenerateResult _filterObjectResult(
  LanguageModelV4GenerateResult response,
  BodyInclusionPolicy policy,
) => LanguageModelV4GenerateResult(
  content: response.content,
  finishReason: response.finishReason,
  rawFinishReason: response.rawFinishReason,
  usage: response.usage,
  warnings: response.warnings,
  request: response.request == null
      ? null
      : LanguageModelV4RequestMetadata(
          body: policy.requestBody ? response.request!.body : null,
        ),
  response: response.response == null
      ? null
      : LanguageModelV4ResponseMetadata(
          id: response.response!.id,
          modelId: response.response!.modelId,
          timestamp: response.response!.timestamp,
          headers: response.response!.headers,
          body: policy.responseBody ? response.response!.body : null,
        ),
  providerMetadata: response.providerMetadata,
);

LanguageModelV4ResponseMetadata? _filterObjectMetadata(
  LanguageModelV4ResponseMetadata? metadata,
  BodyInclusionPolicy policy,
) => metadata == null
    ? null
    : LanguageModelV4ResponseMetadata(
        id: metadata.id,
        modelId: metadata.modelId,
        timestamp: metadata.timestamp,
        headers: metadata.headers,
        body: policy.responseBody ? metadata.body : null,
      );
