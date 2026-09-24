import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';
import 'package:ai_sdk_remote/ai_sdk_remote.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test('binary conversation file becomes a lossless UI data URL', () async {
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
    await transport
        .send(
          _conversation(
            ConversationFileBytes(Uint8List.fromList([0, 255, 128])),
          ),
        )
        .toList();
    final message = (body!['messages'] as List).single as Map;
    final part = (message['parts'] as List).single as Map;
    expect(part['url'], 'data:application/octet-stream;base64,AP+A');
    expect(part['mediaType'], 'application/octet-stream');
    expect(part['filename'], 'fixture.bin');
  });

  test('opaque provider file cannot silently become a null UI URL', () async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
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
    await expectLater(
      transport
          .send(
            _conversation(
              ConversationFileProviderReference(
                namespace: 'openai',
                id: 'file-1',
              ),
            ),
          )
          .toList(),
      throwsA(isA<UnsupportedError>()),
    );
    expect(requests, 0);
  });
}

Conversation _conversation(ConversationFileData data) => Conversation(
  id: 'conversation',
  messages: [
    ConversationMessage(
      id: 'message',
      role: ConversationRole.user,
      parts: [
        FilePart(
          id: 'file',
          data: data,
          mimeType: 'application/octet-stream',
          name: 'fixture.bin',
        ),
      ],
    ),
  ],
);
