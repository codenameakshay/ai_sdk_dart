import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';
import 'package:ai_sdk_remote/ai_sdk_remote.dart';
import 'package:test/test.dart';

import '../bin/server.dart' as fixture;

void main() {
  late HttpServer server;

  setUp(() async {
    server = await fixture.startRemoteBackendServer(port: 0);
  });

  tearDown(() => server.close(force: true));

  test(
    'serves a validated SSE response through RemoteConversationTransport',
    () async {
      final transport = RemoteConversationTransport(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/chat'),
      );
      addTearDown(transport.dispose);
      final snapshots = await transport
          .send(
            Conversation(
              id: 'example-chat',
              messages: [
                ConversationMessage(
                  id: 'user-1',
                  role: ConversationRole.user,
                  parts: [TextPart(id: 'user-part', text: 'Say hello.')],
                ),
              ],
            ),
          )
          .toList();
      expect(
        snapshots.last.messages.last.status,
        ConversationMessageStatus.complete,
      );
      expect(
        snapshots.last.messages.last.parts.whereType<TextPart>().single.text,
        'Hello from the trusted backend.',
      );
    },
  );

  test('rejects malformed bodies with an explicit JSON error', () async {
    final client = HttpClient();
    addTearDown(client.close);
    final request = await client.postUrl(
      Uri.parse('http://127.0.0.1:${server.port}/chat'),
    );
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode({
        'messages': [
          {'role': 'user'},
        ],
      }),
    );
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();

    expect(response.statusCode, HttpStatus.badRequest);
    expect(jsonDecode(body), {
      'error': 'messages[0] must contain string role and array parts.',
    });
  });

  test('answers CORS preflight requests for browser development', () async {
    final client = HttpClient();
    addTearDown(client.close);
    final request = await client.openUrl(
      'OPTIONS',
      Uri.parse('http://127.0.0.1:${server.port}/chat'),
    );
    final response = await request.close();

    expect(response.statusCode, HttpStatus.noContent);
    expect(response.headers.value('access-control-allow-origin'), '*');
    expect(
      response.headers.value('access-control-allow-methods'),
      contains('POST'),
    );
    expect(
      response.headers.value('access-control-expose-headers'),
      'x-vercel-ai-ui-message-stream',
    );
  });

  test('survives invalid UTF-8 and serves the next valid request', () async {
    final client = HttpClient();
    addTearDown(client.close);
    final invalid = await client.postUrl(
      Uri.parse('http://127.0.0.1:${server.port}/chat'),
    );
    invalid.headers.contentType = ContentType.json;
    invalid.add([0xc3, 0x28]);
    final invalidResponse = await invalid.close();
    expect(invalidResponse.statusCode, HttpStatus.badRequest);
    await invalidResponse.drain<void>();

    final transport = RemoteConversationTransport(
      endpoint: Uri.parse('http://127.0.0.1:${server.port}/chat'),
    );
    addTearDown(transport.dispose);
    final snapshots = await transport
        .send(
          Conversation(
            id: 'after-invalid',
            messages: [
              ConversationMessage(
                id: 'user-1',
                role: ConversationRole.user,
                parts: [TextPart(id: 'user-part', text: 'hello')],
              ),
            ],
          ),
        )
        .toList();
    expect(
      snapshots.last.messages.last.status,
      ConversationMessageStatus.complete,
    );
  });
}
