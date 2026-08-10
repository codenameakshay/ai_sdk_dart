import 'package:ai_sdk_provider/ai_sdk_provider.dart';

import '../core/generate_text.dart';
import '../core/stream_text.dart';
import '../messages/model_message.dart';
import '../stop_conditions/stop_conditions.dart';
import '../tools/tool.dart';

/// Agent that runs tools in a loop to accomplish tasks.
///
/// Mirrors `ToolLoopAgent` from the JS AI SDK v6. Handles the tool-call loop,
/// context management, and stop conditions. Use [generate] or [stream].
///
/// Example:
/// ```dart
/// final agent = ToolLoopAgent(
///   model: model,
///   tools: {...},
///   maxSteps: 5,
/// );
/// final result = await agent.generate(prompt: 'What is the weather?');
/// ```
class ToolLoopAgent {
  ToolLoopAgent({
    required this.model,
    this.instructions,
    this.tools = const {},
    this.maxSteps = 1,
    this.stopConditions = const [],
  });

  final LanguageModelV3 model;
  final String? instructions;
  final ToolSet tools;
  final int maxSteps;
  final List<StopCondition> stopConditions;

  /// Runs the agent in non-streaming mode.
  Future<GenerateTextResult> generate({
    String? prompt,
    List<ModelMessage>? messages,
    CancellationToken? abortSignal,
    Duration? timeout,
  }) {
    return generateText(
      model: model,
      system: instructions,
      prompt: prompt,
      messages: messages,
      tools: tools,
      maxSteps: maxSteps,
      stopConditions: stopConditions,
      abortSignal: abortSignal,
      timeout: timeout,
    );
  }

  /// Runs the agent in streaming mode.
  ///
  /// Pass [toolApprovalResponses] to supply pre-collected tool-approval
  /// decisions (mirrors the JS SDK `addToolApprovalResponse` / `useChat` flow).
  Future<StreamTextResult> stream({
    String? prompt,
    List<ModelMessage>? messages,
    List<LanguageModelV3ToolApprovalResponse> toolApprovalResponses = const [],
    CancellationToken? abortSignal,
    Duration? timeout,
  }) {
    return streamText(
      model: model,
      system: instructions,
      prompt: prompt,
      messages: messages,
      tools: tools,
      maxSteps: maxSteps,
      stopConditions: stopConditions,
      toolApprovalResponses: toolApprovalResponses,
      abortSignal: abortSignal,
      timeout: timeout,
    );
  }
}
