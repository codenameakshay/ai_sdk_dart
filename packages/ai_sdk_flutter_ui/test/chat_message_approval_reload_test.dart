import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

String Function() _ids() {
  var next = 0;
  return () => 'id-${++next}';
}

void main() {
  group('ChatController approval reload regressions', () {
    test(
      'reload with an agent on a fresh controller resumes that agent',
      () async {
        final controller = ChatController(generateId: _ids());
        addTearDown(controller.dispose);
        final agent = approvalAgent(
          finalText: 'agent B answer',
          repeatCallAfterApproval: false,
        );

        await controller.reload(agent: agent);
        await pumpUntil(() => controller.status == ChatStatus.awaitingApproval);

        expect(controller.pendingApprovalRequests, hasLength(1));
        controller.addToolApprovalResponse(
          approvalId: controller.pendingApprovalRequests.single.approvalId,
          approved: true,
        );
        await pumpUntil(() => controller.status == ChatStatus.ready);

        final assistantMessages = controller.chatMessages
            .where((entry) => entry.message.role == ModelMessageRole.assistant)
            .toList();
        expect(assistantMessages, hasLength(1));
        expect(assistantMessages.single.id, 'id-1');
        expect(assistantMessages.single.message.content, 'agent B answer');
        expect(assistantMessages.single.provider, 'mock');
        expect(assistantMessages.single.modelId, 'queued');
      },
    );

    test('reload agent resumes approval through the reloaded agent', () async {
      final controller = ChatController(generateId: _ids());
      addTearDown(controller.dispose);
      final agentA = textAgent('agent A answer');
      final agentB = approvalAgent(
        finalText: 'agent B answer',
        repeatCallAfterApproval: false,
      );

      await controller.sendMessage(agent: agentA, text: 'question');
      await pumpUntil(() => controller.status == ChatStatus.ready);
      await controller.reload(agent: agentB);
      await pumpUntil(() => controller.status == ChatStatus.awaitingApproval);

      expect(controller.pendingApprovalRequests, hasLength(1));
      controller.addToolApprovalResponse(
        approvalId: controller.pendingApprovalRequests.single.approvalId,
        approved: true,
      );
      await pumpUntil(() => controller.status == ChatStatus.ready);

      final assistantMessages = controller.chatMessages
          .where((entry) => entry.message.role == ModelMessageRole.assistant)
          .toList();
      expect(assistantMessages, hasLength(1));
      expect(assistantMessages.single.id, 'id-3');
      expect(assistantMessages.single.message.content, 'agent B answer');
      expect(assistantMessages.single.provider, 'mock');
      expect(assistantMessages.single.modelId, 'queued');
    });
  });
}
