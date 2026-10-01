import 'dart:convert';

import 'package:ai_sdk_mcp/ai_sdk_mcp.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  for (final refreshedToken in [null, '']) {
    test(
      'an unavailable refreshed token preserves the HTTP unauthorized error ($refreshedToken)',
      () async {
        final client = _Client();
        final transport = StreamableHttpClientTransport(
          url: Uri.https('mcp.test', '/'),
          auth: MCPAuthConfiguration(
            resource: Uri.https('mcp.test', '/'),
            accessToken: () async => 'expired',
            refreshAccessToken: () async => refreshedToken,
            retryAfterUnauthorized: true,
          ),
          client: client,
        );
        addTearDown(transport.close);
        await expectLater(
          transport
              .send(JsonRpcRequest(method: 'tools/list', id: 1))
              .timeout(const Duration(seconds: 1)),
          throwsA(
            isA<MCPTransportException>()
                .having((error) => error.statusCode, 'statusCode', 401)
                .having(
                  (error) => error.message,
                  'message',
                  isNot(contains('private response')),
                ),
          ),
        );
        expect(client.sends, 1);
      },
    );
  }
}

class _Client extends http.BaseClient {
  var sends = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sends++;
    return http.StreamedResponse(
      Stream.value(utf8.encode('private response')),
      401,
      headers: {'content-type': 'text/plain'},
    );
  }
}
