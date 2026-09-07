import 'package:ai_sdk_provider/ai_sdk_provider.dart';

import '../../output/output.dart';
import '../partial_json.dart';

int emitTrackedArrayElements({
  required ArrayOutput<dynamic> output,
  required List<Object?> elements,
  required List<dynamic> partialValues,
  required void Function(Object? element) onElement,
}) {
  var acceptedCount = 0;
  for (final item in elements) {
    try {
      if (item is Map<String, dynamic>) {
        final value = output.element.fromJson(item);
        partialValues.add(value);
        onElement(value);
        acceptedCount++;
      }
    } catch (_) {}
  }
  return acceptedCount;
}

TOutput? tryParseStreamingPartialOutput<TOutput>(
  Output<TOutput> output,
  String text,
) {
  try {
    return parseStreamingOutput(output, text);
  } catch (_) {
    return null;
  }
}

TOutput parseStreamingOutput<TOutput>(Output<TOutput> output, String text) {
  switch (output) {
    case TextOutput():
      return text as TOutput;
    case ObjectOutput<TOutput>(:final schema):
      final jsonMap = extractStreamingJsonObject(text);
      return schema.fromJson(jsonMap);
    case ArrayOutput(:final element):
      final jsonValue = extractStreamingJsonValue(text);
      if (jsonValue is! List) {
        throw AiInvalidToolInputError(
          'Model did not return a JSON array: $text',
        );
      }
      final list = <dynamic>[];
      for (final item in jsonValue) {
        if (item is Map<String, dynamic>) {
          list.add(element.fromJson(item));
        } else {
          throw AiInvalidToolInputError(
            'Array element is not a JSON object: $item',
          );
        }
      }
      return list as TOutput;
    case ChoiceOutput(:final options):
      final parsed = tryParsePartialJsonValue(
        text,
        phase: PartialJsonParsePhase.streamTextPartial,
        trigger: PartialJsonParseTrigger.candidateClosed,
      );
      final value = switch (parsed) {
        String s => s,
        _ => text.trim(),
      };
      if (!options.contains(value)) {
        throw AiInvalidToolInputError(
          'Model did not return a valid choice: $value',
        );
      }
      return value as TOutput;
    case JsonOutput():
      return extractStreamingJsonValue(text) as TOutput;
  }
}

TOutput parseStreamingOutputWithNoObjectError<TOutput>({
  required Output<TOutput> output,
  required String text,
  required LanguageModelV4Usage? usage,
  required LanguageModelV4ResponseMetadata? response,
}) {
  try {
    return parseStreamingOutput(output, text);
  } catch (error) {
    if (output is TextOutput) {
      rethrow;
    }
    throw AiNoObjectGeneratedError(
      message: 'Failed to generate a valid structured output.',
      text: text,
      response: response,
      usage: usage,
      cause: error,
    );
  }
}

Map<String, dynamic> extractStreamingJsonObject(String text) {
  final parsed = extractStreamingJsonValue(text);
  if (parsed is Map<String, dynamic>) {
    return parsed;
  }
  throw AiInvalidToolInputError('Model did not return a JSON object: $text');
}

Object extractStreamingJsonValue(String text) {
  if (text.trim().isEmpty) {
    throw const AiNoContentGeneratedError('No content was generated.');
  }
  final parsed = tryParsePartialJsonValue(
    text,
    phase: PartialJsonParsePhase.streamTextPartial,
    trigger: PartialJsonParseTrigger.candidateClosed,
  );
  if (parsed == null) {
    throw AiInvalidToolInputError('Model did not return valid JSON: $text');
  }
  return parsed;
}
