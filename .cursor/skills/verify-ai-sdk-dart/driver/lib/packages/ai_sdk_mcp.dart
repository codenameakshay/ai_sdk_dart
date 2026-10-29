// Verification checks for package:ai_sdk_mcp. See features/ai_sdk_mcp.md.
//
// HTTP checks run MCPClient against an in-process JSON-RPC fixture server.
// Stdio checks run it against the pinned TypeScript SDK reference server in
// examples/mcp_reference/js. Every check asserts the request that reached the
// server and the value the caller observed.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_mcp/ai_sdk_mcp.dart';
import 'package:ai_sdk_openai_compatible/ai_sdk_openai_compatible.dart';
import 'package:dio/dio.dart';

import '../harness.dart';

const _package = 'ai_sdk_mcp';

// ---------------------------------------------------------------------------
// JSON-RPC fixture helpers
// ---------------------------------------------------------------------------

FixtureResponse _reply(
  Object? id,
  Object? result, {
  Map<String, String> headers = const {},
}) => FixtureResponse.json({
  'jsonrpc': '2.0',
  'id': id,
  'result': result,
}, headers: headers);

FixtureResponse _rpcError(Object? id, int code, String message) =>
    FixtureResponse.json({
      'jsonrpc': '2.0',
      'id': id,
      'error': {'code': code, 'message': message},
    });

Map<String, Object?> _text(String text) => {'type': 'text', 'text': text};

Map<String, Object?> _toolDescriptor(String name, {String? description}) => {
  'name': name,
  'description': description ?? 'The $name tool.',
  'inputSchema': {
    'type': 'object',
    'properties': {
      'text': {'type': 'string'},
    },
    'required': ['text'],
  },
};

typedef _Override =
    FixtureResponse? Function(FixtureRequest request, Map<String, dynamic> rpc);

/// A minimal MCP server over Streamable HTTP. [override] sees every JSON-RPC
/// request (not notifications) first and may answer it.
FixtureHandler _mcpHandler({
  String protocolVersion = '2025-06-18',
  String? sessionId = 'sess-1',
  bool modern = false,
  _Override? override,
  FixtureResponse Function(FixtureRequest request)? onGet,
}) {
  Map<String, Object?> done(Map<String, Object?> result) =>
      modern ? {'resultType': 'complete', ...result} : result;
  return (request) {
    if (request.method == 'GET') {
      return onGet?.call(request) ?? FixtureResponse.text('', status: 405);
    }
    if (request.method == 'DELETE') {
      return FixtureResponse.text('', status: 204);
    }
    final rpc = request.jsonObject;
    final id = rpc['id'];
    if (id == null) return FixtureResponse.text('', status: 202);
    final custom = override?.call(request, rpc);
    if (custom != null) return custom;
    final params = (rpc['params'] as Map?)?.cast<String, dynamic>() ?? {};
    switch (rpc['method']) {
      case 'initialize':
        return _reply(
          id,
          {
            'protocolVersion': protocolVersion,
            'capabilities': {'tools': <String, Object?>{}},
            'serverInfo': {'name': 'verify-mcp', 'version': '1.0.0'},
          },
          headers: {'Mcp-Session-Id': ?sessionId},
        );
      case 'server/discover':
        return _reply(id, {
          'supportedVersions': [MCPClient.modernProtocolVersion],
          'serverInfo': {'name': 'verify-mcp', 'version': '1.0.0'},
        });
      case 'tools/list':
        return _reply(
          id,
          done({
            'tools': [
              _toolDescriptor(
                'echo',
                description: 'Return the given text prefixed with echo:.',
              ),
            ],
          }),
        );
      case 'tools/call':
        final args = (params['arguments'] as Map?) ?? {};
        return _reply(
          id,
          done({
            'content': [_text('echo:${args['text'] ?? ''}')],
          }),
        );
    }
    return _rpcError(id, -32601, 'Method not found: ${rpc['method']}');
  };
}

Future<void> _until(
  bool Function() condition,
  String what, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw CheckFailure('timed out waiting for $what');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// JSON-RPC methods of the POST requests [server] received, in order.
List<String> _postMethods(List<FixtureRequest> requests) => [
  for (final r in requests)
    if (r.method == 'POST') '${r.jsonObject['method']}',
];

List<FixtureRequest> _rpcCalls(List<FixtureRequest> requests, String method) =>
    [
      for (final r in requests)
        if (r.method == 'POST' && r.jsonObject['method'] == method) r,
    ];

MCPClient _httpClient(
  CheckContext ctx,
  FixtureServer server, {
  MCPProtocolMode mode = MCPProtocolMode.legacy,
  Map<String, String>? headers,
  Duration listenerReconnectDelay = const Duration(milliseconds: 250),
  MCPAuthConfiguration? auth,
  MCPReconnectPolicy? reconnectPolicy,
  String path = '/mcp',
}) => _clientFor(
  ctx,
  server.url(path),
  mode: mode,
  headers: headers,
  listenerReconnectDelay: listenerReconnectDelay,
  auth: auth,
  reconnectPolicy: reconnectPolicy,
);

MCPClient _clientFor(
  CheckContext ctx,
  String url, {
  MCPProtocolMode mode = MCPProtocolMode.legacy,
  Map<String, String>? headers,
  Duration listenerReconnectDelay = const Duration(milliseconds: 250),
  MCPAuthConfiguration? auth,
  MCPReconnectPolicy? reconnectPolicy,
}) {
  StreamableHttpClientTransport transport() => StreamableHttpClientTransport(
    url: Uri.parse(url),
    headers: headers,
    requestTimeout: const Duration(seconds: 5),
    listenerReconnectDelay: listenerReconnectDelay,
    auth: auth,
  );
  final client = MCPClient(
    transport: transport(),
    protocolMode: mode,
    reconnectPolicy: reconnectPolicy,
    transportFactory: reconnectPolicy == null ? null : transport,
  );
  ctx.onCleanup(client.close);
  return client;
}

/// Like [FixtureServer] but a handler may return null to drop the connection
/// without answering, which is how a lost response looks to the client.
class _DroppingServer {
  _DroppingServer._(this._server);

  final HttpServer _server;
  final List<FixtureRequest> requests = [];

  static Future<_DroppingServer> start(
    CheckContext ctx,
    FutureOr<FixtureResponse?> Function(FixtureRequest request) handler,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final self = _DroppingServer._(server);
    ctx.onCleanup(() => server.close(force: true));
    server.listen((request) async {
      final body = await request.fold<List<int>>([], (a, b) => a..addAll(b));
      final headers = <String, String>{};
      request.headers.forEach((n, v) => headers[n] = v.join(', '));
      final fixtureRequest = FixtureRequest(
        index: self.requests.length,
        method: request.method,
        uri: request.uri,
        headers: headers,
        bodyBytes: body,
      );
      self.requests.add(fixtureRequest);
      final exchange = Exchange(
        source: 'fixture',
        method: request.method,
        url: request.uri.path,
        requestHeaders: redactHeaders(headers),
        requestBody: fixtureRequest.json,
      );
      ctx.exchanges.add(exchange);
      final reply = await handler(fixtureRequest);
      if (reply == null) {
        exchange.error = 'connection dropped before any response';
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.destroy();
        return;
      }
      request.response.statusCode = reply.status;
      reply.headers.forEach(request.response.headers.set);
      final sent = <int>[];
      for (final chunk in reply.chunks) {
        request.response.add(chunk);
        sent.addAll(chunk);
      }
      exchange
        ..status = reply.status
        ..responseContentType = reply.headers['content-type']
        ..responseBody = utf8.decode(sent, allowMalformed: true);
      await request.response.close();
    });
    return self;
  }

  String url(String path) => 'http://127.0.0.1:${_server.port}$path';
}

// ---------------------------------------------------------------------------
// Stdio helpers: run the pinned TypeScript SDK server and tap its frames.
// ---------------------------------------------------------------------------

class _FrameLog {
  final frames = <Map<String, Object?>>[];
  final _pending = {'->': <int>[], '<-': <int>[]};

  void add(String direction, List<int> chunk) {
    final bytes = _pending[direction]!..addAll(chunk);
    int newline;
    while ((newline = bytes.indexOf(0x0a)) >= 0) {
      final line = utf8.decode(bytes.sublist(0, newline));
      bytes.removeRange(0, newline + 1);
      if (line.trim().isEmpty) continue;
      try {
        frames.add({'dir': direction, 'msg': jsonDecode(line)});
      } on FormatException {
        frames.add({'dir': direction, 'raw': line});
      }
    }
  }

  /// Messages sent in [direction] (`->` client to server, `<-` back).
  List<Map<String, dynamic>> sent(String direction, {String? method}) => [
    for (final f in frames)
      if (f['dir'] == direction &&
          f['msg'] is Map &&
          (method == null || (f['msg'] as Map)['method'] == method))
        (f['msg'] as Map).cast<String, dynamic>(),
  ];
}

class _TapConsumer implements StreamConsumer<List<int>> {
  _TapConsumer(this._inner, this._log);
  final IOSink _inner;
  final _FrameLog _log;

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      _log.add('->', chunk);
      _inner.add(chunk);
    }
    await _inner.flush();
  }

  @override
  Future<void> close() => _inner.close();
}

class _TapProcess implements Process {
  _TapProcess(this._inner, _FrameLog log)
    : stdin = IOSink(_TapConsumer(_inner.stdin, log)),
      stdout = _inner.stdout.map((chunk) {
        log.add('<-', chunk);
        return chunk;
      });

  final Process _inner;

  @override
  final IOSink stdin;
  @override
  final Stream<List<int>> stdout;
  @override
  Stream<List<int>> get stderr => _inner.stderr;
  @override
  Future<int> get exitCode => _inner.exitCode;
  @override
  int get pid => _inner.pid;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) =>
      _inner.kill(signal);
}

class _Stdio {
  _Stdio(this.transport, this.log, this._process);
  final StdioMCPTransport transport;
  final _FrameLog log;
  final List<Process> _process;
  Process get process => _process.single;
}

_Stdio _referenceServer(CheckContext ctx) {
  final script = '${ctx.repoRoot}/examples/mcp_reference/js/server.mjs';
  if (!Directory(
    '${ctx.repoRoot}/examples/mcp_reference/js/node_modules/@modelcontextprotocol',
  ).existsSync()) {
    ctx.skip(
      'pinned TypeScript SDK is not installed '
      '(run make test-mcp-reference or npm ci in examples/mcp_reference/js)',
    );
  }
  final log = _FrameLog();
  final started = <Process>[];
  final transport = StdioMCPTransport(
    command: 'node',
    args: [script],
    processStarter: (command, args) async {
      final process = await Process.start(command, args);
      started.add(process);
      ctx.onCleanup(() async => process.kill());
      return _TapProcess(process, log);
    },
  );
  return _Stdio(transport, log, started);
}

// ---------------------------------------------------------------------------
// Chat model for the generateText check
// ---------------------------------------------------------------------------

OpenAICompatibleChatLanguageModel _chatModel(
  CheckContext ctx,
  FixtureServer server,
) {
  final baseUrl = server.url('/v1');
  final dio = Dio(BaseOptions(baseUrl: baseUrl));
  ctx.onCleanup(() async => dio.close(force: true));
  return OpenAICompatibleChatLanguageModel(
    modelId: 'verify-model',
    config: OpenAICompatibleConfig(
      provider: 'verify-compat',
      baseUrl: baseUrl,
      client: dio,
      headers: () => {'Authorization': 'Bearer verify-key'},
    ),
  );
}

Map<String, Object?> _completion({
  String? content,
  List<Map<String, Object?>>? toolCalls,
  String finishReason = 'stop',
}) => {
  'id': 'chatcmpl-verify',
  'object': 'chat.completion',
  'created': 1767225600,
  'model': 'verify-model',
  'choices': [
    {
      'index': 0,
      'message': {
        'role': 'assistant',
        'content': content,
        'tool_calls': ?toolCalls,
      },
      'finish_reason': finishReason,
    },
  ],
  'usage': {'prompt_tokens': 11, 'completion_tokens': 7, 'total_tokens': 18},
};

// ---------------------------------------------------------------------------
// Checks
// ---------------------------------------------------------------------------

final checks = PackageChecks(_package, [
  // ----- handshake and protocol modes -----
  Check(
    id: 'http-legacy-handshake',
    feature: 'mcp-handshake',
    description:
        'Legacy initialize over Streamable HTTP sends protocol 2025-06-18, then '
        'notifications/initialized, reuses Mcp-Session-Id and MCP-Protocol-Version, '
        'opens the GET listener and sends DELETE on close.',
    run: (ctx) async {
      final server = await ctx.server(
        _mcpHandler(onGet: (_) => FixtureResponse.sse(const [], status: 200)),
      );
      final client = _httpClient(ctx, server, headers: {'X-Tenant-Id': 'acme'});
      await client.initialize();
      await client.initialize(); // idempotent: must not re-handshake
      final tools = await client.tools();
      await _until(
        () => server.requests.any((r) => r.method == 'GET'),
        'the GET listener',
      );
      await client.close();
      ctx.observe('toolNames', tools.keys.toList());
      final reqs = server.requests;
      ctx.observe('requests', [for (final r in reqs) '${r.method} ${r.path}']);

      final initialize = _rpcCalls(reqs, 'initialize');
      ctx.expectEquals(initialize.length, 1, 'initialize count');
      final first = initialize.single;
      final params = first.jsonObject['params'] as Map;
      ctx.expectEquals(
        params['protocolVersion'],
        '2025-06-18',
        'client version',
      );
      ctx.expectEquals(
        (params['clientInfo'] as Map)['name'],
        'ai_sdk_dart',
        'clientInfo.name',
      );
      ctx.expect(
        !first.headers.containsKey('mcp-session-id') &&
            !first.headers.containsKey('mcp-protocol-version'),
        'initialize must not carry a session id or version header',
      );
      ctx.expect(
        first.headers['accept']!.contains('application/json') &&
            first.headers['accept']!.contains('text/event-stream'),
        'initialize Accept header: ${first.headers['accept']}',
      );
      ctx.expectEquals(first.headers['x-tenant-id'], 'acme', 'custom header');

      final initialized = _rpcCalls(reqs, 'notifications/initialized');
      ctx.expectEquals(initialized.length, 1, 'initialized notification');
      ctx.expect(
        initialized.single.jsonObject['id'] == null,
        'notification must not carry an id',
      );
      for (final r in [
        initialized.single,
        _rpcCalls(reqs, 'tools/list').single,
      ]) {
        ctx.expectEquals(r.headers['mcp-session-id'], 'sess-1', 'session id');
        ctx.expectEquals(
          r.headers['mcp-protocol-version'],
          '2025-06-18',
          'protocol header',
        );
        ctx.expectEquals(r.headers['x-tenant-id'], 'acme', 'custom header');
      }
      final get = reqs.firstWhere((r) => r.method == 'GET');
      ctx.expect(
        get.headers['accept']!.contains('text/event-stream'),
        'GET Accept header',
      );
      ctx.expectEquals(get.headers['mcp-session-id'], 'sess-1', 'GET session');
      final delete = ctx.singleRequest(server, '/mcp', method: 'DELETE');
      ctx.expectEquals(
        delete.headers['mcp-session-id'],
        'sess-1',
        'DELETE session',
      );
      ctx.expectEquals(tools.keys.toList(), ['echo'], 'discovered tools');
    },
  ),
  Check(
    id: 'protocol-negotiation',
    feature: 'mcp-protocol-modes',
    description:
        'A server that negotiates another protocol version fails initialize '
        'with a clear MCPException in both modes, and a later initialize can still succeed.',
    run: (ctx) async {
      var stale = true;
      final legacyServer = await ctx.server(
        _mcpHandler(
          override: (_, rpc) => stale && rpc['method'] == 'initialize'
              ? _reply(rpc['id'], {
                  'protocolVersion': '2024-11-05',
                  'capabilities': <String, Object?>{},
                  'serverInfo': {'name': 'old', 'version': '0.1'},
                })
              : null,
        ),
      );
      final legacy = _httpClient(ctx, legacyServer);
      final legacyError = await ctx.expectThrows<MCPException>(
        legacy.initialize,
        'legacy mismatch',
      );
      ctx.expect(
        legacyError.message.contains(
          'Unsupported protocolVersion "2024-11-05"',
        ),
        'legacy error message: ${legacyError.message}',
      );
      ctx.expectEquals(
        _postMethods(legacyServer.requests),
        ['initialize'],
        'no notification after a failed handshake',
      );
      stale = false;
      await legacy.initialize();
      ctx.expectEquals(
        _postMethods(
          legacyServer.requests,
        ).where((m) => m == 'initialize').length,
        2,
        'initialize retried',
      );
      ctx.expect(
        _postMethods(
          legacyServer.requests,
        ).contains('notifications/initialized'),
        'recovered handshake must send notifications/initialized',
      );

      final modernServer = await ctx.server(
        _mcpHandler(
          modern: true,
          override: (_, rpc) => rpc['method'] == 'server/discover'
              ? _reply(rpc['id'], {
                  'supportedVersions': ['2025-01-01'],
                })
              : null,
        ),
      );
      final modern = _httpClient(
        ctx,
        modernServer,
        mode: MCPProtocolMode.modern,
      );
      final modernError = await ctx.expectThrows<MCPException>(
        modern.initialize,
        'modern mismatch',
      );
      ctx.expect(
        modernError.message.contains('does not support 2026-07-28'),
        'modern error message: ${modernError.message}',
      );
      ctx.expectEquals(
        MCPClient.legacyProtocolVersion,
        '2025-06-18',
        'legacy constant',
      );
      ctx.expectEquals(
        MCPClient.modernProtocolVersion,
        '2026-07-28',
        'modern constant',
      );
    },
  ),
  Check(
    id: 'modern-mode-http',
    feature: 'mcp-protocol-modes',
    description:
        'Modern mode probes server/discover, adds _meta protocol metadata and '
        'Mcp-Method/Mcp-Name routing headers, uses no session, and rejects results without resultType.',
    run: (ctx) async {
      final server = await ctx.server(
        _mcpHandler(
          modern: true,
          sessionId: null,
          override: (_, rpc) {
            final params = (rpc['params'] as Map?) ?? {};
            if (rpc['method'] == 'tools/call' && params['name'] == 'bad') {
              return _reply(rpc['id'], {
                'content': [_text('no resultType here')],
              });
            }
            return null;
          },
        ),
      );
      final client = _httpClient(ctx, server, mode: MCPProtocolMode.modern);
      await client.initialize();
      final tools = await client.tools();
      final echoed = await client.callTool('echo', {'text': 'modern'});
      final error = await ctx.expectThrows<MCPException>(
        () => client.callTool('bad', {'text': 'x'}),
        'missing resultType',
      );
      await client.close();
      ctx.observe('echoed', echoed);
      ctx.observe('requests', [
        for (final r in server.requests) '${r.method} ${r.path}',
      ]);

      final reqs = server.requests;
      final methods = _postMethods(reqs);
      ctx.expectEquals(
        methods,
        ['server/discover', 'tools/list', 'tools/call', 'tools/call'],
        'modern request sequence (no initialize, no initialized notification)',
      );
      ctx.expect(
        reqs.every((r) => r.method == 'POST'),
        'modern mode must not use GET or DELETE: '
        '${reqs.map((r) => r.method).toList()}',
      );
      final discover = reqs.first;
      final meta = (discover.jsonObject['params'] as Map)['_meta'] as Map;
      ctx.expectEquals(
        meta['io.modelcontextprotocol/protocolVersion'],
        '2026-07-28',
        '_meta protocolVersion',
      );
      ctx.expectEquals(
        (meta['io.modelcontextprotocol/clientInfo'] as Map)['name'],
        'ai_sdk_dart',
        '_meta clientInfo',
      );
      for (final r in reqs) {
        ctx.expectEquals(
          r.headers['mcp-protocol-version'],
          '2026-07-28',
          'protocol header on ${r.jsonObject['method']}',
        );
        ctx.expectEquals(
          r.headers['mcp-method'],
          r.jsonObject['method'],
          'Mcp-Method',
        );
        ctx.expect(
          !r.headers.containsKey('mcp-session-id'),
          'modern mode sent a session id',
        );
      }
      final call = _rpcCalls(reqs, 'tools/call').first;
      ctx.expectEquals(call.headers['mcp-name'], 'echo', 'Mcp-Name');
      final callParams = call.jsonObject['params'] as Map;
      ctx.expectEquals(callParams['name'], 'echo', 'tool name');
      ctx.expectEquals(
        (callParams['arguments'] as Map)['text'],
        'modern',
        'args',
      );
      ctx.expect(
        (callParams['_meta'] as Map).containsKey(
          'io.modelcontextprotocol/protocolVersion',
        ),
        'tools/call must carry _meta protocol metadata',
      );
      ctx.expectEquals(tools.keys.toList(), ['echo'], 'tools');
      ctx.expectEquals(echoed, 'echo:modern', 'tool result');
      ctx.expect(
        error.message.contains('resultType'),
        'missing resultType message: ${error.message}',
      );
    },
  ),
  Check(
    id: 'modern-input-required',
    feature: 'mcp-protocol-modes',
    description:
        'A modern tools/call that needs more input returns MCPInputRequiredResult; '
        'passing requestState and inputResponses back completes the call.',
    run: (ctx) async {
      final server = await ctx.server(
        _mcpHandler(
          modern: true,
          sessionId: null,
          override: (_, rpc) {
            if (rpc['method'] != 'tools/call') return null;
            final params = (rpc['params'] as Map).cast<String, dynamic>();
            if (params['requestState'] == null) {
              return _reply(rpc['id'], {
                'resultType': 'input_required',
                'inputRequests': {
                  'confirm': {
                    'method': 'elicitation/create',
                    'params': {'message': 'Confirm this action'},
                  },
                },
                'requestState': 'state-1',
              });
            }
            final answer =
                ((params['inputResponses'] as Map)['confirm'] as Map)['action'];
            return _reply(rpc['id'], {
              'resultType': 'complete',
              'content': [_text('confirmed:$answer')],
            });
          },
        ),
      );
      final client = _httpClient(ctx, server, mode: MCPProtocolMode.modern);
      final first = await client.callTool('delete_all', <String, dynamic>{});
      ctx.expect(
        first is MCPInputRequiredResult,
        'first call returned ${first.runtimeType}',
      );
      final pending = first as MCPInputRequiredResult;
      ctx.observe('inputRequests', pending.inputRequests);
      ctx.observe('requestState', pending.requestState);
      final second = await client.callTool(
        'delete_all',
        <String, dynamic>{},
        requestState: pending.requestState,
        inputResponses: {
          'confirm': {'action': 'accept'},
        },
      );
      ctx.observe('second', second);
      final calls = _rpcCalls(server.requests, 'tools/call');
      ctx.expectEquals(calls.length, 2, 'tools/call count');
      final retryParams = calls[1].jsonObject['params'] as Map;
      ctx.expectEquals(retryParams['requestState'], 'state-1', 'requestState');
      ctx.expectEquals(retryParams['inputResponses'], {
        'confirm': {'action': 'accept'},
      }, 'inputResponses');
      ctx.expectEquals(
        (calls[0].jsonObject['params'] as Map).containsKey('requestState'),
        false,
        'first call carries no requestState',
      );
      ctx.expectEquals(pending.requestState, 'state-1', 'returned state');
      ctx.expectEquals(pending.inputRequests.keys.toList(), [
        'confirm',
      ], 'input request ids');
      ctx.expectEquals(second, 'confirmed:accept', 'completed result');
    },
  ),
  // ----- tools -----
  Check(
    id: 'tools-pagination',
    feature: 'mcp-tool-discovery',
    description:
        'tools() follows nextCursor across pages and returns every tool; a '
        'repeated cursor is rejected instead of looping forever.',
    run: (ctx) async {
      final server = await ctx.server(
        _mcpHandler(
          override: (_, rpc) {
            if (rpc['method'] != 'tools/list') return null;
            final cursor = ((rpc['params'] as Map?) ?? {})['cursor'];
            return switch (cursor) {
              null => _reply(rpc['id'], {
                'tools': [_toolDescriptor('alpha')],
                'nextCursor': 'c1',
              }),
              'c1' => _reply(rpc['id'], {
                'tools': [_toolDescriptor('beta')],
                'nextCursor': 'c2',
              }),
              _ => _reply(rpc['id'], {
                'tools': [_toolDescriptor('gamma')],
              }),
            };
          },
        ),
      );
      final client = _httpClient(ctx, server);
      final tools = await client.tools();
      final cursors = [
        for (final r in _rpcCalls(server.requests, 'tools/list'))
          ((r.jsonObject['params'] as Map?) ?? {})['cursor'],
      ];
      ctx.observe('toolNames', tools.keys.toList());
      ctx.observe('cursors', cursors);
      ctx.expectEquals(tools.keys.toList(), [
        'alpha',
        'beta',
        'gamma',
      ], 'tools');
      ctx.expectEquals(cursors, [null, 'c1', 'c2'], 'cursor sequence');
      ctx.expectEquals(
        tools['alpha']!.description,
        'The alpha tool.',
        'tool description',
      );

      final loopServer = await ctx.server(
        _mcpHandler(
          override: (_, rpc) => rpc['method'] == 'tools/list'
              ? _reply(rpc['id'], {
                  'tools': [_toolDescriptor('loop')],
                  'nextCursor': 'same',
                })
              : null,
        ),
      );
      final looping = _httpClient(ctx, loopServer);
      final error = await ctx.expectThrows<MCPException>(
        looping.tools,
        'repeated cursor',
      );
      ctx.expect(
        error.message.contains('repeated cursor'),
        'repeated cursor message: ${error.message}',
      );
    },
  ),
  Check(
    id: 'tool-results',
    feature: 'mcp-tool-calls',
    description:
        'callTool joins text parts, keeps non-text content, returns a '
        'structured-only result, and throws MCPException for isError results and JSON-RPC errors.',
    run: (ctx) async {
      final server = await ctx.server(
        _mcpHandler(
          override: (_, rpc) {
            if (rpc['method'] != 'tools/call') return null;
            final name = (rpc['params'] as Map)['name'];
            final id = rpc['id'];
            return switch (name) {
              'two_parts' => _reply(id, {
                'content': [_text('line one'), _text('line two')],
              }),
              'mixed' => _reply(id, {
                'content': [
                  _text('caption'),
                  {'type': 'image', 'data': 'AQID', 'mimeType': 'image/png'},
                ],
              }),
              'structured' => _reply(id, {
                'content': <Object?>[],
                'structuredContent': {'temperature': 18, 'unit': 'C'},
              }),
              'tool_failure' => _reply(id, {
                'content': [_text('disk is full')],
                'isError': true,
              }),
              'rpc_failure' => _rpcError(id, -32602, 'bad arguments'),
              _ => null,
            };
          },
        ),
      );
      final client = _httpClient(ctx, server);
      final joined = await client.callTool('two_parts', {'text': 'x'});
      final mixed = await client.callTool('mixed', {'text': 'x'});
      final structured = await client.callTool('structured', {'text': 'x'});
      final toolFailure = await ctx.expectThrows<MCPException>(
        () => client.callTool('tool_failure', {'text': 'x'}),
        'isError result',
      );
      final rpcFailure = await ctx.expectThrows<MCPException>(
        () => client.callTool('rpc_failure', {'text': 'x'}),
        'JSON-RPC error',
      );
      ctx.observe('joined', joined);
      ctx.observe('mixed', mixed);
      ctx.observe('structured', structured);
      ctx.expectEquals(joined, 'line one\nline two', 'text parts joined');
      ctx.expect(
        mixed is List && mixed.length == 2,
        'mixed content kept as list',
      );
      ctx.expectEquals((mixed as List)[1], {
        'type': 'image',
        'data': 'AQID',
        'mimeType': 'image/png',
      }, 'image part preserved');
      ctx.expect(
        structured is Map &&
            (structured['structuredContent'] as Map)['temperature'] == 18,
        'structured-only result must expose structuredContent: $structured',
      );
      ctx.expect(
        toolFailure.message.contains('disk is full'),
        'isError message: ${toolFailure.message}',
      );
      ctx.expect(
        rpcFailure.message.contains('bad arguments') &&
            rpcFailure.message.contains('rpc_failure'),
        'JSON-RPC error message: ${rpcFailure.message}',
      );
      final call = _rpcCalls(server.requests, 'tools/call').first;
      ctx.expectEquals((call.jsonObject['params'] as Map)['arguments'], {
        'text': 'x',
      }, 'arguments sent');
    },
  ),
  Check(
    id: 'generate-text-mcp-tools',
    feature: 'mcp-generate-text',
    description:
        'The ToolSet from tools() works in generateText: the model asks for the '
        'MCP tool, the MCP server receives tools/call, and its result goes back to the model.',
    run: (ctx) async {
      final mcpServer = await ctx.server(
        _mcpHandler(onGet: (_) => FixtureResponse.sse(const [], status: 200)),
      );
      final chat = await ctx.server((request) {
        if (request.index == 0) {
          return FixtureResponse.json(
            _completion(
              finishReason: 'tool_calls',
              toolCalls: [
                {
                  'id': 'call_mcp_1',
                  'type': 'function',
                  'function': {
                    'name': 'echo',
                    'arguments': '{"text":"hello mcp"}',
                  },
                },
              ],
            ),
          );
        }
        return FixtureResponse.json(
          _completion(content: 'The tool said echo:hello mcp.'),
        );
      });
      final client = _httpClient(ctx, mcpServer);
      final tools = await client.tools();
      final result = await generateText(
        model: _chatModel(ctx, chat),
        prompt: 'Echo "hello mcp".',
        tools: tools,
        maxSteps: 3,
      );
      ctx.observe('text', result.text);
      ctx.observe('steps', result.steps.length);

      final chatRequests = ctx.requestsTo(chat, '/v1/chat/completions');
      ctx.expectEquals(chatRequests.length, 2, 'chat request count');
      final advertised =
          ((chatRequests[0].jsonObject['tools'] as List).single
                  as Map)['function']
              as Map;
      ctx.observe('advertisedTool', advertised);
      ctx.expectEquals(advertised['name'], 'echo', 'tool sent to the model');
      ctx.expectEquals(
        advertised['description'],
        'Return the given text prefixed with echo:.',
        'MCP description forwarded to the model',
      );
      final call = _rpcCalls(mcpServer.requests, 'tools/call').single;
      final callParams = call.jsonObject['params'] as Map;
      ctx.expectEquals(callParams['name'], 'echo', 'MCP tools/call name');
      ctx.expectEquals(callParams['arguments'], {
        'text': 'hello mcp',
      }, 'MCP tools/call arguments');
      final followUp = (chatRequests[1].jsonObject['messages'] as List)
          .cast<Map>();
      final toolMessage = followUp.lastWhere((m) => m['role'] == 'tool');
      ctx.expectEquals(
        toolMessage['tool_call_id'],
        'call_mcp_1',
        'tool_call_id',
      );
      ctx.expect(
        '${toolMessage['content']}'.contains('echo:hello mcp'),
        'MCP result missing from the follow-up: ${toolMessage['content']}',
      );
      ctx.expectEquals(
        result.text,
        'The tool said echo:hello mcp.',
        'final text',
      );
      ctx.note(
        'tools() builds each tool with dynamicTool, so the model receives the '
        'description but the MCP inputSchema is not forwarded '
        '(parameters: ${advertised['parameters']}).',
      );
    },
  ),
  // ----- transport behavior -----
  Check(
    id: 'sse-response-progress',
    feature: 'mcp-http-responses',
    description:
        'The HTTP transport reads both JSON and text/event-stream replies; '
        'progress notifications sent ahead of the SSE reply reach client.progress.',
    run: (ctx) async {
      final server = await ctx.server(
        _mcpHandler(
          override: (_, rpc) {
            if (rpc['method'] != 'tools/call') return null;
            final params = (rpc['params'] as Map).cast<String, dynamic>();
            final token = (params['_meta'] as Map?)?['progressToken'];
            return FixtureResponse.sse([
              SseEvent({
                'jsonrpc': '2.0',
                'method': 'notifications/progress',
                'params': {
                  'progressToken': token,
                  'progress': 1,
                  'total': 2,
                  'message': 'halfway',
                },
              }),
              SseEvent({
                'jsonrpc': '2.0',
                'method': 'notifications/progress',
                'params': {'progressToken': token, 'progress': 2, 'total': 2},
              }),
              SseEvent({
                'jsonrpc': '2.0',
                'id': rpc['id'],
                'result': {
                  'content': [_text('streamed:done')],
                },
              }),
            ]);
          },
        ),
      );
      final client = _httpClient(ctx, server);
      final updates = <MCPProgressUpdate>[];
      final subscription = client.progress.listen(updates.add);
      ctx.onCleanup(subscription.cancel);
      final tools = await client.tools(); // JSON reply
      final result = await client.callTool('long_task', {
        'text': 'go',
      }, progressToken: 'task-1'); // SSE reply
      await _until(() => updates.length >= 2, 'progress updates');
      ctx.observe('result', result);
      ctx.observe('progress', [
        for (final u in updates)
          {
            'token': u.progressToken,
            'progress': u.progress,
            'total': u.total,
            'message': u.message,
          },
      ]);
      String? contentTypeOf(String method) => [
        for (final e in ctx.exchanges)
          if ((e.requestBody as Map?)?['method'] == method)
            e.responseContentType,
      ].single;
      ctx.expectEquals(
        contentTypeOf('tools/list'),
        'application/json',
        'JSON reply',
      );
      ctx.expectEquals(
        contentTypeOf('tools/call'),
        'text/event-stream',
        'SSE reply',
      );
      ctx.expectEquals(tools.keys.toList(), ['echo'], 'tools from JSON');
      ctx.expectEquals(result, 'streamed:done', 'result from SSE');
      final call = _rpcCalls(server.requests, 'tools/call').single;
      ctx.expectEquals(
        ((call.jsonObject['params'] as Map)['_meta'] as Map)['progressToken'],
        'task-1',
        'progressToken on the wire',
      );
      ctx.expectEquals(updates.map((u) => u.progress).toList(), [
        1,
        2,
      ], 'progress');
      ctx.expectEquals(updates.first.total, 2, 'progress total');
      ctx.expectEquals(updates.first.message, 'halfway', 'progress message');
      ctx.expectEquals(updates.first.progressToken, 'task-1', 'progress token');
    },
  ),
  Check(
    id: 'session-expiry-recovery',
    feature: 'mcp-http-session',
    description:
        'When the server answers 404 to a request that carries Mcp-Session-Id, the '
        'client starts a new session with a fresh initialize and replays the request.',
    run: (ctx) async {
      var sessions = 0;
      var expireFirst = false;
      final server = await ctx.server(
        _mcpHandler(
          override: (request, rpc) {
            if (rpc['method'] == 'initialize') {
              sessions++;
              return _reply(
                rpc['id'],
                {
                  'protocolVersion': '2025-06-18',
                  'capabilities': <String, Object?>{},
                  'serverInfo': {'name': 'verify-mcp', 'version': '1.0.0'},
                },
                headers: {'Mcp-Session-Id': 'sess-$sessions'},
              );
            }
            if (expireFirst && request.headers['mcp-session-id'] == 'sess-1') {
              return FixtureResponse.text('session gone', status: 404);
            }
            return null;
          },
        ),
      );
      final client = _httpClient(ctx, server);
      await client.initialize();
      expireFirst = true;
      final result = await client.callTool('echo', {'text': 'after expiry'});
      ctx.observe('result', result);
      final posts = [
        for (final r in server.requests)
          if (r.method == 'POST')
            '${r.jsonObject['method']}@${r.headers['mcp-session-id'] ?? '-'}',
      ];
      ctx.observe('posts', posts);
      ctx.expectEquals(posts, [
        'initialize@-',
        'notifications/initialized@sess-1',
        'tools/call@sess-1',
        'initialize@-',
        'notifications/initialized@sess-2',
        'tools/call@sess-2',
      ], 'request sequence across the expired session');
      ctx.expectEquals(result, 'echo:after expiry', 'replayed result');
    },
  ),
  Check(
    id: 'ambiguous-tool-completion',
    feature: 'mcp-failure-handling',
    description:
        'A tools/call whose response is lost raises MCPAmbiguousToolCompletionException '
        'and is sent once; HTTP 408 is ambiguous too, a 400 rejection stays a plain MCPTransportException.',
    run: (ctx) async {
      final server = await _DroppingServer.start(ctx, (request) {
        final base = _mcpHandler();
        if (request.method == 'POST' &&
            request.jsonObject['method'] == 'tools/call') {
          final name = (request.jsonObject['params'] as Map)['name'];
          switch (name) {
            case 'lost':
              return null;
            case 'timeout':
              return FixtureResponse.text('', status: 408);
            case 'reject':
              return FixtureResponse.text('nope', status: 400);
          }
        }
        return base(request) as FixtureResponse;
      });
      final client = _clientFor(ctx, server.url('/mcp'));
      final lost = await ctx.expectThrows<MCPAmbiguousToolCompletionException>(
        () => client.callTool('lost', {'text': 'charge card'}),
        'lost response',
      );
      final timeout = await ctx
          .expectThrows<MCPAmbiguousToolCompletionException>(
            () => client.callTool('timeout', {'text': 'x'}),
            'HTTP 408',
          );
      final reject = await ctx.expectThrows<MCPTransportException>(
        () => client.callTool('reject', {'text': 'x'}),
        'HTTP 400',
      );
      ctx.observe('lost', {
        'toolName': lost.toolName,
        'requestId': lost.requestId,
        'cause': '${lost.cause.runtimeType}',
        'message': lost.message,
      });
      ctx.observe('rejectStatus', reject.statusCode);
      final lostCalls = [
        for (final r in _rpcCalls(server.requests, 'tools/call'))
          if ((r.jsonObject['params'] as Map)['name'] == 'lost') r,
      ];
      ctx.expectEquals(
        lostCalls.length,
        1,
        'lost tools/call is never replayed',
      );
      ctx.expectEquals(lost.toolName, 'lost', 'toolName');
      ctx.expectEquals(
        lost.requestId,
        lostCalls.single.jsonObject['id'],
        'requestId matches the wire id',
      );
      ctx.expect(
        lost.cause is MCPTransportException,
        'cause is a transport error',
      );
      ctx.expectEquals(timeout.toolName, 'timeout', '408 toolName');
      ctx.expectEquals(
        (timeout.cause as MCPTransportException).statusCode,
        408,
        '408 cause',
      );
      ctx.expectEquals(reject.statusCode, 400, '400 statusCode');
      ctx.expect(
        reject is! MCPAmbiguousToolCompletionException,
        'a definite 400 rejection must not be reported as ambiguous',
      );
    },
  ),
  Check(
    id: 'retry-on-transport-failure',
    feature: 'mcp-failure-handling',
    description:
        'retryOnTransportFailure with an MCPReconnectPolicy replays a tools/call '
        'after a lost response; without a policy the opt-in alone still ends ambiguous.',
    run: (ctx) async {
      var dropNext = true;
      final server = await _DroppingServer.start(ctx, (request) {
        if (dropNext &&
            request.method == 'POST' &&
            request.jsonObject['method'] == 'tools/call') {
          dropNext = false;
          return null;
        }
        return _mcpHandler()(request) as FixtureResponse;
      });
      final client = _clientFor(
        ctx,
        server.url('/mcp'),
        reconnectPolicy: const MCPReconnectPolicy(
          maxAttempts: 2,
          initialDelayMs: 10,
          maxDelayMs: 20,
        ),
      );
      final recovered = await client.callTool('echo', {
        'text': 'safe read',
      }, retryOnTransportFailure: true);
      ctx.observe('recovered', recovered);
      final calls = _rpcCalls(server.requests, 'tools/call');
      ctx.expectEquals(recovered, 'echo:safe read', 'replayed result');
      ctx.expectEquals(calls.length, 2, 'tools/call attempts on the wire');

      dropNext = true;
      final noPolicy = _clientFor(ctx, server.url('/mcp'));
      final ambiguous = await ctx
          .expectThrows<MCPAmbiguousToolCompletionException>(
            () => noPolicy.callTool('echo', {
              'text': 'x',
            }, retryOnTransportFailure: true),
            'opt-in without a policy',
          );
      ctx.expectEquals(ambiguous.toolName, 'echo', 'toolName');
      ctx.expectEquals(
        _rpcCalls(server.requests, 'tools/call').length,
        3,
        'no replay without a policy',
      );
    },
  ),
  Check(
    id: 'reconnect-policy',
    feature: 'mcp-failure-handling',
    description:
        'With an MCPReconnectPolicy and transportFactory, a read-only request that '
        'loses its response reconnects on a fresh transport, re-initializes and succeeds; '
        'delayFor grows exponentially up to the cap.',
    run: (ctx) async {
      var dropNext = false;
      final server = await _DroppingServer.start(ctx, (request) {
        if (dropNext &&
            request.method == 'POST' &&
            request.jsonObject['method'] == 'tools/list') {
          dropNext = false;
          return null;
        }
        return _mcpHandler(sessionId: 'sess-r')(request) as FixtureResponse;
      });
      final client = _clientFor(
        ctx,
        server.url('/mcp'),
        reconnectPolicy: const MCPReconnectPolicy(
          maxAttempts: 3,
          initialDelayMs: 10,
          maxDelayMs: 20,
        ),
      );
      await client.initialize();
      dropNext = true;
      final tools = await client.tools();
      ctx.observe('toolNames', tools.keys.toList());
      final methods = _postMethods(server.requests);
      ctx.observe('methods', methods);
      ctx.expectEquals(tools.keys.toList(), ['echo'], 'tools after reconnect');
      ctx.expectEquals(
        methods.where((m) => m == 'initialize').length,
        2,
        'a second initialize on the fresh transport',
      );
      ctx.expectEquals(
        methods.where((m) => m == 'tools/list').length,
        2,
        'tools/list is retried',
      );
      const policy = MCPReconnectPolicy(
        initialDelayMs: 100,
        maxDelayMs: 350,
        backoffFactor: 2,
      );
      final delays = [
        for (var i = 0; i < 4; i++) policy.delayFor(i).inMilliseconds,
      ];
      ctx.observe('delaysMs', delays);
      ctx.expectEquals(delays, [100, 200, 350, 350], 'delayFor');
    },
  ),
  Check(
    id: 'listener-resume-backoff',
    feature: 'mcp-http-listener',
    description:
        'The GET listener delivers server notifications, resumes with Last-Event-ID '
        'after the stream ends, and waits longer before each further reconnect.',
    run: (ctx) async {
      final clock = Stopwatch()..start();
      final getTimes = <int>[];
      final server = await ctx.server(
        _mcpHandler(
          onGet: (request) {
            getTimes.add(clock.elapsedMilliseconds);
            if (getTimes.length == 1) {
              return FixtureResponse.sse([
                SseEvent({
                  'jsonrpc': '2.0',
                  'method': 'notifications/message',
                  'params': {'level': 'info', 'data': 'hello'},
                }, id: 'evt-7'),
              ]);
            }
            return FixtureResponse.sse(const []);
          },
        ),
      );
      final client = _httpClient(
        ctx,
        server,
        listenerReconnectDelay: const Duration(milliseconds: 40),
      );
      final received = <Map<String, dynamic>>[];
      final transport = client.transport as StreamableHttpClientTransport;
      final sub = transport.notifications.listen(received.add);
      ctx.onCleanup(sub.cancel);
      await client.initialize();
      await _until(() => getTimes.length >= 4, 'four listener connections');
      final gets = server.requests.where((r) => r.method == 'GET').toList();
      ctx.observe('getAtMs', getTimes);
      ctx.observe('lastEventIds', [
        for (final g in gets) g.headers['last-event-id'],
      ]);
      ctx.observe('notifications', received);
      ctx.expectEquals(received.length, 1, 'notifications delivered');
      ctx.expectEquals(
        received.single['method'],
        'notifications/message',
        'method',
      );
      ctx.expectEquals(gets.first.headers['last-event-id'], null, 'first GET');
      for (final g in gets.skip(1).take(3)) {
        ctx.expectEquals(g.headers['last-event-id'], 'evt-7', 'resume header');
        ctx.expectEquals(g.headers['mcp-session-id'], 'sess-1', 'GET session');
      }
      // Reconnect waits are 40, 80, 160 ms; timestamps give lower bounds only.
      ctx.expect(
        getTimes[1] - getTimes[0] >= 35,
        'first wait ~40ms: $getTimes',
      );
      ctx.expect(
        getTimes[2] - getTimes[1] >= 70,
        'second wait ~80ms: $getTimes',
      );
      ctx.expect(
        getTimes[3] - getTimes[2] >= 140,
        'third wait ~160ms: $getTimes',
      );
    },
  ),
  // ----- prompts and resources -----
  Check(
    id: 'prompts-and-resources',
    feature: 'mcp-prompts-resources',
    description:
        'listPrompts, getPrompt with arguments, listResources and readResource '
        '(text and blob parts) send the MCP methods and map the replies to typed values.',
    run: (ctx) async {
      final server = await ctx.server(
        _mcpHandler(
          override: (_, rpc) {
            final id = rpc['id'];
            final params = ((rpc['params'] as Map?) ?? {})
                .cast<String, dynamic>();
            switch (rpc['method']) {
              case 'prompts/list':
                return _reply(id, {
                  'prompts': [
                    {
                      'name': 'summarize',
                      'description': 'Summarize a text.',
                      'arguments': [
                        {
                          'name': 'text',
                          'description': 'Text to summarize',
                          'required': true,
                        },
                      ],
                    },
                  ],
                });
              case 'prompts/get':
                return _reply(id, {
                  'description': 'Summarize prompt',
                  'messages': [
                    {
                      'role': 'user',
                      'content': _text(
                        'Summarize: ${(params['arguments'] as Map)['text']}',
                      ),
                    },
                  ],
                });
              case 'resources/list':
                return _reply(id, {
                  'resources': [
                    {
                      'uri': 'file:///notes.txt',
                      'name': 'notes',
                      'description': 'Project notes',
                      'mimeType': 'text/plain',
                    },
                  ],
                });
              case 'resources/read':
                return _reply(id, {
                  'contents': [
                    {
                      'uri': params['uri'],
                      'mimeType': 'text/plain',
                      'text': 'remember the milk',
                    },
                    {
                      'uri': '${params['uri']}#attachment',
                      'mimeType': 'application/octet-stream',
                      'blob': 'AQID',
                    },
                  ],
                });
            }
            return null;
          },
        ),
      );
      final client = _httpClient(ctx, server);
      final prompts = await client.listPrompts();
      final rendered = await client.getPrompt(
        'summarize',
        arguments: {'text': 'hello'},
      );
      final resources = await client.listResources();
      final content = await client.readResource('file:///notes.txt');
      final parts = await client.readResourceContents('file:///notes.txt');
      ctx.observe('prompt', {
        'name': prompts.single.name,
        'arguments': prompts.single.arguments.map((a) => a.name).toList(),
      });
      ctx.observe('rendered', rendered.messages.map((m) => m.content).toList());
      ctx.observe('resource', resources.single.uri);
      ctx.observe('blobParts', parts.length);
      ctx.expectEquals(prompts.single.name, 'summarize', 'prompt name');
      ctx.expectEquals(
        prompts.single.arguments.single.required,
        true,
        'required',
      );
      ctx.expectEquals(
        rendered.description,
        'Summarize prompt',
        'prompt description',
      );
      ctx.expectEquals(rendered.messages.single.role, 'user', 'role');
      ctx.expectEquals(
        rendered.messages.single.content,
        'Summarize: hello',
        'text',
      );
      final getCall = _rpcCalls(server.requests, 'prompts/get').single;
      ctx.expectEquals(getCall.jsonObject['params'], {
        'name': 'summarize',
        'arguments': {'text': 'hello'},
      }, 'prompts/get params');
      ctx.expectEquals(
        resources.single.uri,
        'file:///notes.txt',
        'resource uri',
      );
      ctx.expectEquals(
        resources.single.mimeType,
        'text/plain',
        'resource mime',
      );
      ctx.expectEquals(content.text, 'remember the milk', 'first text part');
      ctx.expectEquals(content.allContents.length, 2, 'allContents');
      ctx.expectEquals(content.allContents[1].blob, 'AQID', 'blob part');
      ctx.expectEquals(parts.length, 2, 'readResourceContents');
      ctx.expectEquals(
        _rpcCalls(server.requests, 'resources/read').first.jsonObject['params'],
        {'uri': 'file:///notes.txt'},
        'resources/read params',
      );
    },
  ),
  Check(
    id: 'resource-subscription-push',
    feature: 'mcp-prompts-resources',
    description:
        'subscribeResource sends resources/subscribe; a pushed notifications/resources/updated '
        'on the GET listener makes the client re-read the resource and emit it; cancel sends resources/unsubscribe.',
    run: (ctx) async {
      var reads = 0;
      var gets = 0;
      final server = await ctx.server(
        _mcpHandler(
          onGet: (_) {
            gets++;
            if (gets > 1) return FixtureResponse.text('', status: 405);
            return FixtureResponse.sse([
              SseEvent({
                'jsonrpc': '2.0',
                'method': 'notifications/resources/updated',
                'params': {'uri': 'file:///log.txt'},
              }, id: '1'),
            ], delay: const Duration(milliseconds: 150));
          },
          override: (_, rpc) {
            final id = rpc['id'];
            switch (rpc['method']) {
              case 'resources/subscribe':
              case 'resources/unsubscribe':
                return _reply(id, <String, Object?>{});
              case 'resources/read':
                reads++;
                return _reply(id, {
                  'contents': [
                    {
                      'uri': 'file:///log.txt',
                      'mimeType': 'text/plain',
                      'text': 'version $reads',
                    },
                  ],
                });
            }
            return null;
          },
        ),
      );
      final client = _httpClient(ctx, server);
      await client.initialize();
      final updates = <MCPResourceContent>[];
      final subscription = client
          .subscribeResource('file:///log.txt')
          .listen(updates.add);
      await _until(() => updates.isNotEmpty, 'the pushed resource update');
      await subscription.cancel();
      await _until(
        () => _rpcCalls(server.requests, 'resources/unsubscribe').isNotEmpty,
        'resources/unsubscribe',
      );
      ctx.observe('update', updates.first.text);
      ctx.expectEquals(
        _rpcCalls(
          server.requests,
          'resources/subscribe',
        ).single.jsonObject['params'],
        {'uri': 'file:///log.txt'},
        'resources/subscribe params',
      );
      ctx.expectEquals(updates.first.text, 'version 1', 'emitted content');
      ctx.expectEquals(updates.first.uri, 'file:///log.txt', 'emitted uri');
      ctx.expectEquals(
        _rpcCalls(
          server.requests,
          'resources/unsubscribe',
        ).single.jsonObject['params'],
        {'uri': 'file:///log.txt'},
        'resources/unsubscribe params',
      );
    },
  ),
  // ----- auth -----
  Check(
    id: 'auth-bearer-refresh',
    feature: 'mcp-auth',
    description:
        'MCPAuthConfiguration sends the host token as a Bearer header; on 401 it asks '
        'the host to refresh and replays once only with retryAfterUnauthorized.',
    run: (ctx) async {
      final server = await ctx.server(
        _mcpHandler(
          override: (request, rpc) =>
              request.headers['authorization'] == 'Bearer fresh-token'
              ? null
              : FixtureResponse.text(
                  'unauthorized',
                  status: 401,
                  headers: {'www-authenticate': 'Bearer realm="mcp"'},
                ),
        ),
      );
      final resource = Uri.parse(server.url('/mcp'));
      var refreshes = 0;
      var hostToken = 'stale-token';
      final retrying = _httpClient(
        ctx,
        server,
        auth: MCPAuthConfiguration(
          resource: resource,
          accessToken: () async => hostToken,
          refreshAccessToken: () async {
            refreshes++;
            return hostToken = 'fresh-token';
          },
          retryAfterUnauthorized: true,
        ),
      );
      await retrying.initialize();
      final tools = await retrying.tools();
      final initializes = _rpcCalls(server.requests, 'initialize');
      ctx.observe('authorization', [
        for (final r in initializes) r.headers['authorization'],
      ]);
      ctx.expectEquals(
        [for (final r in initializes) r.headers['authorization']],
        ['Bearer stale-token', 'Bearer fresh-token'],
        'initialize replayed with the refreshed token',
      );
      ctx.expectEquals(refreshes, 1, 'refresh callback calls');
      ctx.expectEquals(tools.keys.toList(), ['echo'], 'tools after refresh');

      final before = server.requests.length;
      var strictRefreshes = 0;
      final strict = _httpClient(
        ctx,
        server,
        auth: MCPAuthConfiguration(
          resource: resource,
          accessToken: () async => 'stale-token',
          refreshAccessToken: () async {
            strictRefreshes++;
            return 'fresh-token';
          },
        ),
      );
      final error = await ctx.expectThrows<MCPTransportException>(
        strict.initialize,
        'no replay without retryAfterUnauthorized',
      );
      ctx.expectEquals(error.statusCode, 401, 'status');
      ctx.expectEquals(
        server.requests.length - before,
        1,
        'one request, no replay',
      );
      ctx.expectEquals(strictRefreshes, 0, 'refresh must not run');
    },
  ),
  Check(
    id: 'auth-discovery',
    feature: 'mcp-auth',
    description:
        'MCPAuthDiscovery finds protected-resource and authorization-server metadata '
        '(path insertion, root fallback, WWW-Authenticate hint); the validators reject mismatches.',
    run: (ctx) async {
      late FixtureServer server;
      server = await ctx.server((request) {
        switch (request.path) {
          case '/.well-known/oauth-protected-resource':
            return FixtureResponse.json({
              'resource': server.url('/mcp'),
              'authorization_servers': [server.origin],
              'scopes_supported': ['mcp.read'],
            });
          case '/hint/metadata':
            return FixtureResponse.json({
              'resource': server.url('/mcp'),
              'authorization_servers': [server.origin],
            });
          case '/.well-known/oauth-authorization-server':
            return FixtureResponse.json({
              'issuer': server.origin,
              'authorization_endpoint': server.url('/authorize'),
              'token_endpoint': server.url('/token'),
              'authorization_response_iss_parameter_supported': true,
            });
        }
        return FixtureResponse.text('not found', status: 404);
      });
      final resource = Uri.parse(server.url('/mcp'));
      final metadata = await MCPAuthDiscovery.discoverProtectedResource(
        resource,
      );
      final hinted = await MCPAuthDiscovery.discoverProtectedResource(
        resource,
        wwwAuthenticate:
            'Bearer realm="mcp", resource_metadata="${server.url('/hint/metadata')}"',
      );
      final issuer = Uri.parse(server.origin);
      final authServer = await MCPAuthDiscovery.authorizationServer(issuer);
      ctx.observe('requestPaths', [for (final r in server.requests) r.path]);
      ctx.observe('scopes', metadata.scopesSupported);
      ctx.expectEquals(
        [for (final r in server.requests) r.path],
        [
          '/.well-known/oauth-protected-resource/mcp',
          '/.well-known/oauth-protected-resource',
          '/hint/metadata',
          '/.well-known/oauth-authorization-server',
        ],
        'discovery request order',
      );
      ctx.expect(
        server.requests.every((r) => !r.headers.containsKey('authorization')),
        'metadata requests must not carry credentials',
      );
      ctx.expectEquals(metadata.resource, resource, 'resource');
      ctx.expectEquals(metadata.authorizationServers, [issuer], 'auth servers');
      ctx.expectEquals(metadata.scopesSupported, ['mcp.read'], 'scopes');
      ctx.expectEquals(hinted.resource, resource, 'hinted resource');
      ctx.expectEquals(authServer.issuer, issuer, 'issuer');
      ctx.expectEquals(
        authServer.tokenEndpoint,
        Uri.parse(server.url('/token')),
        'token endpoint',
      );
      ctx.expectEquals(
        authServer.authorizationResponseIssuerSupported,
        true,
        'RFC 9207 flag',
      );

      final config = MCPAuthConfiguration(resource: resource, issuer: issuer);
      config.validateProtectedResource(metadata);
      config.validateAuthorizationIssuer(
        server.origin,
        issuerParameterSupported: true,
      );
      await ctx.expectThrows<MCPException>(
        () async => config.validateAuthorizationIssuer(
          'https://evil.example',
          issuerParameterSupported: true,
        ),
        'issuer mismatch',
      );
      await ctx.expectThrows<MCPException>(
        () async => config.validateAuthorizationIssuer(
          null,
          issuerParameterSupported: true,
        ),
        'missing issuer',
      );
      await ctx.expectThrows<MCPException>(
        () async => MCPAuthConfiguration(
          resource: Uri.parse('https://other.example/mcp'),
        ).validateProtectedResource(metadata),
        'resource mismatch',
      );
      ctx.expectEquals(
        MCPAuthConfiguration.validateRedirectUri(
          Uri.parse('http://127.0.0.1:8080/callback'),
        ),
        Uri.parse('http://127.0.0.1:8080/callback'),
        'loopback redirect accepted',
      );
      for (final bad in [
        'http://example.com/callback',
        'https://example.com/callback#frag',
        'https://user:pw@example.com/callback',
      ]) {
        await ctx.expectThrows<ArgumentError>(
          () async => MCPAuthConfiguration.validateRedirectUri(Uri.parse(bad)),
          'redirect $bad',
        );
      }
    },
  ),
  // ----- stdio against the pinned TypeScript SDK server -----
  Check(
    id: 'stdio-reference-handshake-tools',
    feature: 'mcp-stdio',
    description:
        'StdioMCPTransport spawns the pinned TypeScript SDK server, negotiates 2025-06-18, '
        'sends notifications/initialized and discovers the echo tool with its description.',
    run: (ctx) async {
      final stdio = _referenceServer(ctx);
      final client = MCPClient(transport: stdio.transport);
      ctx.onCleanup(client.close);
      await client.initialize();
      await client.initialize();
      final tools = await client.tools();
      ctx.observe('stdioFrames', stdio.log.frames);
      ctx.observe('toolNames', tools.keys.toList());
      final initializes = stdio.log.sent('->', method: 'initialize');
      ctx.expectEquals(initializes.length, 1, 'initialize frames');
      ctx.expectEquals(
        (initializes.single['params'] as Map)['protocolVersion'],
        '2025-06-18',
        'client version',
      );
      final replies = stdio.log
          .sent('<-')
          .where((m) => m['result'] is Map)
          .toList();
      ctx.expectEquals(
        ((replies.first['result'] as Map)['serverInfo'] as Map)['name'],
        'dart-sdk-reference',
        'server name',
      );
      ctx.expectEquals(
        (replies.first['result'] as Map)['protocolVersion'],
        '2025-06-18',
        'negotiated version',
      );
      final methods = [for (final m in stdio.log.sent('->')) m['method']];
      ctx.expectEquals(methods, [
        'initialize',
        'notifications/initialized',
        'tools/list',
      ], 'client frames in order');
      final listReply = replies.firstWhere(
        (m) => (m['result'] as Map).containsKey('tools'),
      );
      final listed =
          ((listReply['result'] as Map)['tools'] as List).single as Map;
      ctx.expectEquals(listed['name'], 'echo', 'tool on the wire');
      ctx.expectEquals(tools.keys.toList(), ['echo'], 'ToolSet keys');
      ctx.expectEquals(
        tools['echo']!.description,
        'Return fixture text or an explicit tool failure.',
        'description from the server',
      );
    },
  ),
  Check(
    id: 'stdio-reference-calls',
    feature: 'mcp-stdio',
    description:
        'Against the TypeScript SDK server, callTool round-trips Unicode text, '
        'reports an isError result as MCPException, and keeps working afterwards.',
    run: (ctx) async {
      final stdio = _referenceServer(ctx);
      final client = MCPClient(transport: stdio.transport);
      ctx.onCleanup(client.close);
      final first = await client.callTool('echo', {'text': 'snow ☃'});
      final failure = await ctx.expectThrows<MCPException>(
        () => client.callTool('echo', {'text': 'failure', 'fail': true}),
        'tool failure',
      );
      final after = await client.callTool('echo', {'text': 'after'});
      ctx.observe('stdioFrames', stdio.log.frames);
      ctx.observe('results', [first, after]);
      ctx.expectEquals(first, 'echo:snow ☃', 'unicode round trip');
      ctx.expect(
        failure.message.contains('fixture tool failed'),
        'isError message: ${failure.message}',
      );
      ctx.expectEquals(after, 'echo:after', 'call after a tool error');
      final calls = stdio.log.sent('->', method: 'tools/call');
      ctx.expectEquals(calls.length, 3, 'tools/call frames');
      ctx.expectEquals((calls[1]['params'] as Map)['arguments'], {
        'text': 'failure',
        'fail': true,
      }, 'failure call arguments');
      final errorReply = stdio.log
          .sent('<-')
          .firstWhere((m) => m['id'] == calls[1]['id']);
      ctx.expectEquals(
        (errorReply['result'] as Map)['isError'],
        true,
        'isError on the wire',
      );
    },
  ),
  Check(
    id: 'stdio-close-and-failures',
    feature: 'mcp-stdio',
    description:
        'close() ends the child process and later calls fail with a clear error; a '
        'missing command and a process that exits early surface as MCPException.',
    run: (ctx) async {
      final stdio = _referenceServer(ctx);
      final client = MCPClient(transport: stdio.transport);
      await client.initialize();
      final pid = stdio.process.pid;
      await client.close();
      await client.close(); // idempotent
      final exit = await stdio.process.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () =>
            throw CheckFailure('pid $pid still running after close()'),
      );
      ctx.observe('childExitCode', exit);
      final closed = await ctx.expectThrows<MCPException>(
        () => client.callTool('echo', {'text': 'late'}),
        'call after close',
      );
      ctx.expect(
        closed.message.toLowerCase().contains('closed'),
        'closed message: ${closed.message}',
      );

      final missing = MCPClient(
        transport: StdioMCPTransport(command: '/nonexistent/mcp-server-binary'),
      );
      ctx.onCleanup(missing.close);
      final missingError = await ctx.expectThrows<MCPException>(
        missing.initialize,
        'missing command',
      );
      ctx.expect(
        missingError.message.contains('Failed to start stdio MCP process'),
        'missing command message: ${missingError.message}',
      );

      final dying = MCPClient(
        transport: StdioMCPTransport(
          command: 'node',
          args: ['-e', 'process.exit(3)'],
        ),
      );
      ctx.onCleanup(dying.close);
      final dyingError = await ctx.expectThrows<MCPException>(
        dying.initialize,
        'early exit',
      );
      ctx.expect(
        dyingError.message.contains('exited with code 3'),
        'early exit message: ${dyingError.message}',
      );
    },
  ),
]);
