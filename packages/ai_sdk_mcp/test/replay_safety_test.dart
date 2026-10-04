import 'dart:convert';
import 'dart:async';

import 'package:ai_sdk_mcp/ai_sdk_mcp.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

class LostResponseTransport extends MCPTransport {
  int sideEffects = 0;
  final attempted = Completer<void>();
  Map<String, dynamic>? advertisedCapabilities;

  @override
  Future<JsonRpcResponse> send(JsonRpcRequest request) async {
    if (request.method == 'initialize') {
      advertisedCapabilities =
          request.params!['capabilities'] as Map<String, dynamic>;
      return const JsonRpcResponse(
        result: {'protocolVersion': '2025-06-18', 'capabilities': {}},
      );
    }
    if (request.method == 'tools/call') {
      sideEffects++;
      if (!attempted.isCompleted) attempted.complete();
      throw MCPTransportException(
        method: request.method,
        uri: Uri.parse('https://fixture.invalid'),
        context: 'response lost',
      );
    }
    return const JsonRpcResponse(result: {});
  }

  @override
  Future<void> sendNotification(JsonRpcNotification notification) async {}
  @override
  Future<void> close() async {}
}

void main() {
  test(
    'closing interrupts reconnect backoff and prevents another tool call',
    () async {
      final transport = LostResponseTransport();
      final client = MCPClient(
        transport: transport,
        reconnectPolicy: const MCPReconnectPolicy(initialDelayMs: 30000),
      );
      final operation = expectLater(
        client.callTool('lookup', {}, retryOnTransportFailure: true),
        throwsA(isA<MCPException>()),
      );
      await transport.attempted.future;
      await client.close();
      await operation.timeout(const Duration(seconds: 1));
      expect(transport.sideEffects, 1);
    },
  );

  test('lost tool response never silently repeats the side effect', () async {
    final transport = LostResponseTransport();
    final client = MCPClient(
      transport: transport,
      reconnectPolicy: const MCPReconnectPolicy(
        maxAttempts: 2,
        initialDelayMs: 0,
      ),
    );
    addTearDown(client.close);
    await expectLater(
      client.callTool('charge', {'amount': 1}),
      throwsA(
        isA<MCPAmbiguousToolCompletionException>()
            .having((error) => error.toolName, 'toolName', 'charge')
            .having(
              (error) => error.cause,
              'cause',
              isA<MCPTransportException>(),
            ),
      ),
    );
    expect(transport.sideEffects, 1);
  });

  test('caller may authorize retry for an idempotent tool operation', () async {
    final transport = LostResponseTransport();
    final client = MCPClient(
      transport: transport,
      reconnectPolicy: const MCPReconnectPolicy(
        maxAttempts: 2,
        initialDelayMs: 0,
      ),
    );
    addTearDown(client.close);
    await expectLater(
      client.callTool('lookup', {}, retryOnTransportFailure: true),
      throwsA(isA<MCPException>()),
    );
    expect(transport.sideEffects, 3);
  });

  test(
    'definite HTTP rejection stays a transport error and is never retried',
    () async {
      var toolCalls = 0;
      final httpClient = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final id = body['id'] as int;
        if (body['method'] == 'server/discover') {
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': id,
              'result': {
                'supportedVersions': ['2026-07-28'],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (body['method'] == 'tools/call') toolCalls++;
        return http.Response('rejected before dispatch', 400);
      });
      final transport = StreamableHttpClientTransport(
        url: Uri.parse('https://mcp.test/'),
        client: httpClient,
      );
      final client = MCPClient(
        transport: transport,
        protocolMode: MCPProtocolMode.modern,
        reconnectPolicy: const MCPReconnectPolicy(
          maxAttempts: 2,
          initialDelayMs: 0,
        ),
      );
      addTearDown(client.close);
      addTearDown(httpClient.close);

      await expectLater(
        client.callTool('charge', {}, retryOnTransportFailure: true),
        throwsA(
          isA<MCPTransportException>().having(
            (error) => error.statusCode,
            'statusCode',
            400,
          ),
        ),
      );
      expect(toolCalls, 1);
    },
  );

  test('unrecognized HTTP client status remains ambiguous', () async {
    var toolCalls = 0;
    final httpClient = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final id = body['id'] as int;
      if (body['method'] == 'server/discover') {
        return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': id,
            'result': {
              'supportedVersions': ['2026-07-28'],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (body['method'] == 'tools/call') toolCalls++;
      return http.Response('request may have been dispatched', 499);
    });
    final transport = StreamableHttpClientTransport(
      url: Uri.parse('https://mcp.test/'),
      client: httpClient,
    );
    final client = MCPClient(
      transport: transport,
      protocolMode: MCPProtocolMode.modern,
      reconnectPolicy: const MCPReconnectPolicy(
        maxAttempts: 2,
        initialDelayMs: 0,
      ),
    );
    addTearDown(client.close);
    addTearDown(httpClient.close);

    await expectLater(
      client.callTool('charge', {}),
      throwsA(isA<MCPAmbiguousToolCompletionException>()),
    );
    expect(toolCalls, 1);
  });

  test('HTTP 408 remains ambiguous and does not replay tools/call', () async {
    var toolCalls = 0;
    final httpClient = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final id = body['id'] as int;
      if (body['method'] == 'server/discover') {
        return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': id,
            'result': {
              'supportedVersions': ['2026-07-28'],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (body['method'] == 'tools/call') toolCalls++;
      return http.Response('request timeout', 408);
    });
    final transport = StreamableHttpClientTransport(
      url: Uri.parse('https://mcp.test/'),
      client: httpClient,
    );
    final client = MCPClient(
      transport: transport,
      protocolMode: MCPProtocolMode.modern,
      reconnectPolicy: const MCPReconnectPolicy(
        maxAttempts: 2,
        initialDelayMs: 0,
      ),
    );
    addTearDown(client.close);
    addTearDown(httpClient.close);

    await expectLater(
      client.callTool('charge', {}, retryOnTransportFailure: true),
      throwsA(isA<MCPAmbiguousToolCompletionException>()),
    );
    expect(toolCalls, 1);
  });

  test(
    'tool completion ambiguity is typed even without a reconnect policy',
    () async {
      final transport = LostResponseTransport();
      final client = MCPClient(transport: transport);
      addTearDown(client.close);
      await expectLater(
        client.callTool('charge', {}),
        throwsA(isA<MCPAmbiguousToolCompletionException>()),
      );
      expect(transport.sideEffects, 1);
    },
  );

  test(
    'legacy initialize does not advertise server features as client capabilities',
    () async {
      final transport = LostResponseTransport();
      final client = MCPClient(transport: transport);
      addTearDown(client.close);
      await client.initialize();
      expect(transport.advertisedCapabilities, isEmpty);
    },
  );
}
