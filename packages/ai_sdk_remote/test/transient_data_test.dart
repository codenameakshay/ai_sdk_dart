import 'dart:convert';

import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';
import 'package:ai_sdk_remote/ai_sdk_remote.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test(
    'transient data is excluded from persisted conversation history',
    () async {
      final events = [
        {'type': 'start', 'messageId': 'assistant-1'},
        {
          'type': 'data-status',
          'id': 'temporary-status',
          'data': {'message': 'Searching'},
          'transient': true,
        },
        {
          'type': 'data-status',
          'id': 'retained-status',
          'data': {'message': 'Found'},
        },
        {'type': 'finish'},
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
      final restored = ConversationCodec.decode(
        ConversationCodec.encode(snapshots.last),
      );
      expect(restored.messages.single.parts.map((part) => part.id), [
        'retained-status',
      ]);
      expect(
        (restored.messages.single.parts.single as UnknownPart).raw['data'],
        {'message': 'Found'},
      );
      expect(snapshots[1].messages.single.parts, isEmpty);
    },
  );
}
