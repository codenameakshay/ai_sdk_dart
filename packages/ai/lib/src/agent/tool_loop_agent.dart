import 'dart:convert';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';

import '../core/generate_text.dart';
import '../core/stream_text.dart';
import '../messages/model_message.dart';
import '../stop_conditions/stop_conditions.dart';
import '../tools/tool.dart';

/// Class-based multi-step agent API, mirroring AI SDK ToolLoopAgent.
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

  Future<GenerateTextResult> generate({
    String? prompt,
    List<ModelMessage>? messages,
  }) async {
    if (tools.isEmpty || maxSteps <= 1) {
      return generateText(
        model: model,
        system: instructions,
        prompt: prompt,
        messages: messages,
      );
    }

    final promptMessages = <LanguageModelV3Message>[
      if (prompt != null)
        LanguageModelV3Message(
          role: LanguageModelV3Role.user,
          content: [LanguageModelV3TextPart(text: prompt)],
        ),
      ...?messages?.map(_toLanguageModelMessage),
    ];

    LanguageModelV3GenerateResult? lastResponse;
    for (var step = 0; step < maxSteps; step++) {
      final response = await model.doGenerate(
        LanguageModelV3CallOptions(
          prompt: LanguageModelV3Prompt(
            system: instructions,
            messages: promptMessages,
          ),
          tools: tools.entries
              .map(
                (entry) => LanguageModelV3FunctionTool(
                  name: entry.key,
                  description: entry.value.description,
                  inputSchema: entry.value.inputSchema.jsonSchema,
                  strict: entry.value.strict,
                ),
              )
              .toList(),
        ),
      );

      lastResponse = response;
      promptMessages.add(
        LanguageModelV3Message(
          role: LanguageModelV3Role.assistant,
          content: response.content,
        ),
      );

      final toolCalls = response.content
          .whereType<LanguageModelV3ToolCallPart>();
      if (toolCalls.isEmpty) {
        return _toGenerateTextResult(response);
      }

      final snapshot = StepSnapshot(
        stepCount: step + 1,
        toolCallNames: toolCalls.map((call) => call.toolName).toList(),
      );
      if (stopConditions.any((condition) => condition(snapshot))) {
        return _toGenerateTextResult(response);
      }

      final toolResults = <LanguageModelV3ContentPart>[];
      for (final call in toolCalls) {
        toolResults.add(await _executeTool(call, promptMessages));
      }
      promptMessages.add(
        LanguageModelV3Message(
          role: LanguageModelV3Role.tool,
          content: toolResults,
        ),
      );
    }

    if (lastResponse != null) {
      return _toGenerateTextResult(lastResponse);
    }

    return generateText(
      model: model,
      system: instructions,
      prompt: prompt,
      messages: messages,
    );
  }

  Future<StreamTextResult> stream({
    String? prompt,
    List<ModelMessage>? messages,
  }) {
    return streamText(
      model: model,
      system: instructions,
      prompt: prompt,
      messages: messages,
      tools: tools,
      maxSteps: maxSteps,
      stopConditions: stopConditions,
    );
  }

  Future<LanguageModelV3ContentPart> _executeTool(
    LanguageModelV3ToolCallPart call,
    List<LanguageModelV3Message> messages,
  ) async {
    final tool = tools[call.toolName];
    if (tool == null) {
      return LanguageModelV3ToolResultPart(
        toolCallId: call.toolCallId,
        toolName: call.toolName,
        isError: true,
        output: const ToolResultOutputText('Tool not found.'),
      );
    }

    final rawInput = call.input;
    if (rawInput is! Map) {
      return LanguageModelV3ToolResultPart(
        toolCallId: call.toolCallId,
        toolName: call.toolName,
        isError: true,
        output: const ToolResultOutputText('Tool input is not a JSON object.'),
      );
    }

    try {
      final parsedInput = tool.inputSchema.fromJson(
        rawInput.cast<String, dynamic>(),
      );
      final executor = tool.executeDynamic;
      if (executor == null) {
        return LanguageModelV3ToolResultPart(
          toolCallId: call.toolCallId,
          toolName: call.toolName,
          isError: true,
          output: const ToolResultOutputText('Tool has no executor.'),
        );
      }

      final output = await executor(
        parsedInput,
        ToolExecutionOptions(toolCallId: call.toolCallId, messages: messages),
      );
      return LanguageModelV3ToolResultPart(
        toolCallId: call.toolCallId,
        toolName: call.toolName,
        output: ToolResultOutputText(_stringifyToolOutput(output)),
      );
    } catch (error) {
      return LanguageModelV3ToolResultPart(
        toolCallId: call.toolCallId,
        toolName: call.toolName,
        isError: true,
        output: ToolResultOutputText(error.toString()),
      );
    }
  }
}

GenerateTextResult _toGenerateTextResult(
  LanguageModelV3GenerateResult response,
) {
  final text = response.content
      .whereType<LanguageModelV3TextPart>()
      .map((part) => part.text)
      .join();
  return GenerateTextResult(
    text: text,
    output: text,
    content: response.content,
    toolCalls: response.content
        .whereType<LanguageModelV3ToolCallPart>()
        .toList(),
    toolResults: response.content
        .whereType<LanguageModelV3ToolResultPart>()
        .toList(),
    toolApprovalRequests: response.content
        .whereType<LanguageModelV3ToolApprovalRequestPart>()
        .toList(),
    steps: const [],
    sources: response.content.whereType<LanguageModelV3SourcePart>().toList(),
    files: response.content.whereType<LanguageModelV3FilePart>().toList(),
    reasoning: response.content
        .whereType<LanguageModelV3ReasoningPart>()
        .toList(),
    reasoningText: response.content
        .whereType<LanguageModelV3ReasoningPart>()
        .map((part) => part.text)
        .join(),
    requestMessages: const [],
    responseMessages: const [],
    request: const GenerateTextRequest(system: null, messages: [], body: null),
    responseInfo: const GenerateTextResponse(
      messages: [],
      body: null,
      metadata: null,
    ),
    response: response,
    usage: response.usage,
    totalUsage: response.usage,
    finishReason: response.finishReason,
    rawFinishReason: response.rawFinishReason,
    warnings: response.warnings,
    providerMetadata: response.providerMetadata,
  );
}

LanguageModelV3Message _toLanguageModelMessage(ModelMessage message) {
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

String _stringifyToolOutput(Object? output) {
  if (output == null) return 'null';
  if (output is String) return output;
  if (output is num || output is bool) return output.toString();
  try {
    return jsonEncode(output);
  } catch (_) {
    return output.toString();
  }
}
