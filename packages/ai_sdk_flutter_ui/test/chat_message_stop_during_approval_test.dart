import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  test(
    'stop during an approval response notification prevents resume',
    () async {
      final controller = ChatController();
      addTearDown(controller.dispose);
      final agent = approvalAgent(
        finalText: 'should not resume',
        repeatCallAfterApproval: false,
      );

      await controller.sendMessage(agent: agent, text: 'question');
      await pumpUntil(() => controller.status == ChatStatus.awaitingApproval);
      expect(controller.pendingApprovalRequests, hasLength(1));
      final approvalId = controller.pendingApprovalRequests.single.approvalId;
      Future<void>? stopping;
      controller.statusListenable.addListener(() {
        if (controller.status == ChatStatus.awaitingApproval &&
            controller.pendingApprovalRequests.isEmpty &&
            stopping == null) {
          stopping = controller.stop();
        }
      });

      controller.addToolApprovalResponse(
        approvalId: approvalId,
        approved: true,
      );
      await stopping;
      await pumpUntil(() => false, tries: 40);

      expect(stopping, isNotNull);
      expect(controller.status, ChatStatus.ready);
      expect(controller.messages, hasLength(1));
      expect(controller.messages.single.role, ModelMessageRole.user);
    },
  );
}
