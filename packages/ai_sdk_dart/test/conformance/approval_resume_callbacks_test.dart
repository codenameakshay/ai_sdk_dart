import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

void main() {
  test(
    'approval replay reports the resumed tool execution lifecycle',
    () async {
      final tools = {
        'lookup': dynamicTool<String>(execute: (_, _) async => 'found'),
      };
      final paused = await generateText(
        model: FakeToolModel(toolName: 'lookup', toolInput: {}),
        tools: tools,
        approvalPolicy: ToolApprovalPolicy.always,
      );
      final request = paused.toolApprovalRequests.single;
      final starts = <GenerateTextExperimentalToolCallStartEvent>[];
      final ends = <GenerateTextExperimentalToolCallFinishEvent>[];
      final result =
          await ToolLoopAgent(
            model: FakeTextModel('answer'),
            tools: tools,
          ).resume(
            replay: ToolApprovalReplay(
              messages: [
                ModelMessage.parts(
                  role: ModelMessageRole.assistant,
                  parts: [request.toolCall],
                ),
              ],
              requests: [request],
            ),
            toolApprovalResponses: [
              LanguageModelV4ToolApprovalResponse(
                approvalId: request.approvalId,
                approved: true,
                toolCallId: request.toolCall.toolCallId,
                toolName: request.toolCall.toolName,
                argumentsFingerprint: request.argumentsFingerprint,
                policyRevision: request.policyRevision,
              ),
            ],
            onToolExecutionStart: starts.add,
            onToolExecutionEnd: ends.add,
          );
      expect(await result.text, 'answer');
      expect(starts.map((event) => event.toolCall.toolCallId), ['call-1']);
      expect(ends.map((event) => event.success), [true]);
      expect(ends.single.output, 'found');
    },
  );
}
