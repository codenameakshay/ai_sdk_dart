import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai/ai.dart';
import 'package:http/http.dart' as http;

/// JSON-RPC 2.0 request.
class _JsonRpcRequest {
  _JsonRpcRequest({
    required this.method,
    required this.id,
    this.params,
  });

  final String method;
  final int id;
  final Map<String, dynamic>? params;

  Map<String, dynamic> toJson() => {
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        if (params != null) 'params': params,
      };
}

/// JSON-RPC 2.0 response.
class _JsonRpcResponse {
  const _JsonRpcResponse({this.result, this.error, this.id});

  final Object? result;
  final Map<String, dynamic>? error;
  final int? id;

  bool get isError => error != null;

  factory _JsonRpcResponse.fromJson(Map<String, dynamic> json) {
    return _JsonRpcResponse(
      result: json['result'],
      error: json['error'] is Map
          ? (json['error'] as Map).cast<String, dynamic>()
          : null,
      id: json['id'] is int ? json['id'] as int : null,
    );
  }
}

/// MCP tool descriptor returned by `tools/list`.
class MCPToolInfo {
  const MCPToolInfo({
    required this.name,
    this.description,
    required this.inputSchema,
  });

  final String name;
  final String? description;
  final Map<String, dynamic> inputSchema;
}

/// Abstract MCP transport.
abstract class MCPTransport {
  /// Send a JSON-RPC request and receive the response.
  Future<_JsonRpcResponse> send(_JsonRpcRequest request);

  /// Close the transport.
  Future<void> close();
}

/// SSE (HTTP) transport — connects to an MCP server over HTTP SSE.
///
/// Sends requests via POST to [postUrl] and receives events via SSE at [url].
class SseClientTransport implements MCPTransport {
  SseClientTransport({
    required this.url,
    Uri? postUrl,
    this.headers,
  }) : postUrl = postUrl ?? url;

  final Uri url;
  final Uri postUrl;
  final Map<String, String>? headers;

  final _client = http.Client();

  @override
  Future<_JsonRpcResponse> send(_JsonRpcRequest request) async {
    final allHeaders = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      ...?headers,
    };
    final response = await _client.post(
      postUrl,
      headers: allHeaders,
      body: jsonEncode(request.toJson()),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MCPException(
        'HTTP ${response.statusCode}: ${response.body}',
      );
    }
    final body = jsonDecode(response.body);
    if (body is! Map) {
      throw MCPException('Unexpected MCP response format: $body');
    }
    return _JsonRpcResponse.fromJson(body.cast<String, dynamic>());
  }

  @override
  Future<void> close() async {
    _client.close();
  }
}

/// Stdio transport — spawns a process and communicates via stdin/stdout.
class StdioMCPTransport implements MCPTransport {
  StdioMCPTransport({required this.command, this.args = const []});

  final String command;
  final List<String> args;

  Process? _process;
  StreamSubscription<String>? _stdoutSub;
  final _pending = <int, Completer<_JsonRpcResponse>>{};
  final _buffer = StringBuffer();

  Future<void> _ensureStarted() async {
    if (_process != null) return;
    _process = await Process.start(command, args);
    _stdoutSub = _process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleLine);
  }

  void _handleLine(String line) {
    if (line.trim().isEmpty) return;
    _buffer.write(line);
    try {
      final json = jsonDecode(_buffer.toString());
      _buffer.clear();
      if (json is Map<String, dynamic>) {
        final response = _JsonRpcResponse.fromJson(json);
        final id = response.id;
        if (id != null && _pending.containsKey(id)) {
          _pending.remove(id)!.complete(response);
        }
      }
    } catch (_) {
      // Incomplete JSON — accumulate more lines.
    }
  }

  @override
  Future<_JsonRpcResponse> send(_JsonRpcRequest request) async {
    await _ensureStarted();
    final completer = Completer<_JsonRpcResponse>();
    _pending[request.id] = completer;
    final line = '${jsonEncode(request.toJson())}\n';
    _process!.stdin.write(line);
    await _process!.stdin.flush();
    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _pending.remove(request.id);
        throw MCPException('Timeout waiting for response to ${request.method}');
      },
    );
  }

  @override
  Future<void> close() async {
    await _stdoutSub?.cancel();
    _process?.stdin.close();
    _process?.kill();
    _process = null;
  }
}

/// Exception thrown by the MCP client.
class MCPException implements Exception {
  const MCPException(this.message);
  final String message;

  @override
  String toString() => 'MCPException: $message';
}

/// MCP client — connects to an MCP server, discovers tools, and invokes them.
///
/// ```dart
/// final client = MCPClient(
///   transport: SseClientTransport(url: Uri.parse('http://localhost:3000/mcp')),
/// );
/// await client.initialize();
/// final tools = await client.tools();
/// ```
class MCPClient {
  MCPClient({required this.transport});

  final MCPTransport transport;
  int _nextId = 1;

  int get _id => _nextId++;

  bool _initialized = false;

  /// Perform the MCP initialize handshake.
  ///
  /// Must be called before [tools] or [callTool].
  Future<void> initialize() async {
    if (_initialized) return;
    final response = await transport.send(
      _JsonRpcRequest(
        method: 'initialize',
        id: _id,
        params: {
          'protocolVersion': '2024-11-05',
          'capabilities': {'tools': {}},
          'clientInfo': {'name': 'ai_sdk_dart', 'version': '0.1.0'},
        },
      ),
    );
    if (response.isError) {
      throw MCPException(
        'Initialize failed: ${response.error}',
      );
    }
    // Send initialized notification (fire-and-forget, no response expected).
    try {
      await transport.send(
        _JsonRpcRequest(method: 'notifications/initialized', id: _id),
      );
    } catch (_) {
      // Notifications may not return a response — ignore errors.
    }
    _initialized = true;
  }

  /// Discover all tools available on the MCP server.
  ///
  /// Returns a [ToolSet] compatible with `generateText`/`streamText`.
  Future<ToolSet> tools() async {
    await initialize();
    final response = await transport.send(
      _JsonRpcRequest(method: 'tools/list', id: _id),
    );
    if (response.isError) {
      throw MCPException('tools/list failed: ${response.error}');
    }
    final result = response.result;
    if (result is! Map) return {};

    final toolsList = result['tools'];
    if (toolsList is! List) return {};

    final toolSet = <String, Tool<dynamic, dynamic>>{};
    for (final toolData in toolsList) {
      if (toolData is! Map) continue;
      final info = MCPToolInfo(
        name: toolData['name']?.toString() ?? '',
        description: toolData['description']?.toString(),
        inputSchema: toolData['inputSchema'] is Map
            ? (toolData['inputSchema'] as Map).cast<String, dynamic>()
            : {'type': 'object'},
      );
      if (info.name.isEmpty) continue;

      toolSet[info.name] = dynamicTool(
        description: info.description,
        execute: (input, options) => callTool(info.name, input),
      );
    }
    return toolSet;
  }

  /// Call a specific tool by [name] with the given [input].
  Future<Object?> callTool(String name, Object? input) async {
    await initialize();
    final response = await transport.send(
      _JsonRpcRequest(
        method: 'tools/call',
        id: _id,
        params: {
          'name': name,
          'arguments': input is Map ? input : {'value': input},
        },
      ),
    );
    if (response.isError) {
      throw MCPException(
        'tools/call "$name" failed: ${response.error}',
      );
    }
    final result = response.result;
    if (result is! Map) return result;
    // MCP returns {content: [{type: 'text', text: '...'}], isError: bool}
    final content = result['content'];
    final isError = result['isError'] == true;
    if (content is List && content.isNotEmpty) {
      final parts = content
          .whereType<Map>()
          .where((p) => p['type'] == 'text')
          .map((p) => p['text']?.toString() ?? '')
          .join('\n');
      if (isError) throw MCPException('Tool "$name" returned error: $parts');
      return parts;
    }
    return result;
  }

  /// Close the transport connection.
  Future<void> close() => transport.close();
}
