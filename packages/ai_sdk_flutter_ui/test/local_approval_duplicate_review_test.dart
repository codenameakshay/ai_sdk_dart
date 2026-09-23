import 'dart:async';

import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_dart/test.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  test('duplicate approval while executing runs the tool once', () async {
    var executions = 0;
    final entered = Completer<void>();
    final release = Completer<String>();
    final backend = LocalConversationBackend(
      initial: Conversation(id: 'chat', messages: const []),
      agent: ToolLoopAgent(
        model: QueuedStreamModel([
          [
            mockToolCall(
              toolName: 'write',
              toolCallId: 'call-1',
              input: const {},
            ),
          ],
          [mockText('finished')],
        ]),
        tools: {
          'write': Tool<Map<String, dynamic>, String>(
            inputSchema: Schema<Map<String, dynamic>>(
              jsonSchema: const {'type': 'object'},
              fromJson: (json) => json,
            ),
            approvalPolicy: ToolApprovalPolicy.always,
            executeDynamic: (_, _) async {
              executions++;
              if (!entered.isCompleted) entered.complete();
              return release.future;
            },
          ),
        },
      ),
    );
    addTearDown(() async {
      if (!release.isCompleted) release.complete('written');
      await backend.dispose();
    });
    await backend.send('write once');
    final approval = backend.conversation.messages
        .expand((message) => message.parts)
        .whereType<ApprovalPart>()
        .single;
    await backend.respondToApproval(
      approvalId: approval.approvalId!,
      approved: true,
    );
    await entered.future;
    await backend.respondToApproval(
      approvalId: approval.approvalId!,
      approved: true,
    );
    await Future<void>.delayed(Duration.zero);
    expect(executions, 1);
    release.complete('written');
    await pumpUntil(
      () =>
          backend.conversation.messages.last.status ==
          ConversationMessageStatus.complete,
    );
    expect(executions, 1);
  });
}
