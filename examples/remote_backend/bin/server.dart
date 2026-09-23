import 'dart:convert';
import 'dart:io';

// Minimal loopback backend fixture. Replace the static events with a trusted
// server using the pinned Vercel AI SDK's toUIMessageStream helpers. Provider
// credentials and tool execution belong here, never in Flutter.
void main() {
  HttpServer.bind(InternetAddress.loopbackIPv4, 8080).then((server) {
    print('Listening on http://${server.address.host}:${server.port}/chat');
    server.listen((request) async {
      if (request.method != 'POST' || request.uri.path != '/chat') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      request.response
        ..headers.contentType = ContentType('text', 'event-stream')
        ..headers.set('x-vercel-ai-ui-message-stream', 'v1');
      for (final event in [
        {'type': 'start', 'messageId': 'example-assistant'},
        {'type': 'text-start', 'id': 'example-text'},
        {
          'type': 'text-delta',
          'id': 'example-text',
          'delta': 'Hello from the trusted backend.',
        },
        {'type': 'text-end', 'id': 'example-text'},
        {'type': 'finish'},
      ]) {
        request.response.write('data: ${jsonEncode(event)}\n\n');
      }
      request.response.write('data: [DONE]\n\n');
      await request.response.close();
    });
  });
}
