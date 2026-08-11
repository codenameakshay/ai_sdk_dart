import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_mcp/ai_sdk_mcp.dart';
import 'package:test/test.dart';

import 'support/fake_streamable_http_server.dart';

// ---------------------------------------------------------------------------
// Mock MCP HTTP server
// ---------------------------------------------------------------------------

/// A local HTTP server that responds to JSON-RPC MCP requests from queued responses.
class _MockMCPServer {
  _MockMCPServer._(this._server);

  final HttpServer _server;
  final List<Map<String, dynamic>> _requestLog = [];
  final _responseQueue = <Map<String, dynamic>>[];
  int? _initializedNotificationStatusCode;
  String _initializedNotificationBody = '';

  List<Map<String, dynamic>> get requestLog => List.unmodifiable(_requestLog);

  static Future<_MockMCPServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final mock = _MockMCPServer._(server);
    unawaited(mock._serve());
    return mock;
  }

  void enqueue(Map<String, dynamic> response) {
    _responseQueue.add(response);
  }

  /// Queue the standard initialize success + an empty response for the
  /// `notifications/initialized` fire-and-forget call.
  void enqueueInitialize({bool includeInitializedResponse = true}) {
    enqueue({
      'jsonrpc': '2.0',
      'result': {
        'protocolVersion': '2025-06-18',
        'capabilities': {'tools': {}},
        'serverInfo': {'name': 'test-server', 'version': '1.0.0'},
      },
    });
    if (includeInitializedResponse) {
      // notifications/initialized may get a response — provide one so the
      // legacy request path still completes.
      enqueue({'jsonrpc': '2.0', 'result': {}});
    }
  }

  void acceptInitializedNotification({int statusCode = 202, String body = ''}) {
    _initializedNotificationStatusCode = statusCode;
    _initializedNotificationBody = body;
  }

  Future<void> _serve() async {
    await for (final request in _server) {
      if (request.method == 'GET' || request.method == 'DELETE') {
        request.response.statusCode = 405;
        await request.response.close();
        continue;
      }

      final bodyText = await utf8.decoder.bind(request).join();
      try {
        final body = (jsonDecode(bodyText) as Map).cast<String, dynamic>();
        _requestLog.add(body);
        if (body['method'] == 'notifications/initialized' &&
            _initializedNotificationStatusCode != null) {
          request.response.statusCode = _initializedNotificationStatusCode!;
          if (_initializedNotificationBody.isNotEmpty) {
            request.response.write(_initializedNotificationBody);
          }
          await request.response.close();
          continue;
        }

        final id = body['id'];

        Map<String, dynamic> responseBody;
        if (_responseQueue.isNotEmpty) {
          responseBody = Map.of(_responseQueue.removeAt(0))..['id'] = id;
        } else {
          responseBody = {'jsonrpc': '2.0', 'id': id, 'result': {}};
        }

        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(responseBody));
      } catch (e) {
        request.response.statusCode = 500;
        request.response.write('{"error":"$e"}');
      }
      await request.response.close();
    }
  }

  Uri get uri =>
      Uri.parse('http://${_server.address.address}:${_server.port}/mcp');

  Future<void> close() => _server.close(force: true);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

MCPClient _client(_MockMCPServer mock) =>
    MCPClient(transport: StreamableHttpClientTransport(url: mock.uri));

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('MCPClient conformance', () {
    // ── initialize() ────────────────────────────────────────────────────────

    group('initialize()', () {
      test(
        'sends protocol version "2025-06-18" and tools capability',
        () async {
          final mock = await _MockMCPServer.start();
          addTearDown(mock.close);
          mock.enqueueInitialize();

          final client = _client(mock);
          addTearDown(client.close);

          await client.initialize();

          expect(mock.requestLog, isNotEmpty);
          final initReq = mock.requestLog.first;
          expect(initReq['method'], 'initialize');
          final params = initReq['params'] as Map<String, dynamic>;
          expect(params['protocolVersion'], '2025-06-18');
          final caps = params['capabilities'] as Map<String, dynamic>;
          expect(caps.keys, contains('tools'));
        },
      );

      test(
        'is idempotent — second call does not send another initialize',
        () async {
          final mock = await _MockMCPServer.start();
          addTearDown(mock.close);
          mock.enqueueInitialize();

          final client = _client(mock);
          addTearDown(client.close);

          await client.initialize();
          await client.initialize(); // no-op

          final initCount = mock.requestLog
              .where((r) => r['method'] == 'initialize')
              .length;
          expect(initCount, 1);
        },
      );

      test(
        'sends notifications/initialized without an id and accepts 202 with an empty body',
        () async {
          final mock = await _MockMCPServer.start();
          addTearDown(mock.close);
          mock.enqueueInitialize(includeInitializedResponse: false);
          mock.acceptInitializedNotification();

          final client = _client(mock);
          addTearDown(client.close);

          await client.initialize();

          expect(mock.requestLog, hasLength(2));
          final initialized = mock.requestLog[1];
          expect(initialized['method'], 'notifications/initialized');
          expect(initialized.containsKey('id'), isFalse);
        },
      );

      test(
        'throws MCPException when server returns a JSON-RPC error',
        () async {
          final mock = await _MockMCPServer.start();
          addTearDown(mock.close);

          mock.enqueue({
            'jsonrpc': '2.0',
            'error': {'code': -32600, 'message': 'Invalid Request'},
          });

          final client = _client(mock);
          addTearDown(client.close);

          await expectLater(
            client.initialize(),
            throwsA(
              isA<MCPException>().having(
                (e) => e.message,
                'message',
                contains('Initialize failed'),
              ),
            ),
          );
        },
      );

      test(
        'concurrent cold starts share one initialize handshake and one initialized notification',
        () async {
          final server = await FakeStreamableHttpServer.start();
          addTearDown(server.close);
          final releaseInitialize = Completer<void>();
          server.queueInitializeResponse(
            sessionId: 'session-1',
            waitFor: releaseInitialize.future,
          );
          server.queueJsonResponse({
            'jsonrpc': '2.0',
            'result': {
              'tools': [
                {
                  'name': 'ping',
                  'inputSchema': {'type': 'object'},
                },
              ],
            },
          });
          server.queueJsonResponse({
            'jsonrpc': '2.0',
            'result': {'resources': []},
          });

          final client = MCPClient(
            transport: StreamableHttpClientTransport(url: server.uri),
          );
          addTearDown(client.close);

          final toolsFuture = client.tools();
          final resourcesFuture = client.listResources();
          await Future<void>.delayed(const Duration(milliseconds: 30));
          releaseInitialize.complete();

          final tools = await toolsFuture;
          final resources = await resourcesFuture;
          expect(tools.keys, contains('ping'));
          expect(resources, isEmpty);

          final initializeCount = server.requestLog
              .where((request) => request.body?['method'] == 'initialize')
              .length;
          final initializedCount = server.requestLog
              .where(
                (request) =>
                    request.body?['method'] == 'notifications/initialized',
              )
              .length;
          expect(initializeCount, 1);
          expect(initializedCount, 1);
        },
      );

      test(
        'missing protocolVersion fails handshake before initialized and does not retain session',
        () async {
          final server = await FakeStreamableHttpServer.start();
          addTearDown(server.close);
          server.queueJsonResponse(
            {
              'jsonrpc': '2.0',
              'result': {
                'capabilities': {'tools': {}},
                'serverInfo': {'name': 'bad-server', 'version': '1.0.0'},
              },
            },
            headers: const {'Mcp-Session-Id': 'session-1'},
          );

          final client = MCPClient(
            transport: StreamableHttpClientTransport(url: server.uri),
          );
          addTearDown(client.close);

          await expectLater(
            client.initialize(),
            throwsA(
              isA<MCPException>().having(
                (e) => e.message,
                'message',
                contains('protocolVersion'),
              ),
            ),
          );

          expect(
            server.requestLog.any(
              (request) =>
                  request.body?['method'] == 'notifications/initialized',
            ),
            isFalse,
          );

          await client.close();
          expect(server.deleteRequestCount, 0);
        },
      );

      test(
        'unsupported protocolVersion fails handshake before initialized',
        () async {
          final server = await FakeStreamableHttpServer.start();
          addTearDown(server.close);
          server.queueInitializeResponse(
            protocolVersion: '2024-11-05',
            sessionId: 'session-1',
          );

          final client = MCPClient(
            transport: StreamableHttpClientTransport(url: server.uri),
          );
          addTearDown(client.close);

          await expectLater(
            client.initialize(),
            throwsA(
              isA<MCPException>().having(
                (e) => e.message,
                'message',
                contains('Unsupported protocolVersion'),
              ),
            ),
          );

          expect(
            server.requestLog.any(
              (request) =>
                  request.body?['method'] == 'notifications/initialized',
            ),
            isFalse,
          );
        },
      );
    });

    // ── tools() ─────────────────────────────────────────────────────────────

    group('tools()', () {
      test('returns a ToolSet with correct tool names from server', () async {
        final mock = await _MockMCPServer.start();
        addTearDown(mock.close);
        mock.enqueueInitialize();
        mock.enqueue({
          'jsonrpc': '2.0',
          'result': {
            'tools': [
              {
                'name': 'get_weather',
                'description': 'Get current weather',
                'inputSchema': {
                  'type': 'object',
                  'properties': {
                    'city': {'type': 'string'},
                  },
                },
              },
              {
                'name': 'calculate',
                'description': 'Arithmetic',
                'inputSchema': {'type': 'object'},
              },
            ],
          },
        });

        final client = _client(mock);
        addTearDown(client.close);

        final toolSet = await client.tools();
        expect(toolSet.length, 2);
        expect(toolSet.keys, containsAll(['get_weather', 'calculate']));
      });

      test('returns empty ToolSet when server returns no tools', () async {
        final mock = await _MockMCPServer.start();
        addTearDown(mock.close);
        mock.enqueueInitialize();
        mock.enqueue({
          'jsonrpc': '2.0',
          'result': {'tools': []},
        });

        final client = _client(mock);
        addTearDown(client.close);

        final toolSet = await client.tools();
        expect(toolSet, isEmpty);
      });
    });

    // ── callTool() ───────────────────────────────────────────────────────────

    group('callTool()', () {
      test('returns text content from MCP tool response', () async {
        final mock = await _MockMCPServer.start();
        addTearDown(mock.close);
        mock.enqueueInitialize();
        mock.enqueue({
          'jsonrpc': '2.0',
          'result': {
            'content': [
              {'type': 'text', 'text': 'Sunny, 18°C'},
            ],
            'isError': false,
          },
        });

        final client = _client(mock);
        addTearDown(client.close);

        final result = await client.callTool('get_weather', {'city': 'Paris'});
        expect(result, 'Sunny, 18°C');
      });

      test('throws MCPException when isError is true', () async {
        final mock = await _MockMCPServer.start();
        addTearDown(mock.close);
        mock.enqueueInitialize();
        mock.enqueue({
          'jsonrpc': '2.0',
          'result': {
            'content': [
              {'type': 'text', 'text': 'Unknown city'},
            ],
            'isError': true,
          },
        });

        final client = _client(mock);
        addTearDown(client.close);

        await expectLater(
          client.callTool('get_weather', {'city': 'INVALID'}),
          throwsA(
            isA<MCPException>().having(
              (e) => e.message,
              'message',
              contains('Unknown city'),
            ),
          ),
        );
      });

      test('sends tools/call with correct name and arguments', () async {
        final mock = await _MockMCPServer.start();
        addTearDown(mock.close);
        mock.enqueueInitialize();
        mock.enqueue({
          'jsonrpc': '2.0',
          'result': {
            'content': [
              {'type': 'text', 'text': '42'},
            ],
            'isError': false,
          },
        });

        final client = _client(mock);
        addTearDown(client.close);

        await client.callTool('calculate', {'expression': '6*7'});

        final callReq = mock.requestLog.firstWhere(
          (r) => r['method'] == 'tools/call',
        );
        expect(callReq['params']['name'], 'calculate');
        expect((callReq['params']['arguments'] as Map)['expression'], '6*7');
      });
    });

    // ── listPrompts() ────────────────────────────────────────────────────────

    group('listPrompts()', () {
      test('returns prompt list from server', () async {
        final mock = await _MockMCPServer.start();
        addTearDown(mock.close);
        mock.enqueueInitialize();
        mock.enqueue({
          'jsonrpc': '2.0',
          'result': {
            'prompts': [
              {
                'name': 'summarize',
                'description': 'Summarizes a document',
                'arguments': [
                  {'name': 'document', 'required': true},
                  {'name': 'length', 'description': 'Target length'},
                ],
              },
              {'name': 'translate', 'description': 'Translate text'},
            ],
          },
        });

        final client = _client(mock);
        addTearDown(client.close);

        final prompts = await client.listPrompts();
        expect(prompts.length, 2);
        expect(prompts.first.name, 'summarize');
        expect(prompts.first.description, 'Summarizes a document');
        expect(prompts.first.arguments.length, 2);
        expect(prompts.first.arguments.first.name, 'document');
        expect(prompts.first.arguments.first.required, isTrue);
        expect(prompts[1].name, 'translate');
      });

      test('returns empty list when server has no prompts', () async {
        final mock = await _MockMCPServer.start();
        addTearDown(mock.close);
        mock.enqueueInitialize();
        mock.enqueue({
          'jsonrpc': '2.0',
          'result': {'prompts': []},
        });

        final client = _client(mock);
        addTearDown(client.close);

        final prompts = await client.listPrompts();
        expect(prompts, isEmpty);
      });

      test('sends prompts/list method', () async {
        final mock = await _MockMCPServer.start();
        addTearDown(mock.close);
        mock.enqueueInitialize();
        mock.enqueue({
          'jsonrpc': '2.0',
          'result': {'prompts': []},
        });

        final client = _client(mock);
        addTearDown(client.close);

        await client.listPrompts();

        expect(
          mock.requestLog.any((r) => r['method'] == 'prompts/list'),
          isTrue,
        );
      });
    });

    // ── getPrompt() ───────────────────────────────────────────────────────────

    group('getPrompt()', () {
      test('returns rendered prompt messages', () async {
        final mock = await _MockMCPServer.start();
        addTearDown(mock.close);
        mock.enqueueInitialize();
        mock.enqueue({
          'jsonrpc': '2.0',
          'result': {
            'description': 'Summarize this',
            'messages': [
              {
                'role': 'user',
                'content': {'type': 'text', 'text': 'Summarize: Hello world'},
              },
            ],
          },
        });

        final client = _client(mock);
        addTearDown(client.close);

        final result = await client.getPrompt(
          'summarize',
          arguments: {'document': 'Hello world'},
        );
        expect(result.description, 'Summarize this');
        expect(result.messages.length, 1);
        expect(result.messages.first.role, 'user');
        expect(result.messages.first.content, 'Summarize: Hello world');
      });

      test('sends prompts/get with name and arguments', () async {
        final mock = await _MockMCPServer.start();
        addTearDown(mock.close);
        mock.enqueueInitialize();
        mock.enqueue({
          'jsonrpc': '2.0',
          'result': {'messages': []},
        });

        final client = _client(mock);
        addTearDown(client.close);

        await client.getPrompt('summarize', arguments: {'doc': 'test'});

        final req = mock.requestLog.firstWhere(
          (r) => r['method'] == 'prompts/get',
        );
        expect(req['params']['name'], 'summarize');
        expect((req['params']['arguments'] as Map)['doc'], 'test');
      });

      test('throws MCPException on server error', () async {
        final mock = await _MockMCPServer.start();
        addTearDown(mock.close);
        mock.enqueueInitialize();
        mock.enqueue({
          'jsonrpc': '2.0',
          'error': {'code': -32601, 'message': 'Prompt not found'},
        });

        final client = _client(mock);
        addTearDown(client.close);

        await expectLater(
          client.getPrompt('unknown'),
          throwsA(isA<MCPException>()),
        );
      });
    });

    // ── listResources() ───────────────────────────────────────────────────────

    group('listResources()', () {
      test('returns resource list from server', () async {
        final mock = await _MockMCPServer.start();
        addTearDown(mock.close);
        mock.enqueueInitialize();
        mock.enqueue({
          'jsonrpc': '2.0',
          'result': {
            'resources': [
              {
                'uri': 'file:///data/config.json',
                'name': 'config.json',
                'description': 'App configuration',
                'mimeType': 'application/json',
              },
              {'uri': 'file:///data/log.txt', 'name': 'log.txt'},
            ],
          },
        });

        final client = _client(mock);
        addTearDown(client.close);

        final resources = await client.listResources();
        expect(resources.length, 2);
        expect(resources.first.uri, 'file:///data/config.json');
        expect(resources.first.name, 'config.json');
        expect(resources.first.mimeType, 'application/json');
        expect(resources[1].description, isNull);
      });

      test('returns empty list when server has no resources', () async {
        final mock = await _MockMCPServer.start();
        addTearDown(mock.close);
        mock.enqueueInitialize();
        mock.enqueue({
          'jsonrpc': '2.0',
          'result': {'resources': []},
        });

        final client = _client(mock);
        addTearDown(client.close);

        final resources = await client.listResources();
        expect(resources, isEmpty);
      });
    });

    // ── readResource() ────────────────────────────────────────────────────────

    group('readResource()', () {
      test('returns resource content', () async {
        final mock = await _MockMCPServer.start();
        addTearDown(mock.close);
        mock.enqueueInitialize();
        mock.enqueue({
          'jsonrpc': '2.0',
          'result': {
            'contents': [
              {
                'uri': 'file:///data/config.json',
                'mimeType': 'application/json',
                'text': '{"debug": true}',
              },
            ],
          },
        });

        final client = _client(mock);
        addTearDown(client.close);

        final content = await client.readResource('file:///data/config.json');
        expect(content.uri, 'file:///data/config.json');
        expect(content.mimeType, 'application/json');
        expect(content.text, '{"debug": true}');
      });

      test('sends resources/read with correct uri', () async {
        final mock = await _MockMCPServer.start();
        addTearDown(mock.close);
        mock.enqueueInitialize();
        mock.enqueue({
          'jsonrpc': '2.0',
          'result': {
            'contents': [
              {'uri': 'file:///x', 'mimeType': 'text/plain', 'text': 'hello'},
            ],
          },
        });

        final client = _client(mock);
        addTearDown(client.close);

        await client.readResource('file:///x');

        final req = mock.requestLog.firstWhere(
          (r) => r['method'] == 'resources/read',
        );
        expect(req['params']['uri'], 'file:///x');
      });

      test('throws MCPException on server error', () async {
        final mock = await _MockMCPServer.start();
        addTearDown(mock.close);
        mock.enqueueInitialize();
        mock.enqueue({
          'jsonrpc': '2.0',
          'error': {'code': -32601, 'message': 'Resource not found'},
        });

        final client = _client(mock);
        addTearDown(client.close);

        await expectLater(
          client.readResource('file:///missing'),
          throwsA(isA<MCPException>()),
        );
      });
    });

    // ── subscribeResource / notifyResourceUpdated ─────────────────────────────

    group('resource subscriptions', () {
      test('subscribeResource returns a stream', () async {
        final mock = await _MockMCPServer.start();
        addTearDown(mock.close);
        mock.enqueueInitialize();
        // Server accepts subscribe silently
        mock.enqueue({'jsonrpc': '2.0', 'result': {}});

        final client = _client(mock);
        addTearDown(client.close);

        final stream = client.subscribeResource('file:///data/log.txt');
        expect(stream, isA<Stream<MCPResourceContent>>());
      });

      test('notifyResourceUpdated pushes to subscribers', () async {
        final mock = await _MockMCPServer.start();
        addTearDown(mock.close);
        mock.enqueueInitialize();
        mock.enqueue({'jsonrpc': '2.0', 'result': {}});

        final client = _client(mock);
        addTearDown(client.close);

        final updates = <MCPResourceContent>[];
        final subscription = client
            .subscribeResource('file:///data/log.txt')
            .listen(updates.add);
        addTearDown(subscription.cancel);

        await Future<void>.delayed(Duration.zero); // let subscribe settle

        client.notifyResourceUpdated(
          'file:///data/log.txt',
          const MCPResourceContent(
            uri: 'file:///data/log.txt',
            mimeType: 'text/plain',
            text: 'new content',
          ),
        );

        await Future<void>.delayed(Duration.zero);
        expect(updates.length, 1);
        expect(updates.first.text, 'new content');
      });
    });

    // ── MCPReconnectPolicy ────────────────────────────────────────────────────

    group('MCPReconnectPolicy', () {
      test('delayFor returns increasing delays', () {
        const policy = MCPReconnectPolicy(
          initialDelayMs: 100,
          backoffFactor: 2.0,
          maxDelayMs: 5000,
        );
        final d0 = policy.delayFor(0);
        final d1 = policy.delayFor(1);
        final d2 = policy.delayFor(2);
        expect(d1.inMilliseconds, greaterThanOrEqualTo(d0.inMilliseconds));
        expect(d2.inMilliseconds, greaterThanOrEqualTo(d1.inMilliseconds));
      });

      test('delayFor caps at maxDelayMs', () {
        const policy = MCPReconnectPolicy(
          initialDelayMs: 1000,
          backoffFactor: 10.0,
          maxDelayMs: 3000,
        );
        final delay = policy.delayFor(10);
        expect(delay.inMilliseconds, lessThanOrEqualTo(3000));
      });

      test('MCPClient accepts reconnectPolicy constructor param', () {
        final mockTransport = StreamableHttpClientTransport(
          url: Uri.parse('http://localhost:9999/mcp'),
        );
        final client = MCPClient(
          transport: mockTransport,
          reconnectPolicy: const MCPReconnectPolicy(maxAttempts: 3),
        );
        expect(client.reconnectPolicy?.maxAttempts, 3);
        client.close();
      });
    });

    // ── capabilities advertised in initialize() ───────────────────────────────

    group('capabilities', () {
      test(
        'initialize advertises prompts and resources capabilities',
        () async {
          final mock = await _MockMCPServer.start();
          addTearDown(mock.close);
          mock.enqueueInitialize();

          final client = _client(mock);
          addTearDown(client.close);

          await client.initialize();

          final initReq = mock.requestLog.first;
          final caps =
              (initReq['params'] as Map)['capabilities']
                  as Map<String, dynamic>;
          expect(caps.keys, contains('prompts'));
          expect(caps.keys, contains('resources'));
          expect((caps['resources'] as Map)['subscribe'], isTrue);
        },
      );
    });

    // ── MCPException ─────────────────────────────────────────────────────────

    group('MCPException', () {
      test('has a message field', () {
        const e = MCPException('something went wrong');
        expect(e.message, 'something went wrong');
      });

      test('toString includes MCPException prefix and message', () {
        const e = MCPException('oops');
        expect(e.toString(), contains('MCPException'));
        expect(e.toString(), contains('oops'));
      });
    });

    // ── Transport types ──────────────────────────────────────────────────────

    group('transport types', () {
      test('StreamableHttpClientTransport accepts url and headers', () {
        final t = StreamableHttpClientTransport(
          url: Uri.parse('http://localhost:3000/mcp'),
          headers: {'Authorization': 'Bearer token'},
        );
        expect(t.url.path, '/mcp');
        expect(t.headers?['Authorization'], 'Bearer token');
      });

      test('StdioMCPTransport accepts command and args', () {
        final t = StdioMCPTransport(
          command: 'npx',
          args: ['-y', '@modelcontextprotocol/server-filesystem', '/tmp'],
        );
        expect(t.command, 'npx');
        expect(t.args, [
          '-y',
          '@modelcontextprotocol/server-filesystem',
          '/tmp',
        ]);
      });
    });

    group('StreamableHttpClientTransport', () {
      test(
        'negotiates protocol version, captures session ID, and applies headers on subsequent requests',
        () async {
          final server = await FakeStreamableHttpServer.start();
          addTearDown(server.close);
          server.queueInitializeResponse(sessionId: 'session-1');
          server.queueJsonResponse({
            'jsonrpc': '2.0',
            'result': {
              'tools': [
                {
                  'name': 'ping',
                  'inputSchema': {'type': 'object'},
                },
              ],
            },
          });

          final transport = StreamableHttpClientTransport(
            url: server.uri,
            headers: {'Authorization': 'Bearer token'},
          );
          final client = MCPClient(transport: transport);
          addTearDown(client.close);

          final tools = await client.tools();
          expect(tools.keys, contains('ping'));

          await client.close();

          final initializeRequest = server.requestLog.firstWhere(
            (request) => request.body?['method'] == 'initialize',
          );
          expect(
            initializeRequest.headers['accept'],
            contains('application/json'),
          );
          expect(
            initializeRequest.headers['accept'],
            contains('text/event-stream'),
          );
          expect(
            initializeRequest.headers.containsKey('mcp-session-id'),
            isFalse,
          );
          expect(
            initializeRequest.headers.containsKey('mcp-protocol-version'),
            isFalse,
          );

          final initializedRequest = server.requestLog.firstWhere(
            (request) => request.body?['method'] == 'notifications/initialized',
          );
          expect(initializedRequest.headers['mcp-session-id'], 'session-1');
          expect(
            initializedRequest.headers['mcp-protocol-version'],
            '2025-06-18',
          );
          expect(initializedRequest.headers['authorization'], 'Bearer token');

          final toolsRequest = server.requestLog.firstWhere(
            (request) => request.body?['method'] == 'tools/list',
          );
          expect(toolsRequest.headers['mcp-session-id'], 'session-1');
          expect(toolsRequest.headers['mcp-protocol-version'], '2025-06-18');

          final deleteRequest = server.requestLog.firstWhere(
            (request) => request.method == 'DELETE',
          );
          expect(deleteRequest.headers['mcp-session-id'], 'session-1');
          expect(deleteRequest.headers['mcp-protocol-version'], '2025-06-18');
          expect(deleteRequest.headers['authorization'], 'Bearer token');
        },
      );

      test(
        'supports SSE POST responses and dispatches intervening notifications',
        () async {
          final server = await FakeStreamableHttpServer.start();
          addTearDown(server.close);
          server.queueInitializeResponse(sessionId: 'session-1');
          server.queueSseResponse([
            FakeSseFrame.json({
              'jsonrpc': '2.0',
              'method': 'notifications/message',
              'params': {'level': 'info', 'text': 'hello'},
            }),
            FakeSseFrame.json({
              'jsonrpc': '2.0',
              'result': {
                'tools': [
                  {
                    'name': 'ping',
                    'inputSchema': {'type': 'object'},
                  },
                ],
              },
            }),
          ]);

          final transport = StreamableHttpClientTransport(url: server.uri);
          final client = MCPClient(transport: transport);
          addTearDown(client.close);

          final notifications = <Map<String, dynamic>>[];
          final sub = transport.notifications.listen(notifications.add);
          addTearDown(sub.cancel);

          final tools = await client.tools();
          expect(tools.keys, contains('ping'));
          expect(notifications, hasLength(1));
          expect(notifications.single['method'], 'notifications/message');
        },
      );

      test(
        'starts the optional GET listener after initialized and surfaces notifications',
        () async {
          final server = await FakeStreamableHttpServer.start();
          addTearDown(server.close);
          server.getListenerSupported = true;
          server.queueInitializeResponse(sessionId: 'session-1');

          final transport = StreamableHttpClientTransport(url: server.uri);
          final client = MCPClient(transport: transport);
          addTearDown(client.close);

          final notifications = <Map<String, dynamic>>[];
          final sub = transport.notifications.listen(notifications.add);
          addTearDown(sub.cancel);

          await client.initialize();
          await server.pushListenerJson({
            'jsonrpc': '2.0',
            'method': 'notifications/message',
            'params': {'text': 'listener'},
          });

          await Future<void>.delayed(const Duration(milliseconds: 50));
          expect(server.getRequestCount, 1);
          expect(notifications, hasLength(1));
          expect(notifications.single['method'], 'notifications/message');
        },
      );

      test(
        'reconnects the GET listener with Last-Event-ID after an unexpected disconnect',
        () async {
          final server = await FakeStreamableHttpServer.start();
          addTearDown(server.close);
          server.getListenerSupported = true;
          server.queueInitializeResponse(sessionId: 'session-1');

          final transport = StreamableHttpClientTransport(
            url: server.uri,
            listenerReconnectDelay: const Duration(milliseconds: 25),
          );
          final client = MCPClient(transport: transport);
          addTearDown(client.close);

          final notifications = <Map<String, dynamic>>[];
          final sub = transport.notifications.listen(notifications.add);
          addTearDown(sub.cancel);

          await client.initialize();

          server.disconnectListenerAfterNextPush();
          await server.pushListenerJson({
            'jsonrpc': '2.0',
            'method': 'notifications/message',
            'params': {'order': 1},
          }, id: 'evt-1');

          for (var attempt = 0; attempt < 20; attempt++) {
            if (server.listenerConnectionCount >= 2) {
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 25));
          }

          await server.pushListenerJson({
            'jsonrpc': '2.0',
            'method': 'notifications/message',
            'params': {'order': 2},
          }, id: 'evt-2');

          await Future<void>.delayed(const Duration(milliseconds: 75));
          expect(server.listenerConnectionCount, 2);
          expect(server.listenerLastEventIds, [null, 'evt-1']);
          expect(
            notifications.map((message) => (message['params'] as Map)['order']),
            [1, 2],
          );
        },
      );

      test(
        'server-pushed resources/updated reaches resource subscribers',
        () async {
          final server = await FakeStreamableHttpServer.start();
          addTearDown(server.close);
          server.getListenerSupported = true;
          server.queueInitializeResponse(sessionId: 'session-1');
          server.queueJsonResponse({'jsonrpc': '2.0', 'result': {}});
          server.queueJsonResponse({
            'jsonrpc': '2.0',
            'result': {
              'contents': [
                {
                  'uri': 'file:///watched.txt',
                  'mimeType': 'text/plain',
                  'text': 'updated body',
                },
              ],
            },
          });

          final client = MCPClient(
            transport: StreamableHttpClientTransport(url: server.uri),
          );
          addTearDown(client.close);

          final updates = <MCPResourceContent>[];
          final sub = client
              .subscribeResource('file:///watched.txt')
              .listen(updates.add);
          addTearDown(sub.cancel);

          await Future<void>.delayed(const Duration(milliseconds: 100));
          await server.pushListenerJson({
            'jsonrpc': '2.0',
            'method': 'notifications/resources/updated',
            'params': {'uri': 'file:///watched.txt'},
          });

          await Future<void>.delayed(const Duration(milliseconds: 150));
          expect(updates, hasLength(1));
          expect(updates.single.text, 'updated body');
        },
      );

      test('parses multi-line SSE data and event IDs correctly', () async {
        final server = await FakeStreamableHttpServer.start();
        addTearDown(server.close);
        server.getListenerSupported = true;
        server.queueInitializeResponse(sessionId: 'session-1');

        final transport = StreamableHttpClientTransport(url: server.uri);
        final client = MCPClient(transport: transport);
        addTearDown(client.close);

        final notifications = <Map<String, dynamic>>[];
        final sub = transport.notifications.listen(notifications.add);
        addTearDown(sub.cancel);

        await client.initialize();
        await server.pushListenerFrame(
          const FakeSseFrame(
            event: 'message',
            id: 'evt-1',
            comment: 'keepalive',
            dataLines: [
              '{"jsonrpc":"2.0",',
              '"method":"notifications/message","params":{"text":"line one\\nline two"}}',
            ],
          ),
        );

        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(notifications, hasLength(1));
        expect(
          (notifications.single['params'] as Map)['text'],
          'line one\nline two',
        );
      });

      test('reinitializes and retries after a session-scoped 404', () async {
        final server = await FakeStreamableHttpServer.start();
        addTearDown(server.close);
        server.queueInitializeResponse(sessionId: 'session-1');

        final client = MCPClient(
          transport: StreamableHttpClientTransport(url: server.uri),
        );
        addTearDown(client.close);

        await client.initialize();

        server.expireCurrentSession();
        server.queueInitializeResponse(sessionId: 'session-2');
        server.queueJsonResponse({
          'jsonrpc': '2.0',
          'result': {
            'tools': [
              {
                'name': 'ping',
                'inputSchema': {'type': 'object'},
              },
            ],
          },
        });

        final tools = await client.tools();
        expect(tools.keys, contains('ping'));

        final initializeCount = server.requestLog
            .where((request) => request.body?['method'] == 'initialize')
            .length;
        expect(initializeCount, 2);

        final lastToolsRequest = server.requestLog.lastWhere(
          (request) => request.body?['method'] == 'tools/list',
        );
        expect(lastToolsRequest.headers['mcp-session-id'], 'session-2');
      });

      test(
        'concurrent session-expired requests share one recovery handshake and one initialized notification',
        () async {
          final server = await FakeStreamableHttpServer.start();
          addTearDown(server.close);
          server.queueInitializeResponse(sessionId: 'session-1');

          final client = MCPClient(
            transport: StreamableHttpClientTransport(url: server.uri),
          );
          addTearDown(client.close);

          await client.initialize();
          server.expireCurrentSession();

          final releaseRecovery = Completer<void>();
          server.queueInitializeResponse(
            sessionId: 'session-2',
            waitFor: releaseRecovery.future,
          );
          server.queueJsonResponse({
            'jsonrpc': '2.0',
            'result': {
              'tools': [
                {
                  'name': 'ping',
                  'inputSchema': {'type': 'object'},
                },
              ],
            },
          });
          server.queueJsonResponse({
            'jsonrpc': '2.0',
            'result': {'resources': []},
          });

          final toolsFuture = client.tools();
          final resourcesFuture = client.listResources();
          await Future<void>.delayed(const Duration(milliseconds: 30));
          releaseRecovery.complete();

          final tools = await toolsFuture;
          final resources = await resourcesFuture;
          expect(tools.keys, contains('ping'));
          expect(resources, isEmpty);

          final initializeCount = server.requestLog
              .where((request) => request.body?['method'] == 'initialize')
              .length;
          final initializedCount = server.requestLog
              .where(
                (request) =>
                    request.body?['method'] == 'notifications/initialized',
              )
              .length;
          expect(initializeCount, 2);
          expect(initializedCount, 2);
        },
      );

      test(
        'listener 404 triggers background reinitialize and replays subscriptions before listener resumes',
        () async {
          final server = await FakeStreamableHttpServer.start();
          addTearDown(server.close);
          server.getListenerSupported = true;
          server.queueInitializeResponse(sessionId: 'session-1');
          server.queueJsonResponse({'jsonrpc': '2.0', 'result': {}});

          final client = MCPClient(
            transport: StreamableHttpClientTransport(
              url: server.uri,
              listenerReconnectDelay: const Duration(milliseconds: 25),
            ),
          );
          addTearDown(client.close);

          final updates = <MCPResourceContent>[];
          final sub = client
              .subscribeResource('file:///watched.txt')
              .listen(updates.add);
          addTearDown(sub.cancel);

          await server.waitForListenerConnection();
          server.queueGetStatusCode(404);
          server.queueInitializeResponse(sessionId: 'session-2');
          server.queueJsonResponse({'jsonrpc': '2.0', 'result': {}});
          server.queueJsonResponse({
            'jsonrpc': '2.0',
            'result': {
              'contents': [
                {
                  'uri': 'file:///watched.txt',
                  'mimeType': 'text/plain',
                  'text': 'replayed update',
                },
              ],
            },
          });

          await server.disconnectActiveListener();

          for (var attempt = 0; attempt < 40; attempt++) {
            final initializeCount = server.requestLog
                .where((request) => request.body?['method'] == 'initialize')
                .length;
            final subscribeCount = server.requestLog
                .where(
                  (request) => request.body?['method'] == 'resources/subscribe',
                )
                .length;
            if (initializeCount >= 2 &&
                subscribeCount >= 2 &&
                server.listenerConnectionCount >= 3) {
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 25));
          }

          await server.pushListenerJson({
            'jsonrpc': '2.0',
            'method': 'notifications/resources/updated',
            'params': {'uri': 'file:///watched.txt'},
          });

          await Future<void>.delayed(const Duration(milliseconds: 100));
          expect(updates.map((update) => update.text), ['replayed update']);

          final methods = server.requestLog
              .map(
                (request) => request.method == 'GET'
                    ? 'GET'
                    : (request.body?['method']?.toString() ?? request.method),
              )
              .toList();
          final secondInitializeIndex = methods.indexOf(
            'initialize',
            methods.indexOf('initialize') + 1,
          );
          final secondInitializedIndex = methods.indexOf(
            'notifications/initialized',
            methods.indexOf('notifications/initialized') + 1,
          );
          final secondSubscribeIndex = methods.indexOf(
            'resources/subscribe',
            methods.indexOf('resources/subscribe') + 1,
          );
          final resumedListenerIndex = methods.lastIndexOf('GET');

          expect(secondInitializeIndex, greaterThanOrEqualTo(0));
          expect(secondInitializedIndex, greaterThan(secondInitializeIndex));
          expect(secondSubscribeIndex, greaterThan(secondInitializedIndex));
          expect(resumedListenerIndex, greaterThan(secondSubscribeIndex));
        },
      );

      test('operations after close throw MCPException', () async {
        final server = await FakeStreamableHttpServer.start();
        addTearDown(server.close);
        server.queueInitializeResponse(sessionId: 'session-1');

        final client = MCPClient(
          transport: StreamableHttpClientTransport(url: server.uri),
        );
        await client.initialize();
        await client.close();

        await expectLater(client.listResources(), throwsA(isA<MCPException>()));
      });
    });
  });
}
