import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_mcp/ai_sdk_mcp.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Mock MCP HTTP server
// ---------------------------------------------------------------------------

/// A local HTTP server that responds to JSON-RPC MCP requests from queued responses.
class _MockMCPServer {
  _MockMCPServer._(this._server);

  final HttpServer _server;
  final List<Map<String, dynamic>> _requestLog = [];
  final _responseQueue = <Map<String, dynamic>>[];

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
  void enqueueInitialize() {
    enqueue({
      'jsonrpc': '2.0',
      'result': {
        'protocolVersion': '2024-11-05',
        'capabilities': {'tools': {}},
        'serverInfo': {'name': 'test-server', 'version': '1.0.0'},
      },
    });
    // notifications/initialized may get a response — provide one so the client
    // doesn't hang, even though errors from it are silently ignored.
    enqueue({'jsonrpc': '2.0', 'result': {}});
  }

  Future<void> _serve() async {
    await for (final request in _server) {
      final bodyText = await utf8.decoder.bind(request).join();
      try {
        final body = (jsonDecode(bodyText) as Map).cast<String, dynamic>();
        _requestLog.add(body);
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

MCPClient _client(_MockMCPServer mock) => MCPClient(
  transport: SseClientTransport(url: mock.uri, postUrl: mock.uri),
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('MCPClient conformance', () {
    // ── initialize() ────────────────────────────────────────────────────────

    group('initialize()', () {
      test(
        'sends protocol version "2024-11-05" and tools capability',
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
          expect(params['protocolVersion'], '2024-11-05');
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
      test('SseClientTransport accepts url and optional postUrl', () {
        final t = SseClientTransport(
          url: Uri.parse('http://localhost:3000/sse'),
          postUrl: Uri.parse('http://localhost:3000/mcp'),
        );
        expect(t.url.path, '/sse');
        expect(t.postUrl.path, '/mcp');
      });

      test('SseClientTransport defaults postUrl to url when omitted', () {
        final t = SseClientTransport(
          url: Uri.parse('http://localhost:3000/mcp'),
        );
        expect(t.url, t.postUrl);
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
  });
}
