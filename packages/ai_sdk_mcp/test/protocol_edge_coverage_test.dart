import 'dart:async';
import 'dart:convert';

import 'package:ai_sdk_mcp/ai_sdk_mcp.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

class _ScriptedTransport implements MCPTransport {
  _ScriptedTransport(this.handler);

  final FutureOr<JsonRpcResponse> Function(JsonRpcRequest) handler;
  final requests = <JsonRpcRequest>[];
  final sentNotifications = <JsonRpcNotification>[];
  final events = StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> get notifications => events.stream;

  @override
  Future<JsonRpcResponse> send(JsonRpcRequest request) async {
    requests.add(request);
    return handler(request);
  }

  @override
  Future<void> sendNotification(JsonRpcNotification notification) async {
    sentNotifications.add(notification);
  }

  @override
  Future<void> close() => events.close();
}

JsonRpcResponse _modernDiscovery(JsonRpcRequest request) =>
    const JsonRpcResponse(
      result: {
        'supportedVersions': ['2026-07-28'],
      },
    );

JsonRpcResponse _complete(JsonRpcRequest request) =>
    JsonRpcResponse(result: {'resultType': 'complete'}, id: request.id);

class _HandlerClient extends http.BaseClient {
  _HandlerClient(this.handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);

  @override
  void close() => closed = true;
}

http.StreamedResponse _response(
  int status, {
  String body = '',
  Map<String, String> headers = const {},
}) => http.StreamedResponse(
  Stream<List<int>>.value(utf8.encode(body)),
  status,
  headers: headers,
);

void main() {
  group('MCPClient protocol edges', () {
    test(
      'modern discovery errors are surfaced and success selects modern',
      () async {
        final failed = MCPClient(
          transport: _ScriptedTransport((request) {
            return const JsonRpcResponse(error: {'code': -1, 'message': 'no'});
          }),
          protocolMode: MCPProtocolMode.modern,
        );
        await expectLater(
          failed.tools(),
          throwsA(
            isA<MCPException>().having(
              (error) => error.message,
              'message',
              contains('Modern server discovery failed'),
            ),
          ),
        );
        await failed.close();

        final transport = _ScriptedTransport(
          (request) => switch (request.method) {
            'server/discover' => _modernDiscovery(request),
            _ => _complete(request),
          },
        );
        final client = MCPClient(
          transport: transport,
          protocolMode: MCPProtocolMode.modern,
        );
        addTearDown(client.close);
        await client.tools();
        expect(transport.requests.map((request) => request.method), [
          'server/discover',
          'tools/list',
        ]);
        expect(transport.requests.last.params?['_meta'], isA<Map>());
      },
    );

    test(
      'modern session recovery retries the request with fresh metadata',
      () async {
        var expired = false;
        final transport = _ScriptedTransport((request) {
          if (request.method == 'server/discover') {
            return _modernDiscovery(request);
          }
          if (request.method == 'tools/list' && !expired) {
            expired = true;
            throw MCPSessionExpiredException(
              method: 'POST',
              uri: Uri.https('mcp.test', '/'),
            );
          }
          return JsonRpcResponse(
            result: {'resultType': 'complete', 'tools': []},
            id: request.id,
          );
        });
        final client = MCPClient(
          transport: transport,
          protocolMode: MCPProtocolMode.modern,
        );
        addTearDown(client.close);

        expect(await client.tools(), isEmpty);
        final requests = transport.requests
            .where((request) => request.method == 'tools/list')
            .toList();
        expect(requests, hasLength(2));
        expect(requests.last.id, isNot(requests.first.id));
        expect(requests.last.params?['_meta'], isA<Map>());
      },
    );

    test('modern input_required is rejected for unsupported methods', () async {
      final transport = _ScriptedTransport((request) {
        if (request.method == 'server/discover') {
          return _modernDiscovery(request);
        }
        return JsonRpcResponse(
          result: {'resultType': 'input_required', 'requestState': 'state'},
          id: request.id,
        );
      });
      final client = MCPClient(
        transport: transport,
        protocolMode: MCPProtocolMode.modern,
      );
      addTearDown(client.close);
      await expectLater(
        client.tools(),
        throwsA(
          isA<MCPException>().having(
            (error) => error.message,
            'message',
            contains('cannot return input_required'),
          ),
        ),
      );
    });

    test(
      'callTool validates token and returns typed error and input metadata',
      () async {
        final transport = _ScriptedTransport((request) {
          if (request.method == 'initialize') {
            return const JsonRpcResponse(
              result: {
                'protocolVersion': '2025-06-18',
                'capabilities': {},
                'serverInfo': {'name': 'test', 'version': '1'},
              },
            );
          }
          if (request.method == 'tools/call') {
            return JsonRpcResponse(
              result: {
                'resultType': 'input_required',
                'inputRequests': {'confirm': true},
                'requestState': 'state',
                '_meta': {'trace': 'id'},
              },
              id: request.id,
            );
          }
          return _complete(request);
        });
        final client = MCPClient(transport: transport);
        addTearDown(client.close);
        await expectLater(
          client.callTool('echo', {}, progressToken: true),
          throwsA(
            isA<MCPException>().having(
              (error) => error.message,
              'message',
              contains('progressToken must be a string or integer'),
            ),
          ),
        );
        final result = await client.callTool('echo', {});
        expect(result, isA<MCPInputRequiredResult>());
        expect((result! as MCPInputRequiredResult).meta, {'trace': 'id'});
      },
    );

    test('callTool throws when content is marked as an error', () async {
      final transport = _ScriptedTransport((request) {
        if (request.method == 'initialize') {
          return const JsonRpcResponse(
            result: {
              'protocolVersion': '2025-06-18',
              'capabilities': {},
              'serverInfo': {'name': 'test', 'version': '1'},
            },
          );
        }
        if (request.method == 'tools/call') {
          return JsonRpcResponse(
            result: {
              'content': [
                {'type': 'text', 'text': 'denied'},
              ],
              'isError': true,
            },
            id: request.id,
          );
        }
        return _complete(request);
      });
      final client = MCPClient(transport: transport);
      addTearDown(client.close);
      await expectLater(
        client.callTool('echo', {}),
        throwsA(
          isA<MCPException>().having(
            (error) => error.message,
            'message',
            contains('Tool "echo" returned error'),
          ),
        ),
      );
    });

    test(
      'modern subscription errors do not fail the returned stream',
      () async {
        final transport = _ScriptedTransport((request) {
          if (request.method == 'server/discover') {
            return _modernDiscovery(request);
          }
          if (request.method == 'subscriptions/listen') {
            return const JsonRpcResponse(
              error: {'code': -1, 'message': 'unsupported'},
            );
          }
          return _complete(request);
        });
        final client = MCPClient(
          transport: transport,
          protocolMode: MCPProtocolMode.modern,
        );
        addTearDown(client.close);
        final updates = client
            .subscribeResource('file:///optional')
            .listen((_) {});
        addTearDown(updates.cancel);
        await client.initialize();
        await Future<void>.delayed(Duration.zero);
        expect(
          transport.requests.map((request) => request.method),
          contains('subscriptions/listen'),
        );
      },
    );

    test(
      'reinitialize reports a failed resource subscription replay',
      () async {
        var subscriptionFailed = false;
        var toolCall = false;
        final transport = _ScriptedTransport((request) {
          if (request.method == 'initialize') {
            return const JsonRpcResponse(
              result: {
                'protocolVersion': '2025-06-18',
                'capabilities': {},
                'serverInfo': {'name': 'test', 'version': '1'},
              },
            );
          }
          if (request.method == 'resources/subscribe') {
            if (subscriptionFailed) {
              return const JsonRpcResponse(
                error: {'code': -1, 'message': 'replay denied'},
              );
            }
            return _complete(request);
          }
          if (request.method == 'tools/list' && !toolCall) {
            toolCall = true;
            throw MCPSessionExpiredException(
              method: 'POST',
              uri: Uri.https('mcp.test', '/'),
            );
          }
          return _complete(request);
        });
        final client = MCPClient(transport: transport);
        final subscription = client
            .subscribeResource('file:///replay')
            .listen((_) {});
        addTearDown(subscription.cancel);
        await Future<void>.delayed(Duration.zero);
        subscriptionFailed = true;
        await expectLater(
          client.tools(),
          throwsA(
            isA<MCPException>().having(
              (error) => error.message,
              'message',
              contains('resources/subscribe "file:///replay" failed'),
            ),
          ),
        );
        await client.close();
      },
    );

    test('callTool throws when an error result has no content', () async {
      final transport = _ScriptedTransport((request) {
        if (request.method == 'initialize') {
          return const JsonRpcResponse(
            result: {
              'protocolVersion': '2025-06-18',
              'capabilities': {},
              'serverInfo': {'name': 'test', 'version': '1'},
            },
          );
        }
        if (request.method == 'tools/call') {
          return JsonRpcResponse(result: {'isError': true}, id: request.id);
        }
        return _complete(request);
      });
      final client = MCPClient(transport: transport);
      addTearDown(client.close);
      await expectLater(
        client.callTool('echo', {}),
        throwsA(
          isA<MCPException>().having(
            (error) => error.message,
            'message',
            equals('Tool "echo" returned error'),
          ),
        ),
      );
    });

    test(
      'client closure during expired-session recovery rejects the caller',
      () async {
        late MCPClient client;
        final transport = _ScriptedTransport((request) {
          if (request.method == 'initialize') {
            return const JsonRpcResponse(
              result: {
                'protocolVersion': '2025-06-18',
                'capabilities': {},
                'serverInfo': {'name': 'test', 'version': '1'},
              },
            );
          }
          if (request.method == 'tools/list') {
            unawaited(client.close());
            throw MCPSessionExpiredException(
              method: 'POST',
              uri: Uri.https('mcp.test', '/'),
            );
          }
          return _complete(request);
        });
        client = MCPClient(transport: transport);
        await expectLater(client.tools(), throwsA(isA<MCPException>()));
        await client.close();
      },
    );

    test(
      'resource refresh stopped by close does not start a trailing read',
      () async {
        final transport = _ScriptedTransport((request) {
          if (request.method == 'initialize') {
            return const JsonRpcResponse(
              result: {
                'protocolVersion': '2025-06-18',
                'capabilities': {},
                'serverInfo': {'name': 'test', 'version': '1'},
              },
            );
          }
          return _complete(request);
        });
        final client = MCPClient(transport: transport);
        final updates = client
            .subscribeResource('file:///closed')
            .listen((_) {});
        transport.events.add({
          'jsonrpc': '2.0',
          'method': 'notifications/resources/updated',
          'params': {'uri': 'file:///closed'},
        });
        await client.close();
        await updates.cancel();
        expect(
          transport.requests.where(
            (request) => request.method == 'resources/read',
          ),
          isEmpty,
        );
      },
    );

    test(
      'resource refresh suppresses read errors after client close',
      () async {
        final pendingRead = Completer<JsonRpcResponse>();
        final readStarted = Completer<void>();
        final transport = _ScriptedTransport((request) {
          if (request.method == 'initialize') {
            return const JsonRpcResponse(
              result: {
                'protocolVersion': '2025-06-18',
                'capabilities': {},
                'serverInfo': {'name': 'test', 'version': '1'},
              },
            );
          }
          if (request.method == 'resources/read') {
            if (!readStarted.isCompleted) {
              readStarted.complete();
            }
            return pendingRead.future;
          }
          return _complete(request);
        });
        final client = MCPClient(transport: transport);
        final updates = client
            .subscribeResource('file:///failed')
            .listen((_) {});
        await client.initialize();
        transport.events.add({
          'jsonrpc': '2.0',
          'method': 'notifications/resources/updated',
          'params': {'uri': 'file:///failed'},
        });
        await readStarted.future;
        await client.close();
        pendingRead.completeError(StateError('read failed'));
        await updates.cancel();
      },
    );
  });

  group('HTTP protocol edges', () {
    test(
      'auth configuration rejects relative URIs and mismatched resource metadata',
      () {
        expect(
          () => MCPAuthConfiguration(resource: Uri.parse('/relative')),
          throwsA(isA<ArgumentError>()),
        );
        expect(
          () => MCPAuthConfiguration(
            resource: Uri.https('mcp.test', '/'),
            issuer: Uri.parse('/issuer'),
          ),
          throwsA(isA<ArgumentError>()),
        );
        final auth = MCPAuthConfiguration(
          resource: Uri.https('mcp.test', '/'),
          issuer: Uri.https('auth.test', '/'),
        );
        expect(
          () => auth.validateProtectedResource(
            MCPProtectedResourceMetadata(
              resource: Uri(scheme: 'https', host: 'other.test'),
              authorizationServers: [
                Uri(scheme: 'https', host: 'auth.test', path: '/'),
              ],
            ),
          ),
          throwsA(
            isA<MCPException>().having(
              (error) => error.message,
              'message',
              contains('resource mismatch'),
            ),
          ),
        );
        expect(
          () => auth.validateProtectedResource(
            MCPProtectedResourceMetadata(
              resource: Uri(scheme: 'https', host: 'mcp.test', path: '/'),
              authorizationServers: [],
            ),
          ),
          throwsA(
            isA<MCPException>().having(
              (error) => error.message,
              'message',
              contains('authorization server mismatch'),
            ),
          ),
        );
      },
    );

    test(
      'challenge parser accepts escapes and rejects malformed token values',
      () async {
        final auth = Uri.https('mcp.test', '/meta');
        final client = _HandlerClient(
          (_) async => _response(
            200,
            body: jsonEncode({
              'resource': 'https://mcp.test/',
              'authorization_servers': ['https://auth.test/'],
            }),
            headers: {'content-type': 'application/json'},
          ),
        );
        addTearDown(client.close);
        await MCPAuthDiscovery.discoverProtectedResource(
          Uri.https('mcp.test', '/'),
          wwwAuthenticate:
              "Bearer realm=\"a,\\\"b\", resource_metadata=\"$auth\"",
          client: client,
        );
        await expectLater(
          MCPAuthDiscovery.discoverProtectedResource(
            Uri.https('mcp.test', '/'),
            wwwAuthenticate: 'Bearer realm=x/y',
            client: client,
          ),
          throwsA(isA<MCPException>()),
        );
      },
    );

    test(
      'modern subscriptions retain and cancel acknowledged SSE streams',
      () async {
        final stream = StreamController<List<int>>();
        var cancelled = false;
        stream.onCancel = () => cancelled = true;
        final client = _HandlerClient((request) async {
          final body =
              jsonDecode(await request.finalize().bytesToString()) as Map;
          stream.add(
            utf8.encode(
              'data: ${jsonEncode({
                'jsonrpc': '2.0',
                'method': 'notifications/subscriptions/acknowledged',
                'params': {'requestId': body['id']},
              })}\n\n',
            ),
          );
          return http.StreamedResponse(
            stream.stream,
            200,
            headers: const {'content-type': 'text/event-stream'},
          );
        });
        final transport = StreamableHttpClientTransport(
          url: Uri.https('mcp.test', '/'),
          client: client,
        )..setProtocolVersion('2026-07-28');
        addTearDown(transport.close);

        await transport.send(
          JsonRpcRequest(method: 'subscriptions/listen', id: 9),
        );
        await transport.cancelSubscription(9);
        expect(cancelled, isTrue);
        await stream.close();
      },
    );

    test(
      'client cancels the HTTP subscription when its resource stream ends',
      () async {
        final stream = StreamController<List<int>>();
        var cancelled = false;
        final methods = <String>[];
        stream.onCancel = () => cancelled = true;
        final client = _HandlerClient((request) async {
          if (request.method == 'GET') return _response(405);
          final body =
              jsonDecode(await request.finalize().bytesToString()) as Map;
          methods.add(body['method'] as String);
          if (body['method'] == 'server/discover') {
            return _response(
              200,
              body: jsonEncode({
                'jsonrpc': '2.0',
                'id': body['id'],
                'result': {
                  'supportedVersions': ['2026-07-28'],
                },
              }),
              headers: {'content-type': 'application/json'},
            );
          }
          if (body['method'] == 'subscriptions/listen') {
            stream.add(
              utf8.encode(
                'data: ${jsonEncode({
                  'jsonrpc': '2.0',
                  'method': 'notifications/subscriptions/acknowledged',
                  'params': {'requestId': body['id']},
                })}\n\n',
              ),
            );
            return http.StreamedResponse(
              stream.stream,
              200,
              headers: const {'content-type': 'text/event-stream'},
            );
          }
          return _response(202);
        });
        final transport = StreamableHttpClientTransport(
          url: Uri.https('mcp.test', '/'),
          client: client,
        );
        final mcpClient = MCPClient(
          transport: transport,
          protocolMode: MCPProtocolMode.modern,
        );
        final subscription = mcpClient
            .subscribeResource('file:///cancel')
            .listen((_) {});
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await subscription.cancel();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(cancelled, isTrue);
        expect(methods, contains('notifications/cancelled'));
        await mcpClient.close();
        await stream.close();
      },
    );

    test(
      'closing transport cancels response streams from ordinary listen replies',
      () async {
        final stream = StreamController<List<int>>();
        var cancelled = false;
        stream.onCancel = () => cancelled = true;
        final client = _HandlerClient((request) async {
          final body =
              jsonDecode(await request.finalize().bytesToString()) as Map;
          stream.add(
            utf8.encode(
              'data: ${jsonEncode({
                'jsonrpc': '2.0',
                'id': body['id'],
                'result': {'resultType': 'complete'},
              })}\n\n',
            ),
          );
          return http.StreamedResponse(
            stream.stream,
            200,
            headers: const {'content-type': 'text/event-stream'},
          );
        });
        final transport = StreamableHttpClientTransport(
          url: Uri.https('mcp.test', '/'),
          client: client,
        )..setProtocolVersion('2026-07-28');

        await transport.send(
          JsonRpcRequest(method: 'subscriptions/listen', id: 10),
        );
        await transport.close();
        expect(cancelled, isTrue);
        await stream.close();
      },
    );

    test('non-ASCII MCP tool names use encoded-word headers', () async {
      final headers = <String>[];
      final client = _HandlerClient((request) async {
        headers.add(request.headers['mcp-name']!);
        final body =
            jsonDecode(await request.finalize().bytesToString()) as Map;
        return _response(
          200,
          body: jsonEncode({
            'jsonrpc': '2.0',
            'id': body['id'],
            'result': {'resultType': 'complete'},
          }),
          headers: {'content-type': 'application/json'},
        );
      });
      final transport = StreamableHttpClientTransport(
        url: Uri.https('mcp.test', '/'),
        client: client,
      )..setProtocolVersion('2026-07-28');
      addTearDown(transport.close);

      await transport.send(
        JsonRpcRequest(method: 'tools/call', id: 1, params: {'name': 'café'}),
      );
      expect(headers.single, startsWith('=?base64?'));
    });

    test(
      'notification listener drains failed responses and reconnects after stream errors',
      () async {
        var listenerRequests = 0;
        final client = _HandlerClient((request) async {
          if (request.method == 'GET') {
            listenerRequests++;
            if (listenerRequests == 1) {
              return _response(503, body: 'temporarily unavailable');
            }
            if (listenerRequests == 2) {
              throw StateError('listener request failed');
            }
            return http.StreamedResponse(
              Stream<List<int>>.error(StateError('listener stream failed')),
              200,
              headers: const {'content-type': 'text/event-stream'},
            );
          }
          return _response(
            200,
            body: jsonEncode({
              'jsonrpc': '2.0',
              'id': 1,
              'result': {'protocolVersion': '2025-06-18'},
            }),
            headers: {
              'content-type': 'application/json',
              'mcp-session-id': 'session',
            },
          );
        });
        final transport = StreamableHttpClientTransport(
          url: Uri.https('mcp.test', '/'),
          client: client,
          listenerReconnectDelay: const Duration(milliseconds: 1),
        );
        await transport.send(JsonRpcRequest(method: 'initialize', id: 1));
        transport.setProtocolVersion('2025-06-18');
        await transport.startNotificationListener();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await transport.close();
        expect(listenerRequests, greaterThanOrEqualTo(2));
        expect(client.closed, isFalse);
      },
    );

    test('close bounds error bodies and preserves transport context', () async {
      final client = _HandlerClient((request) async {
        if (request.method == 'DELETE') {
          return _response(503, body: 'private server detail');
        }
        return _response(
          200,
          body: jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': {}}),
          headers: {
            'content-type': 'application/json',
            'mcp-session-id': 'session',
          },
        );
      });
      final transport = StreamableHttpClientTransport(
        url: Uri.https('mcp.test', '/'),
        client: client,
      );
      await transport.send(JsonRpcRequest(method: 'initialize', id: 1));
      transport.setProtocolVersion('2025-06-18');
      await expectLater(
        transport.close(),
        throwsA(
          isA<MCPTransportException>().having(
            (error) => error.message,
            'message',
            contains('HTTP 503'),
          ),
        ),
      );
      expect(client.closed, isFalse);
    });
  });
}
