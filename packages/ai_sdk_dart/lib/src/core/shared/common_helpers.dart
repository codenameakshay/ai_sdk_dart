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
void rejectSystemMessages(
  Iterable<ModelMessage> messages, {
  required bool allowSystemInMessages,
}) {
  if (allowSystemInMessages) return;
  if (messages.any((message) => message.role == ModelMessageRole.system)) {
    throw ArgumentError(
      'System-role messages are rejected by default. Use instructions or '
      'set allowSystemInMessages: true for trusted legacy histories.',
    );
  }
}

@internal
void safeInvoke(void Function() action) {
  try {
    action();
  } catch (_) {}
}

@internal
Object? parseToolInput({
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
  int? inputTotal;
  int? inputNoCache;
  int? inputCacheRead;
  int? inputCacheWrite;
  int? outputTotal;
  int? outputText;
  int? outputReasoning;
  var hasReportedUsage = false;

  for (final usage in usages) {
    if (usage == null) continue;
    final input = usage.inputTokens;
    final output = usage.outputTokens;
    if (usage.raw == null &&
        input.total == null &&
        input.noCache == null &&
        input.cacheRead == null &&
        input.cacheWrite == null &&
        output.total == null &&
        output.text == null &&
        output.reasoning == null) {
      continue;
    }

    hasReportedUsage = true;
    if (input.total case final value?) {
      inputTotal = (inputTotal ?? 0) + value;
    }
    if (input.noCache case final value?) {
      inputNoCache = (inputNoCache ?? 0) + value;
    }
    if (input.cacheRead case final value?) {
      inputCacheRead = (inputCacheRead ?? 0) + value;
    }
    if (input.cacheWrite case final value?) {
      inputCacheWrite = (inputCacheWrite ?? 0) + value;
    }
    if (output.total case final value?) {
      outputTotal = (outputTotal ?? 0) + value;
    }
    if (output.text case final value?) {
      outputText = (outputText ?? 0) + value;
    }
    if (output.reasoning case final value?) {
      outputReasoning = (outputReasoning ?? 0) + value;
    }
  }

  if (!hasReportedUsage) return null;

  return LanguageModelV4Usage(
    inputTokens: LanguageModelV4InputTokenUsage(
      total: inputTotal,
      noCache: inputNoCache,
      cacheRead: inputCacheRead,
      cacheWrite: inputCacheWrite,
    ),
    outputTokens: LanguageModelV4OutputTokenUsage(
      total: outputTotal,
      text: outputText,
      reasoning: outputReasoning,
    ),
  );
}
