import 'dart:async';

import 'package:ai_sdk_mcp/ai_sdk_mcp.dart';
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
