import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_mcp/ai_sdk_mcp.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  test('acknowledged stdio resource subscriptions send cancellation', () async {
    final output = StreamController<List<int>>();
    final input = StreamController<List<int>>();
    final started = Completer<int>();
    final cancelled = Completer<Map>();
    input.stream.transform(utf8.decoder).transform(const LineSplitter()).listen(
      (line) {
        final request = jsonDecode(line) as Map;
        if (request['method'] == 'server/discover') {
          output.add(
            utf8.encode(
              '${jsonEncode({
                'jsonrpc': '2.0',
                'id': request['id'],
                'result': {
                  'supportedVersions': ['2026-07-28'],
                },
              })}\n',
            ),
          );
        } else if (request['method'] == 'subscriptions/listen') {
          output.add(utf8.encode('${jsonEncode(_ack(request['id']))}\n'));
          started.complete(request['id'] as int);
        } else if (request['method'] == 'notifications/cancelled') {
          cancelled.complete(request);
        }
      },
    );
    final client = MCPClient(
      transport: StdioMCPTransport(
        command: 'fixture',
        processStarter: (_, _) async =>
            _Process(IOSink(input.sink), output.stream),
      ),
      protocolMode: MCPProtocolMode.modern,
    );
    addTearDown(client.close);
    final subscription = client
        .subscribeResource('file:///resource')
        .listen((_) {});
    final requestId = await started.future;
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();
    final notification = await cancelled.future.timeout(
      const Duration(seconds: 1),
    );
    expect((notification['params'] as Map)['requestId'], requestId);
  });

  test('HTTP completion ends an acknowledged subscription stream', () async {
    final body = StreamController<List<int>>();
    var cancelled = false;
    body.onCancel = () => cancelled = true;
    body.add(utf8.encode('data: ${jsonEncode(_ack(9))}\n\n'));
    final transport = StreamableHttpClientTransport(
      url: Uri.https('mcp.test', '/'),
      client: _Client(body.stream),
    )..setProtocolVersion('2026-07-28');
    addTearDown(transport.close);
    await transport.send(JsonRpcRequest(method: 'subscriptions/listen', id: 9));
    expect(cancelled, isFalse);
    body.add(
      utf8.encode(
        'data: ${jsonEncode({
          'jsonrpc': '2.0',
          'id': 9,
          'result': {
            'resultType': 'complete',
            '_meta': {'io.modelcontextprotocol/subscriptionId': 9},
          },
        })}\n\n',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(cancelled, isTrue);
    await body.close();
  });

  test(
    'stdio ignores malformed acknowledgements before matching valid metadata',
    () async {
      final output = StreamController<List<int>>();
      final input = StreamController<List<int>>();
      final stdin = IOSink(input.sink);
      final sent = Completer<void>();
      input.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            final request = jsonDecode(line) as Map;
            output.add(
              utf8.encode(
                '${jsonEncode({..._ack(request['id']), 'jsonrpc': '1.0'})}\n',
              ),
            );
            sent.complete();
          });
      final transport = StdioMCPTransport(
        command: 'fixture',
        processStarter: (_, _) async => _Process(stdin, output.stream),
      );
      addTearDown(transport.close);
      var settled = false;
      final outcome = transport
          .send(JsonRpcRequest(method: 'subscriptions/listen', id: 9))
          .then<Object?>((value) {
            settled = true;
            return value;
          }, onError: (Object e) => e);
      await sent.future;
      await Future<void>.delayed(Duration.zero);
      expect(settled, isFalse);
      output.add(utf8.encode('${jsonEncode(_ack(9))}\n'));
      expect(
        await outcome.timeout(
          const Duration(seconds: 1),
          onTimeout: () => 'still pending',
        ),
        isA<JsonRpcResponse>(),
      );
    },
  );

  for (final subscriptionId in [null, 10, 9]) {
    test(
      'HTTP rejects ${subscriptionId == 9 ? 'an invalid JSON-RPC version' : 'acknowledgement metadata $subscriptionId'} for request 9',
      () async {
        final body = StreamController<List<int>>();
        var cancelled = false;
        body.onCancel = () => cancelled = true;
        body.add(
          utf8.encode(
            'data: ${jsonEncode({..._ack(subscriptionId), if (subscriptionId == 9) 'jsonrpc': '1.0'})}\n\n',
          ),
        );
        final transport = StreamableHttpClientTransport(
          url: Uri.https('mcp.test', '/'),
          client: _Client(body.stream),
        )..setProtocolVersion('2026-07-28');
        addTearDown(transport.close);
        await expectLater(
          transport.send(JsonRpcRequest(method: 'subscriptions/listen', id: 9)),
          throwsA(isA<MCPException>()),
        );
        expect(cancelled, isTrue);
        await body.close();
      },
    );
  }
}

Map<String, dynamic> _ack(Object? subscriptionId) => {
  'jsonrpc': '2.0',
  'method': 'notifications/subscriptions/acknowledged',
  'params': {
    '_meta': {'io.modelcontextprotocol/subscriptionId': subscriptionId},
    'notifications': <String, Object?>{},
  },
};

class _Client extends http.BaseClient {
  _Client(this.body);
  final Stream<List<int>> body;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        body,
        200,
        headers: {'content-type': 'text/event-stream'},
      );
}

class _Process implements Process {
  _Process(this.stdin, this.stdout);
  @override
  final IOSink stdin;
  @override
  final Stream<List<int>> stdout;
  @override
  Stream<List<int>> get stderr => const Stream.empty();
  @override
  Future<int> get exitCode => Completer<int>().future;
  @override
  int get pid => 1;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;
}
