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
  final LanguageModelV3ToolChoice? toolChoice;
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
  required LanguageModelV3ToolChoice? toolChoice,
}) {
  final choice = toolChoice;
  if (choice == null || choice is ToolChoiceAuto) {
    return ResolvedToolSelection(exposedTools: tools, toolChoice: choice);
  }
  if (choice is ToolChoiceNone) {
    return const ResolvedToolSelection(
      exposedTools: {},
      toolChoice: ToolChoiceNone(),
    );
  }
  if (choice is ToolChoiceRequired) {
    if (tools.isEmpty) {
      throw const AiNoSuchToolError(
        'toolChoice "required" cannot be used without tools.',
      );
    }
    return ResolvedToolSelection(exposedTools: tools, toolChoice: choice);
  }
  if (choice is ToolChoiceSpecific) {
    final tool = tools[choice.toolName];
    if (tool == null) {
      throw AiNoSuchToolError(
        'toolChoice requested unknown tool "${choice.toolName}".',
      );
    }
    return ResolvedToolSelection(
      exposedTools: {choice.toolName: tool},
      toolChoice: choice,
    );
  }
  // Defensive: every ToolChoice subtype is handled above.
  return ResolvedToolSelection(
    exposedTools: tools,
    toolChoice: choice,
  ); // coverage:ignore-line
}

@internal
void validateToolChoiceForCalls({
  required Iterable<LanguageModelV3ToolCallPart> toolCalls,
  required ToolSet tools,
  required LanguageModelV3ToolChoice? toolChoice,
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
    if (!tools.containsKey(call.toolName)) {
      throw AiNoSuchToolError(
        'Step $stepNumber called unknown tool "${call.toolName}".',
      );
    }
  }
}
