import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';

import '../../output/output.dart';

@internal
String buildOutputSystemInstruction<T>(String? system, Output<T> output) {
  switch (output) {
    case TextOutput():
      return system ?? '';
    case ObjectOutput<T>(:final schema):
      return [
        if (system != null && system.isNotEmpty) system,
        'Return a single JSON object that matches this schema exactly:',
        jsonEncode(schema.jsonSchema),
        'Do not include markdown fences or extra text.',
      ].join('\n');
    case ArrayOutput(:final element):
      return [
        if (system != null && system.isNotEmpty) system,
        'Return a single JSON array where each element matches this schema exactly:',
        jsonEncode(element.jsonSchema),
        'Do not include markdown fences or extra text.',
      ].join('\n');
    case ChoiceOutput(:final options):
      return [
        if (system != null && system.isNotEmpty) system,
        'Return exactly one of these values:',
        options.join(', '),
        'Do not include markdown fences or extra text.',
      ].join('\n');
    case JsonOutput():
      return [
        if (system != null && system.isNotEmpty) system,
        'Return valid JSON only. Do not include markdown fences or extra text.',
      ].join('\n');
  }
}

@internal
LanguageModelV4ResponseFormat buildResponseFormat<T>(Output<T> output) {
  return switch (output) {
    TextOutput() => const LanguageModelV4TextResponseFormat(),
    ObjectOutput(:final schema, :final name, :final description) =>
      LanguageModelV4JsonResponseFormat(
        schema: schema.jsonSchema,
        name: name,
        description: description,
      ),
    ArrayOutput(:final element, :final name, :final description) =>
      LanguageModelV4JsonResponseFormat(
        schema: {'type': 'array', 'items': element.jsonSchema},
        name: name,
        description: description,
      ),
    ChoiceOutput(:final options, :final name, :final description) =>
      LanguageModelV4JsonResponseFormat(
        schema: {'type': 'string', 'enum': options},
        name: name,
        description: description,
      ),
    JsonOutput(:final name, :final description) =>
      LanguageModelV4JsonResponseFormat(name: name, description: description),
  };
}
