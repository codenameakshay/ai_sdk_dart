import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';
import 'package:ai_sdk_remote/ai_sdk_remote.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test('completed tool history retains the original input', () async {
    Map<String, dynamic>? body;
    final client = MockClient((request) async {
      body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        'data: {"type":"start","messageId":"reply"}\n\n'
        'data: {"type":"finish"}\n\n'
        'data: [DONE]\n\n',
        200,
        headers: {
          'x-vercel-ai-ui-message-stream': 'v1',
          'content-type': 'text/event-stream',
        },
      );
    });
    final transport = RemoteConversationTransport(
      endpoint: Uri.parse('https://backend.test/chat'),
      client: client,
    );
    addTearDown(transport.dispose);
    addTearDown(client.close);
    await transport.send(_history()).toList();
    final message = (body!['messages'] as List).single as Map;
    final part = (message['parts'] as List).single as Map;
    expect(part['state'], 'output-available');
    expect(part['input'], {'path': '/tmp/history'});
    expect(part['output'], {'ok': true});
  });

  test('pinned Vercel server accepts completed tool history', () async {
    final endpoint = Platform.environment['AI_SDK_REMOTE_REFERENCE_URL'];
    if (endpoint == null) {
      markTestSkipped('Set AI_SDK_REMOTE_REFERENCE_URL for the pinned server');
      return;
    }
    final transport = RemoteConversationTransport(
      endpoint: Uri.parse(endpoint),
    );
    addTearDown(transport.dispose);
    final snapshots = await transport.send(_history()).toList();
    expect(snapshots, isNotEmpty);
  });
}

Conversation _history() => Conversation(
  id: 'completed-tool-history',
  messages: [
    ConversationMessage(
      id: 'assistant-history',
      role: ConversationRole.assistant,
      parts: [
        ToolCallPart(
          id: 'call-part',
          callId: 'call-history',
          name: 'delete',
          arguments: {'path': '/tmp/history'},
        ),
        ToolResultPart(
          id: 'result-part',
          callId: 'call-history',
          output: {'ok': true},
        ),
      ],
    ),
  ],
);
