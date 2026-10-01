import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:meta/meta.dart';

import '../../tools/tool.dart';

@internal
class ResolvedToolSelection {
  const ResolvedToolSelection({
    required this.exposedTools,
    required this.toolChoice,
  });

  final ToolSet exposedTools;
  final LanguageModelV4ToolChoice? toolChoice;
}

/// Returns true when a provider has already executed a hosted tool call.
/// Provider adapters carry this marker in the typed tool-call contract so the
/// core never invokes a same-named local tool by accident.
@internal
bool isProviderExecutedToolCall(LanguageModelV4ToolCallPart call) {
  return call.providerExecuted;
}

@internal
ToolSet selectActiveTools(ToolSet tools, List<String>? activeToolNames) {
  if (activeToolNames == null) {
    return tools;
  }
  final selected = <String, Tool<dynamic, dynamic>>{};
  for (final toolName in activeToolNames) {
    final tool = tools[toolName];
    if (tool == null) {
      throw AiNoSuchToolError('Active tool "$toolName" was not found.');
    }
    selected[toolName] = tool;
  }
  return selected;
}

@internal
ResolvedToolSelection resolveToolSelection({
  required ToolSet tools,
  required LanguageModelV4ToolChoice? toolChoice,
}) {
  final choice = toolChoice;
  switch (choice) {
    case null:
    case ToolChoiceAuto():
      return ResolvedToolSelection(exposedTools: tools, toolChoice: choice);
    case ToolChoiceNone():
      return const ResolvedToolSelection(
        exposedTools: {},
        toolChoice: ToolChoiceNone(),
      );
    case ToolChoiceRequired():
      if (tools.isEmpty) {
        throw const AiNoSuchToolError(
          'toolChoice "required" cannot be used without tools.',
        );
      }
      return ResolvedToolSelection(exposedTools: tools, toolChoice: choice);
    case ToolChoiceSpecific(:final toolName):
      final tool = tools[toolName];
      if (tool == null) {
        throw AiNoSuchToolError(
          'toolChoice requested unknown tool "$toolName".',
        );
      }
      return ResolvedToolSelection(
        exposedTools: {toolName: tool},
        toolChoice: choice,
      );
  }
}

@internal
void validateToolChoiceForCalls({
  required Iterable<LanguageModelV4ToolCallPart> toolCalls,
  required ToolSet tools,
  required LanguageModelV4ToolChoice? toolChoice,
  required int stepNumber,
}) {
  final calls = toolCalls.toList(growable: false);
  if (toolChoice is ToolChoiceNone && calls.isNotEmpty) {
    throw AiApiCallError(
      'Step $stepNumber produced tool calls while toolChoice is none.',
    );
  }
  if (toolChoice is ToolChoiceRequired && calls.isEmpty) {
    throw AiApiCallError(
      'Step $stepNumber produced no tool calls while toolChoice is required.',
    );
  }
  if (toolChoice is ToolChoiceSpecific) {
    for (final call in calls) {
      if (call.toolName != toolChoice.toolName) {
        throw AiApiCallError(
          'Step $stepNumber called "${call.toolName}" but toolChoice '
          'requires "${toolChoice.toolName}".',
        );
      }
    }
  }
  for (final call in calls) {
    if (isProviderExecutedToolCall(call)) continue;
    if (!tools.containsKey(call.toolName)) {
      throw AiNoSuchToolError(
        'Step $stepNumber called unknown tool "${call.toolName}".',
      );
    }
  }
}
