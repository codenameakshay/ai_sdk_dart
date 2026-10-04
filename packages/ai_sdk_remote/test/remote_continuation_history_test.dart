import 'dart:convert';

import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';
import 'package:ai_sdk_remote/ai_sdk_remote.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test(
    'repeated output retains the existing result identity and metadata',
    () async {
      final client = MockClient((_) async {
        final frames = [
          {'type': 'start', 'messageId': 'assistant-result'},
          {
            'type': 'tool-output-available',
            'toolCallId': 'call-result',
            'output': {'ok': true},
            'providerMetadata': {
              'fixture': {'second': true},
            },
          },
          {
            'type': 'tool-output-available',
            'toolCallId': 'call-result',
            'output': {'ok': true},
            'providerMetadata': {
              'fixture': {'third': true},
            },
          },
          {'type': 'finish'},
          '[DONE]',
        ];
        return http.Response(
          frames
              .map(
                (frame) =>
                    'data: ${frame == '[DONE]' ? frame : jsonEncode(frame)}\n\n',
              )
              .join(),
          200,
          headers: {
            'content-type': 'text/event-stream',
            'x-vercel-ai-ui-message-stream': 'v1',
          },
        );
      });
      final transport = RemoteConversationTransport(
        endpoint: Uri.parse('https://backend.test/chat'),
        client: client,
      );
      addTearDown(transport.dispose);
      addTearDown(client.close);

      final history = Conversation(
        id: 'conversation-result',
        messages: [
          ConversationMessage(
            id: 'assistant-result',
            role: ConversationRole.assistant,
            extra: {'message-extra': true},
            parts: [
              ToolCallPart(
                id: 'call-result-part',
                callId: 'call-result',
                name: 'lookup',
                arguments: const {'key': 'value'},
              ),
              ToolResultPart(
                id: 'stable-result-part',
                callId: 'call-result',
                toolName: 'lookup',
                output: {'ok': false},
                outputKind: 'json',
                providerOptions: const {
                  'fixture': {'first': true},
                },
                extra: const {'result-extra': true},
              ),
            ],
          ),
        ],
      );

      final snapshots = await transport.send(history).toList();
      final message = snapshots.last.messages.single;
      expect(message.extra, {'message-extra': true});
      final result = message.parts.whereType<ToolResultPart>().single;
      expect(result.id, 'stable-result-part');
      expect(result.toolName, 'lookup');
      expect(result.output, {'ok': true});
      expect(result.extra, {'result-extra': true});
      expect(result.providerOptions, {
        'fixture': {'first': true, 'second': true, 'third': true},
      });
    },
  );

  test(
    'same-ID continuation retains prior assistant parts and accepts tool output',
    () async {
      final client = MockClient((_) async {
        final frames = [
          {
            'type': 'start',
            'messageId': 'assistant-history',
            'messageMetadata': {'continued': true},
          },
          {'type': 'reset-step'},
          {
            'type': 'tool-input-available',
            'toolCallId': 'call-1',
            'toolName': 'lookup',
            'input': {'key': 'value'},
          },
          {
            'type': 'tool-approval-request',
            'approvalId': 'approval-1',
            'toolCallId': 'call-1',
          },
          {
            'type': 'tool-approval-request',
            'approvalId': 'approval-1',
            'toolCallId': 'call-1',
          },
          {
            'type': 'tool-approval-response',
            'approvalId': 'approval-1',
            'approved': true,
          },
          {
            'type': 'tool-approval-response',
            'approvalId': 'approval-1',
            'approved': true,
          },
          {
            'type': 'tool-output-available',
            'toolCallId': 'call-1',
            'toolName': 'lookup',
            'output': 'done',
            'providerMetadata': {
              'fixture': {'version': 1},
            },
          },
          {
            'type': 'tool-output-available',
            'toolCallId': 'call-1',
            'toolName': 'lookup',
            'output': 'done',
            'providerMetadata': {
              'fixture': {'replayed': true},
            },
          },
          {'type': 'text-start', 'id': 'before-approval'},
          {'type': 'text-delta', 'id': 'before-approval', 'delta': 'continued'},
          {'type': 'text-end', 'id': 'before-approval'},
          {'type': 'finish'},
          '[DONE]',
        ];
        final body = frames
            .map(
              (frame) =>
                  'data: ${frame == '[DONE]' ? frame : jsonEncode(frame)}\n\n',
            )
            .join();
        return http.Response(
          body,
          200,
          headers: {
            'content-type': 'text/event-stream',
            'x-vercel-ai-ui-message-stream': 'v1',
          },
        );
      });
      final transport = RemoteConversationTransport(
        endpoint: Uri.parse('https://backend.test/chat'),
        client: client,
      );
      addTearDown(transport.dispose);
      addTearDown(client.close);

      final history = Conversation(
        id: 'conversation-1',
        messages: [
          ConversationMessage(
            id: 'user-before',
            role: ConversationRole.user,
            parts: [TextPart(id: 'user-before-part', text: 'before')],
          ),
          ConversationMessage(
            id: 'assistant-history',
            role: ConversationRole.assistant,
            status: ConversationMessageStatus.complete,
            metadata: {'original': true, 'continued': false},
            extra: {'retained': true},
            parts: [
              TextPart(id: 'before-approval', text: 'before '),
              ToolCallPart(
                id: 'call-part',
                callId: 'call-1',
                name: 'lookup',
                arguments: {'key': 'value'},
              ),
              ApprovalPart(
                id: 'approval-part',
                callId: 'call-1',
                approvalId: 'approval-1',
                status: ApprovalStatus.approved,
              ),
            ],
          ),
          ConversationMessage(
            id: 'user-after',
            role: ConversationRole.user,
            parts: [TextPart(id: 'user-after-part', text: 'after')],
          ),
        ],
      );

      final snapshots = await transport.send(history).toList();
      final message = snapshots.last.messages.singleWhere(
        (item) => item.id == 'assistant-history',
      );
      expect(message.id, 'assistant-history');
      expect(message.metadata, {'original': true, 'continued': true});
      expect(message.extra, {'retained': true});
      expect(snapshots.last.messages.map((item) => item.id), [
        'user-before',
        'assistant-history',
        'user-after',
      ]);
      expect(message.parts.whereType<TextPart>().map((part) => part.text), [
        'before ',
        'continued',
      ]);
      expect(message.parts.whereType<TextPart>().map((part) => part.id), [
        'before-approval',
        'before-approval#2',
      ]);
      final call = message.parts.whereType<ToolCallPart>().single;
      expect(call.callId, 'call-1');
      expect(call.id, 'call-part');
      final approval = message.parts.whereType<ApprovalPart>().single;
      expect(approval.id, 'approval-part');
      expect(approval.status, ApprovalStatus.approved);
      final results = message.parts.whereType<ToolResultPart>().toList();
      expect(results, hasLength(1));
      expect(results.single.id, 'result-call-1');
      expect(results.single.output, 'done');
      expect(results.single.providerOptions, {
        'fixture': {'version': 1, 'replayed': true},
      });
    },
  );
}
