import 'dart:convert';

import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';
import 'package:ai_sdk_remote/ai_sdk_remote.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test('merges message metadata from start, updates, and finish', () async {
    final events = [
      {
        'type': 'start',
        'messageId': 'assistant-1',
        'messageMetadata': {
          'createdAt': 123,
          'usage': {'inputTokens': 4},
        },
      },
      {
        'type': 'message-metadata',
        'messageMetadata': {
          'usage': {'outputTokens': 6},
        },
      },
      {
        'type': 'finish',
        'messageMetadata': {
          'model': 'fixture',
          'usage': {'totalTokens': 10},
        },
      },
    ];
    final client = MockClient(
      (_) async => http.Response(
        '${events.map((e) => 'data: ${jsonEncode(e)}\n\n').join()}'
        'data: [DONE]\n\n',
        200,
        headers: {
          'content-type': 'text/event-stream',
          'x-vercel-ai-ui-message-stream': 'v1',
        },
      ),
    );
    final transport = RemoteConversationTransport(
      endpoint: Uri.parse('https://backend.test/chat'),
      client: client,
    );
    addTearDown(transport.dispose);
    addTearDown(client.close);

    final snapshots = await transport
        .send(Conversation(id: 'conversation-1', messages: []))
        .toList();

    expect(snapshots[1].messages.single.metadata, {
      'createdAt': 123,
      'usage': {'inputTokens': 4, 'outputTokens': 6},
    });
    expect(snapshots.last.messages.single.metadata, {
      'createdAt': 123,
      'model': 'fixture',
      'usage': {'inputTokens': 4, 'outputTokens': 6, 'totalTokens': 10},
    });
    expect(snapshots.first.messages.single.metadata, {
      'createdAt': 123,
      'usage': {'inputTokens': 4},
    });
    expect(
      ConversationCodec.decode(ConversationCodec.encode(snapshots.last)),
      snapshots.last,
    );
  });
}
