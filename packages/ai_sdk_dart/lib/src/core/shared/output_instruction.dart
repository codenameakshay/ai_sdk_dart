import 'dart:convert';

import '../../output/output.dart';

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
