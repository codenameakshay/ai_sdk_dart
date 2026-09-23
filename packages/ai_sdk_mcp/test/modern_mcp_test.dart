import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_mcp/ai_sdk_mcp.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// Deterministic local modern-era server fixture. It records complete JSON-RPC
/// requests and returns protocol-shaped responses without network dependencies.
class _ModernServerTransport implements MCPTransport {
  _ModernServerTransport({
    this.supportedVersions = const ['2026-07-28'],
    this.failFirstToolsList = false,
  });

  final List<String> supportedVersions;
  bool failFirstToolsList;
  final requests = <JsonRpcRequest>[];
  bool closed = false;
  final events = StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> get notifications => events.stream;

  @override
  Future<JsonRpcResponse> send(JsonRpcRequest request) async {
    requests.add(request);
    if (request.method == 'server/discover') {
      return JsonRpcResponse(
        result: {
          'supportedVersions': supportedVersions,
          'capabilities': {'tools': {}},
          'serverInfo': {'name': 'modern-local', 'version': '1.0.0'},
        },
      );
    }
    if (request.method == 'tools/list') {
      if (failFirstToolsList) {
        failFirstToolsList = false;
        throw MCPTransportException(
          method: 'POST',
          uri: Uri.parse('http://modern-local/mcp'),
        );
      }
      return const JsonRpcResponse(
        result: {
          'resultType': 'complete',
          'tools': [
            {
              'name': 'echo',
              'inputSchema': {'type': 'object'},
            },
          ],
        },
      );
    }
    if (request.method == 'tools/call') {
      final token = (request.params?['_meta'] as Map?)?['progressToken'];
      if (token != null) {
        events.add({
          'jsonrpc': '2.0',
          'method': 'notifications/progress',
          'params': {'progressToken': token, 'progress': 1, 'total': 2},
        });
        events.add({
          'jsonrpc': '2.0',
          'method': 'notifications/progress',
          'params': {'progressToken': token, 'progress': 2, 'total': 2},
        });
        events.add({
          'jsonrpc': '2.0',
          'method': 'notifications/progress',
          'params': {'progressToken': token, 'progress': -1},
        });
      }
      return const JsonRpcResponse(
        result: {
          'resultType': 'input_required',
          'inputRequests': {
            'confirm': {
              'method': 'elicitation/create',
              'params': {'message': 'Confirm this action'},
            },
          },
          'requestState': 'state-1',
        },
      );
    }
    return const JsonRpcResponse(result: {'resultType': 'complete'});
  }

  @override
  Future<void> sendNotification(JsonRpcNotification notification) async {}

  @override
  Future<void> close() async {
    closed = true;
    await events.close();
  }
}

class _ModernResultTransport implements MCPTransport {
  _ModernResultTransport(this.result);

  final Object? result;
  final requests = <JsonRpcRequest>[];

  @override
  Stream<Map<String, dynamic>> get notifications => const Stream.empty();

  @override
  Future<JsonRpcResponse> send(JsonRpcRequest request) async {
    requests.add(request);
    if (request.method == 'server/discover') {
      return const JsonRpcResponse(
        result: {
          'supportedVersions': ['2026-07-28'],
        },
      );
    }
    return JsonRpcResponse(result: result, id: request.id);
  }

  @override
  Future<void> sendNotification(JsonRpcNotification notification) async {}

  @override
  Future<void> close() async {}
}

void main() {
  test(
    'modern HTTP fixture uses stateless request headers and no session lifecycle',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <HttpRequest>[];
      final listener = server.listen((request) async {
        requests.add(request);
        await request.drain<void>();
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': 1,
              'result': {'resultType': 'complete'},
            }),
          );
        await request.response.close();
      });
      final transport = StreamableHttpClientTransport(
        url: Uri.parse('http://${server.address.address}:${server.port}/mcp'),
      )..setProtocolVersion('2026-07-28');
      await transport.send(
        JsonRpcRequest(
          method: 'tools/call',
          id: 1,
          params: {'name': 'echo', 'arguments': const {}},
        ),
      );
      await transport.close();
      await listener.cancel();
      await server.close(force: true);

      expect(requests, hasLength(1));
      expect(
        requests.single.headers.value('mcp-protocol-version'),
        '2026-07-28',
      );
      expect(requests.single.headers.value('mcp-method'), 'tools/call');
      expect(requests.single.headers.value('mcp-name'), 'echo');
    },
  );

  test('modern strategy discovers and sends per-request metadata', () async {
    final server = _ModernServerTransport();
    final client = MCPClient(
      transport: server,
      protocolMode: MCPProtocolMode.modern,
    );
    addTearDown(client.close);

    await client.tools();

    expect(server.requests.map((request) => request.method), [
      'server/discover',
      'tools/list',
    ]);
    final discover = server.requests.first;
    expect(discover.params?['_meta'], {
      'io.modelcontextprotocol/protocolVersion': '2026-07-28',
      'io.modelcontextprotocol/clientCapabilities': <String, dynamic>{},
      'io.modelcontextprotocol/clientInfo': {
        'name': 'ai_sdk_dart',
        'version': '2.0.0',
      },
    });
    expect(server.requests[1].params?['_meta'], isA<Map>());
  });

  test(
    'HTTP 401 invokes host refresh hook and retries with refreshed token',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final authorization = <String?>[];
      var requestCount = 0;
      final listener = server.listen((request) async {
        requestCount++;
        authorization.add(request.headers.value('authorization'));
        await request.drain<void>();
        if (requestCount == 1) {
          request.response.statusCode = 401;
          await request.response.close();
          return;
        }
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': {}}));
        await request.response.close();
      });
      var refreshed = 0;
      final transport = StreamableHttpClientTransport(
        url: Uri.parse('http://${server.address.address}:${server.port}/mcp'),
        auth: MCPAuthConfiguration(
          resource: Uri.parse('https://mcp.example.test/mcp'),
          accessToken: () async => 'expired',
          refreshAccessToken: () async {
            refreshed++;
            return 'fresh';
          },
          retryAfterUnauthorized: true,
        ),
      )..setProtocolVersion('2026-07-28');
      await transport.send(JsonRpcRequest(method: 'tools/list', id: 1));
      await transport.close();
      await listener.cancel();
      await server.close(force: true);

      expect(refreshed, 1);
      expect(requestCount, 2);
      expect(authorization, ['Bearer expired', 'Bearer fresh']);
    },
  );

  test(
    'modern discovery rejects a result without exact supportedVersions',
    () async {
      final server = _ModernServerTransport(
        supportedVersions: const ['2025-11-25'],
      );
      final client = MCPClient(
        transport: server,
        protocolMode: MCPProtocolMode.modern,
      );
      addTearDown(client.close);

      await expectLater(
        client.initialize(),
        throwsA(
          isA<MCPException>().having(
            (error) => error.message,
            'message',
            contains('does not support 2026-07-28'),
          ),
        ),
      );
    },
  );

  test('auth binding validates issuer and safe redirect boundaries', () {
    final auth = MCPAuthConfiguration(
      resource: Uri.parse('https://mcp.example.test/mcp'),
      issuer: Uri.parse('https://issuer.example.test'),
    );
    auth.validateAuthorizationIssuer(
      'https://issuer.example.test',
      issuerParameterSupported: true,
    );
    expect(
      () => auth.validateAuthorizationIssuer(
        'https://attacker.example.test',
        issuerParameterSupported: true,
      ),
      throwsA(isA<MCPException>()),
    );
    expect(
      MCPAuthConfiguration.validateRedirectUri(
        Uri.parse('http://127.0.0.1:3456/callback'),
      ).host,
      '127.0.0.1',
    );
    expect(
      () => MCPAuthConfiguration.validateRedirectUri(
        Uri.parse('https://user:password@example.test/callback#token'),
      ),
      throwsArgumentError,
    );
  });

  test('401 refresh does not replay by default', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var count = 0;
    final listener = server.listen((request) async {
      count++;
      request.response.statusCode = 401;
      await request.response.close();
    });
    final transport = StreamableHttpClientTransport(
      url: Uri.parse('http://${server.address.address}:${server.port}/mcp'),
      auth: MCPAuthConfiguration(
        resource: Uri.parse('https://mcp.example.test/mcp'),
        accessToken: () async => 'expired',
        refreshAccessToken: () async => 'fresh',
      ),
    )..setProtocolVersion('2026-07-28');
    await expectLater(
      transport.send(JsonRpcRequest(method: 'tools/call', id: 1)),
      throwsA(isA<MCPTransportException>()),
    );
    await transport.close();
    await listener.cancel();
    await server.close(force: true);
    expect(count, 1);
  });

  test('auth discovery fetches protected-resource and AS metadata', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final issuer = Uri.parse('http://${server.address.address}:${server.port}');
    final listener = server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/resource') {
        request.response.write(
          jsonEncode({
            'resource': 'https://mcp.example.test/mcp',
            'authorization_servers': [issuer.toString()],
            'scopes_supported': ['files:read'],
          }),
        );
      } else {
        request.response.write(
          jsonEncode({
            'issuer': issuer.toString(),
            'authorization_endpoint': '$issuer/authorize',
            'token_endpoint': '$issuer/token',
            'authorization_response_iss_parameter_supported': true,
          }),
        );
      }
      await request.response.close();
    });
    final resource = await MCPAuthDiscovery.protectedResource(
      issuer.replace(path: '/resource'),
    );
    final metadata = await MCPAuthDiscovery.authorizationServer(issuer);
    await listener.cancel();
    await server.close(force: true);
    expect(resource.scopesSupported, ['files:read']);
    expect(metadata.issuer, issuer);
    expect(metadata.authorizationResponseIssuerSupported, isTrue);
  });

  test(
    'modern tool calls expose input-required rounds as a typed result',
    () async {
      final server = _ModernServerTransport();
      final client = MCPClient(
        transport: server,
        protocolMode: MCPProtocolMode.modern,
      );
      addTearDown(client.close);

      final result = await client.callTool('echo', {'value': 'x'});
      expect(result, isA<MCPInputRequiredResult>());
      expect((result! as MCPInputRequiredResult).requestState, 'state-1');
      await client.callTool(
        'echo',
        {'value': 'x'},
        inputResponses: const {'confirm': true},
        requestState: 'state-1',
      );
      expect(server.requests.last.params?['inputResponses'], {'confirm': true});
      expect(server.requests.last.params?['requestState'], 'state-1');
    },
  );

  test('modern resource subscriptions use subscriptions/listen', () async {
    final server = _ModernServerTransport();
    final client = MCPClient(
      transport: server,
      protocolMode: MCPProtocolMode.modern,
    );
    addTearDown(client.close);

    final subscription = client.subscribeResource('file:///tmp/a');
    await Future<void>.delayed(const Duration(milliseconds: 1));
    await subscription.listen((_) {}).cancel();
    expect(
      server.requests.map((request) => request.method),
      contains('subscriptions/listen'),
    );
    expect(
      server.requests.map((request) => request.method),
      isNot(contains('resources/subscribe')),
    );
  });

  test(
    'modern subscriptions replay with subscriptions/listen after reconnect',
    () async {
      final server = _ModernServerTransport();
      final client = MCPClient(
        transport: server,
        protocolMode: MCPProtocolMode.modern,
        reconnectPolicy: const MCPReconnectPolicy(
          maxAttempts: 1,
          initialDelayMs: 0,
        ),
        transportFactory: () => server,
      );
      addTearDown(client.close);
      final subscription = client.subscribeResource('file:///tmp/reconnect');
      await Future<void>.delayed(const Duration(milliseconds: 1));
      server.failFirstToolsList = true;
      await client.tools();
      await subscription.listen((_) {}).cancel();
      final listens = server.requests
          .where((request) => request.method == 'subscriptions/listen')
          .length;
      expect(listens, greaterThanOrEqualTo(2));
    },
  );

  test('modern replay-safe retries use a fresh JSON-RPC request id', () async {
    final server = _ModernServerTransport(failFirstToolsList: true);
    final client = MCPClient(
      transport: server,
      protocolMode: MCPProtocolMode.modern,
      reconnectPolicy: const MCPReconnectPolicy(
        maxAttempts: 1,
        initialDelayMs: 0,
      ),
      transportFactory: () => server,
    );
    addTearDown(client.close);

    await client.tools();
    final calls = server.requests.where(
      (request) => request.method == 'tools/list',
    );
    expect(calls.map((request) => request.id).toSet(), hasLength(2));
  });

  test(
    'progress tokens produce typed monotonic updates only while active',
    () async {
      final server = _ModernServerTransport();
      final client = MCPClient(
        transport: server,
        protocolMode: MCPProtocolMode.modern,
      );
      addTearDown(client.close);
      final updates = <MCPProgressUpdate>[];
      final subscription = client.progress.listen(updates.add);
      await client.callTool('echo', {'value': 'x'}, progressToken: 'p-1');
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(updates.map((update) => update.progress), [1, 2]);
      expect(updates.every((update) => update.progressToken == 'p-1'), isTrue);
    },
  );

  test('modern results require a valid resultType envelope', () async {
    final server = _ModernResultTransport(const {'tools': []});
    final client = MCPClient(
      transport: server,
      protocolMode: MCPProtocolMode.modern,
    );
    addTearDown(client.close);

    await expectLater(
      client.tools(),
      throwsA(
        isA<MCPException>().having(
          (error) => error.message,
          'message',
          contains('resultType'),
        ),
      ),
    );
  });

  test(
    'modern input-required results reject non-string request state',
    () async {
      final server = _ModernResultTransport({
        'resultType': 'input_required',
        'requestState': 42,
      });
      final client = MCPClient(
        transport: server,
        protocolMode: MCPProtocolMode.modern,
      );
      addTearDown(client.close);

      await expectLater(
        client.callTool('echo', const {}),
        throwsA(
          isA<MCPException>().having(
            (error) => error.message,
            'message',
            contains('requestState'),
          ),
        ),
      );

      final invalidRequestServer = _ModernResultTransport({
        'resultType': 'input_required',
        'inputRequests': {
          'unsupported': {'method': 'custom/request'},
        },
      });
      final invalidRequestClient = MCPClient(
        transport: invalidRequestServer,
        protocolMode: MCPProtocolMode.modern,
      );
      addTearDown(invalidRequestClient.close);
      await expectLater(
        invalidRequestClient.callTool('echo', const {}),
        throwsA(isA<MCPException>()),
      );
    },
  );

  test('concurrent unauthorized requests share one host refresh', () async {
    var refreshes = 0;
    final refreshStarted = Completer<void>();
    final refreshGate = Completer<String?>();
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (requests <= 2) return http.Response('', 401);
      return http.Response(
        jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'result': {}}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    addTearDown(client.close);
    final transport = StreamableHttpClientTransport(
      url: Uri.parse('https://mcp.example.test/mcp'),
      client: client,
      auth: MCPAuthConfiguration(
        resource: Uri.parse('https://mcp.example.test/mcp'),
        accessToken: () async => 'expired',
        refreshAccessToken: () {
          refreshes++;
          if (!refreshStarted.isCompleted) refreshStarted.complete();
          return refreshGate.future;
        },
        retryAfterUnauthorized: true,
      ),
    )..setProtocolVersion('2026-07-28');
    addTearDown(transport.close);

    final first = transport.send(JsonRpcRequest(method: 'tools/list', id: 1));
    final second = transport.send(JsonRpcRequest(method: 'tools/list', id: 2));
    await refreshStarted.future;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(refreshes, 1);
    refreshGate.complete('fresh');
    await Future.wait([first, second]);
  });
}
