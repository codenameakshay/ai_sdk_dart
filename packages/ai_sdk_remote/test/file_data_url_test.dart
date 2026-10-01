import 'dart:convert';

import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';
import 'package:ai_sdk_remote/ai_sdk_remote.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test('decodes percent-encoded data URLs without corrupting bytes', () async {
    Map<String, dynamic>? replay;
    var requests = 0;
    final client = MockClient((request) async {
      if (++requests == 2) {
        replay = jsonDecode(request.body) as Map<String, dynamic>;
      }
      final events = [
        {'type': 'start', 'messageId': 'assistant-$requests'},
        if (requests == 1)
          {
            'type': 'file',
            'mediaType': 'application/octet-stream',
            'url': 'data:application/octet-stream,%00%FF%80%20%25',
          },
        {'type': 'finish'},
      ];
      return http.Response(
        '${events.map((e) => 'data: ${jsonEncode(e)}\n\n').join()}'
        'data: [DONE]\n\n',
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

    final snapshots = await transport
        .send(Conversation(id: 'conversation-1', messages: []))
        .toList();
    final restored = ConversationCodec.decode(
      ConversationCodec.encode(snapshots.last),
    );
    final file = restored.messages.single.parts.whereType<FilePart>().single;
    expect((file.data as ConversationFileBytes).bytes, [0, 255, 128, 32, 37]);

    await transport.send(restored).drain<void>();
    final message = (replay!['messages'] as List).single as Map;
    expect(
      (message['parts'] as List).single['url'],
      'data:application/octet-stream;base64,AP+AICU=',
    );
  });
}
