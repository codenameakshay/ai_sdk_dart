import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_mcp/ai_sdk_mcp.dart';
import 'package:test/test.dart';

void main() {
  test(
    'modern SSE validates response IDs and forwards notifications',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        request.response.write(
          'data: ${jsonEncode({
            'jsonrpc': '2.0',
            'method': 'notifications/progress',
            'params': {'progressToken': 'p', 'progress': 1},
          })}\r\n\r\n'
          'data: ${jsonEncode({
            'jsonrpc': '2.0',
            'id': body['id'],
            'result': {'resultType': 'complete', 'tools': []},
          })}\r\n\r\n',
        );
        await request.response.close();
      });
      final transport = _transport(server);
      addTearDown(transport.close);
      final notifications = <Map<String, dynamic>>[];
      final subscription = transport.notifications.listen(notifications.add);
      addTearDown(subscription.cancel);
      final result = await transport.send(
        JsonRpcRequest(method: 'tools/list', id: 7),
      );
      expect(result.result, {'resultType': 'complete', 'tools': []});
      expect(notifications.single['method'], 'notifications/progress');
      expect((notifications.single['params'] as Map)['progressToken'], 'p');
    },
  );

  for (final invalidContentType in [false, true]) {
    test(
      'modern response rejects ${invalidContentType ? 'wrong media type' : 'mismatched ID'}',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        server.listen((request) async {
          await request.drain<void>();
          request.response.headers.contentType = invalidContentType
              ? ContentType.text
              : ContentType('text', 'event-stream');
          request.response.write(
            'data: {"jsonrpc":"2.0","id":999,"result":{}}\n\n',
          );
          await request.response.close();
        });
        final transport = _transport(server);
        addTearDown(transport.close);
        await expectLater(
          transport.send(JsonRpcRequest(method: 'tools/list', id: 7)),
          throwsA(isA<MCPException>()),
        );
      },
    );
  }

  for (final status in [202, 403]) {
    test(
      'modern notification handles HTTP $status without a session',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final requests = <Map<String, dynamic>>[];
        final methods = <String?>[];
        final sessions = <String?>[];
        server.listen((request) async {
          methods.add(request.headers.value('mcp-method'));
          sessions.add(request.headers.value('mcp-session-id'));
          requests.add(
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>,
          );
          request.response.statusCode = status;
          await request.response.close();
        });
        final transport = _transport(server);
        addTearDown(transport.close);
        final sending = transport.sendNotification(
          JsonRpcNotification(
            method: 'notifications/cancelled',
            params: {'requestId': 7},
          ),
        );
        if (status == 202) {
          await sending;
        } else {
          await expectLater(sending, throwsA(isA<MCPTransportException>()));
        }
        await transport.close();
        expect(requests, hasLength(1));
        expect(requests.single.containsKey('id'), isFalse);
        expect(methods, ['notifications/cancelled']);
        expect(sessions, [null]);
      },
    );
  }
}

StreamableHttpClientTransport _transport(HttpServer server) =>
    StreamableHttpClientTransport(
      url: Uri.parse('http://127.0.0.1:${server.port}/mcp'),
    )..setProtocolVersion('2026-07-28');
