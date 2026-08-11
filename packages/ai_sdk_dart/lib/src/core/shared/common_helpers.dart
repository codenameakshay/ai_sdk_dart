import 'dart:convert';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:meta/meta.dart';

import '../../messages/model_message.dart';
import '../../tools/tool.dart';

@internal
LanguageModelV4Message toLanguageModelMessage(ModelMessage message) {
  return LanguageModelV4Message(
    role: switch (message.role) {
      ModelMessageRole.system => LanguageModelV4Role.system,
      ModelMessageRole.user => LanguageModelV4Role.user,
      ModelMessageRole.assistant => LanguageModelV4Role.assistant,
      ModelMessageRole.tool => LanguageModelV4Role.tool,
    },
    content:
        message.parts ?? [LanguageModelV4TextPart(text: message.content ?? '')],
  );
}

@internal
void safeInvoke(void Function() action) {
  try {
    action();
  } catch (_) {}
}

@internal
dynamic parseToolInput({
  required Tool<dynamic, dynamic> tool,
  required Object rawInput,
}) {
  if (tool.dynamic) {
    if (tool.strict == true && rawInput is! Map) {
      throw const AiInvalidToolInputError(
        'Strict dynamic tools require JSON object input.',
      );
    }
    return rawInput;
  }
  if (rawInput is! Map) {
    throw const AiInvalidToolInputError('Tool input is not a JSON object.');
  }
  return tool.inputSchema.fromJson(rawInput.cast<String, dynamic>());
}

@internal
String stringifyToolOutput(Object? output) {
  if (output == null) return 'null';
  if (output is String) return output;
  if (output is num || output is bool) return output.toString();
  try {
    return jsonEncode(output);
  } catch (_) {
    return output.toString();
  }
}

@internal
LanguageModelV4Usage? sumUsage(Iterable<LanguageModelV4Usage?> usages) {
  final inputTotals = <int>[];
  final inputNoCache = <int>[];
  final inputCacheRead = <int>[];
  final inputCacheWrite = <int>[];
  final outputTotals = <int>[];
  final outputText = <int>[];
  final outputReasoning = <int>[];
  var hasReportedUsage = false;

  for (final usage in usages) {
    if (usage == null) continue;
    final input = usage.inputTokens;
    final output = usage.outputTokens;
    final values = [
      input.total,
      input.noCache,
      input.cacheRead,
      input.cacheWrite,
      output.total,
      output.text,
      output.reasoning,
    ];
    if (usage.raw == null && values.every((value) => value == null)) continue;

    hasReportedUsage = true;
    if (input.total case final value?) inputTotals.add(value);
    if (input.noCache case final value?) inputNoCache.add(value);
    if (input.cacheRead case final value?) inputCacheRead.add(value);
    if (input.cacheWrite case final value?) inputCacheWrite.add(value);
    if (output.total case final value?) outputTotals.add(value);
    if (output.text case final value?) outputText.add(value);
    if (output.reasoning case final value?) outputReasoning.add(value);
  }

  if (!hasReportedUsage) return null;

  return LanguageModelV4Usage(
    inputTokens: LanguageModelV4InputTokenUsage(
      total: _sumReported(inputTotals),
      noCache: _sumReported(inputNoCache),
      cacheRead: _sumReported(inputCacheRead),
      cacheWrite: _sumReported(inputCacheWrite),
    ),
    outputTokens: LanguageModelV4OutputTokenUsage(
      total: _sumReported(outputTotals),
      text: _sumReported(outputText),
      reasoning: _sumReported(outputReasoning),
    ),
  );
}

int? _sumReported(List<int> values) {
  if (values.isEmpty) return null;
  return values.fold<int>(0, (sum, value) => sum + value);
}
