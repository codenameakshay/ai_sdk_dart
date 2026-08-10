import 'dart:convert';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:meta/meta.dart';

import '../../messages/model_message.dart';
import '../../tools/tool.dart';

@internal
LanguageModelV3Message toLanguageModelMessage(ModelMessage message) {
  return LanguageModelV3Message(
    role: switch (message.role) {
      ModelMessageRole.system => LanguageModelV3Role.system,
      ModelMessageRole.user => LanguageModelV3Role.user,
      ModelMessageRole.assistant => LanguageModelV3Role.assistant,
      ModelMessageRole.tool => LanguageModelV3Role.tool,
    },
    content:
        message.parts ?? [LanguageModelV3TextPart(text: message.content ?? '')],
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
LanguageModelV3Usage? sumUsage(Iterable<LanguageModelV3Usage?> usages) {
  var input = 0;
  var output = 0;
  var total = 0;
  var hasAny = false;

  for (final usage in usages) {
    if (usage == null) {
      continue;
    }
    hasAny = true;
    input += usage.inputTokens ?? 0;
    output += usage.outputTokens ?? 0;
    total += usage.totalTokens ?? 0;
  }

  if (!hasAny) {
    return null;
  }

  return LanguageModelV3Usage(
    inputTokens: input == 0 ? null : input,
    outputTokens: output == 0 ? null : output,
    totalTokens: total == 0 ? null : total,
  );
}
