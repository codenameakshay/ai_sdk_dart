import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_mcp/ai_sdk_mcp.dart';
import 'package:test/test.dart';

void main() {
  test(
    'HTTP disconnect after tool execution does not replay the request',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var sideEffects = 0;
      server.listen((request) async {
        if (request.method != 'POST') {
          request.response.statusCode = HttpStatus.methodNotAllowed;
          await request.response.close();
          return;
        }
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        if (body['method'] == 'tools/call') {
          sideEffects++;
          final socket = await request.response.detachSocket(
            writeHeaders: false,
          );
          socket.destroy();
          return;
        }
        if (body['method'] == 'initialize') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': body['id'],
              'result': {'protocolVersion': '2025-06-18', 'capabilities': {}},
            }),
          );
        } else {
          request.response.statusCode = HttpStatus.accepted;
        }
        await request.response.close();
      });
      final client = MCPClient(
        transport: StreamableHttpClientTransport(
          url: Uri.parse('http://127.0.0.1:${server.port}/mcp'),
        ),
        reconnectPolicy: const MCPReconnectPolicy(
          maxAttempts: 2,
          initialDelayMs: 0,
        ),
      );
      addTearDown(client.close);
      await expectLater(
        client.callTool('charge', {'amount': 1}),
        throwsA(isA<MCPAmbiguousToolCompletionException>()),
      );
      expect(sideEffects, 1);
    },
  );
}
