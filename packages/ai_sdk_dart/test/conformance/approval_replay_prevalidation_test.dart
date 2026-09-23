import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_dart/test.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

void main() {
  test('tampered second replay call prevents execution of the first', () async {
    var executions = 0;
    final model = MockLanguageModelV4(
      response: [mockText('unexpected dispatch')],
    );
    final agent = ToolLoopAgent(
      model: model,
      approvalPolicy: ToolApprovalPolicy.always,
      approvalPolicyRevision: 'v1',
      tools: {
        'write': tool<Map<String, dynamic>, String>(
          inputSchema: Schema<Map<String, dynamic>>(
            jsonSchema: const {'type': 'object'},
            fromJson: (json) => json,
          ),
          execute: (_, _) async {
            executions++;
            return 'written';
          },
        ),
      },
    );
    final requests = [
      for (var index = 0; index < 2; index++)
        LanguageModelV4ToolApprovalRequestPart(
          approvalId: 'approval-$index',
          policyRevision: 'v1',
          argumentsFingerprint: '{"value":1}',
          toolCall: LanguageModelV4ToolCallPart(
            toolCallId: 'call-$index',
            toolName: 'write',
            input: {'value': index == 0 ? 1 : 999},
          ),
        ),
    ];
    final responses = [
      for (final request in requests)
        LanguageModelV4ToolApprovalResponse(
          approvalId: request.approvalId,
          approved: true,
          toolCallId: request.toolCall.toolCallId,
          toolName: 'write',
          argumentsFingerprint: '{"value":1}',
          policyRevision: 'v1',
        ),
    ];
    await expectLater(
      agent.resume(
        replay: ToolApprovalReplay(messages: const [], requests: requests),
        toolApprovalResponses: responses,
      ),
      throwsA(anything),
    );
    expect(executions, 0);
    expect(model.streamCalls, isEmpty);
    expect(model.generateCalls, isEmpty);
  });
}
