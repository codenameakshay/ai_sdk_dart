import 'dart:async';
import 'dart:convert';

import 'package:ai_sdk_mcp/ai_sdk_mcp.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  test(
    'cancelling before acknowledgement closes the late subscription',
    () async {
      final started = Completer<int>();
      final stream = StreamController<List<int>>();
      var cancelled = false;
      stream.onCancel = () => cancelled = true;
      final httpClient = _Client((request) async {
        final body =
            jsonDecode(await request.finalize().bytesToString()) as Map;
        if (body['method'] == 'server/discover') {
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(
                jsonEncode({
                  'jsonrpc': '2.0',
                  'id': body['id'],
                  'result': {
                    'supportedVersions': ['2026-07-28'],
                  },
                }),
              ),
            ),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (body['method'] == 'subscriptions/listen') {
          started.complete(body['id'] as int);
          return http.StreamedResponse(
            stream.stream,
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }
        return http.StreamedResponse(const Stream.empty(), 202);
      });
      final client = MCPClient(
        transport: StreamableHttpClientTransport(
          url: Uri.https('mcp.test', '/'),
          client: httpClient,
        ),
        protocolMode: MCPProtocolMode.modern,
      );
      addTearDown(client.close);
      final subscription = client
          .subscribeResource('file:///late')
          .listen((_) {});
      final requestId = await started.future;
      await subscription.cancel();
      stream.add(
        utf8.encode(
          'data: ${jsonEncode({
            'jsonrpc': '2.0',
            'method': 'notifications/subscriptions/acknowledged',
            'params': {'requestId': requestId},
          })}\n\n',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(cancelled, isTrue);
      await stream.close();
    },
  );
}

class _Client extends http.BaseClient {
  _Client(this.handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}
