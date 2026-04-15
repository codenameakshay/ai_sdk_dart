import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:http/http.dart' as http;

// ---------------------------------------------------------------------------
// JSON-RPC primitives
// ---------------------------------------------------------------------------

/// JSON-RPC 2.0 request.
class _JsonRpcRequest {
  _JsonRpcRequest({required this.method, required this.id, this.params});

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

// ---------------------------------------------------------------------------
// Data types
// ---------------------------------------------------------------------------

/// MCP tool descriptor returned by [MCPClient.tools].
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

/// MCP prompt descriptor returned by [MCPClient.listPrompts].
class MCPPromptInfo {
  const MCPPromptInfo({
    required this.name,
    this.description,
    this.arguments = const [],
  });

  final String name;
  final String? description;

  /// Declared arguments for the prompt.
  final List<MCPPromptArgument> arguments;
}

/// A declared argument for an MCP prompt.
class MCPPromptArgument {
  const MCPPromptArgument({
    required this.name,
    this.description,
    this.required = false,
  });

  final String name;
  final String? description;
  final bool required;
}

/// A rendered prompt returned by [MCPClient.getPrompt].
class MCPPromptResult {
  const MCPPromptResult({required this.messages, this.description});

  final List<MCPPromptMessage> messages;
  final String? description;
}

/// A single message in a rendered MCP prompt.
class MCPPromptMessage {
  const MCPPromptMessage({required this.role, required this.content});

  final String role;
  final String content;
}

/// An MCP resource descriptor returned by [MCPClient.listResources].
class MCPResourceInfo {
  const MCPResourceInfo({
    required this.uri,
    required this.name,
    this.description,
    this.mimeType,
  });

  final String uri;
  final String name;
  final String? description;
  final String? mimeType;
}

/// Content of an MCP resource returned by [MCPClient.readResource].
class MCPResourceContent {
  const MCPResourceContent({
    required this.uri,
    required this.mimeType,
    this.text,
    this.blob,
  });

  final String uri;
  final String mimeType;

  /// Text content (for text/* MIME types).
  final String? text;

  /// Base64-encoded binary content (for binary MIME types).
  final String? blob;
}

// ---------------------------------------------------------------------------
// Exception
// ---------------------------------------------------------------------------

/// Exception thrown when an MCP operation fails.
class MCPException implements Exception {
  const MCPException(this.message);
  final String message;

  @override
  String toString() => 'MCPException: $message';
}

// ---------------------------------------------------------------------------
// Transports
// ---------------------------------------------------------------------------

/// Abstract transport for MCP JSON-RPC communication.
abstract class MCPTransport {
  /// Send a JSON-RPC request and receive the response.
  Future<_JsonRpcResponse> send(_JsonRpcRequest request);

  /// Close the transport.
  Future<void> close();
}

/// SSE (HTTP) transport for MCP over HTTP.
///
/// Sends requests via POST to [postUrl]; receives responses as JSON.
class SseClientTransport implements MCPTransport {
  SseClientTransport({required this.url, Uri? postUrl, this.headers})
    : postUrl = postUrl ?? url;

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
      throw MCPException('HTTP ${response.statusCode}: ${response.body}');
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

/// Stdio transport for MCP — spawns [command] and communicates via stdin/stdout.
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

// ---------------------------------------------------------------------------
// MCPClient
// ---------------------------------------------------------------------------

/// Configuration for automatic reconnection on transport failures.
class MCPReconnectPolicy {
  const MCPReconnectPolicy({
    this.maxAttempts = 5,
    this.initialDelayMs = 500,
    this.maxDelayMs = 30000,
    this.backoffFactor = 2.0,
  });

  /// Maximum number of reconnect attempts before giving up.
  final int maxAttempts;

  /// Delay before the first reconnect attempt (milliseconds).
  final int initialDelayMs;

  /// Maximum delay between reconnect attempts (milliseconds).
  final int maxDelayMs;

  /// Multiplier applied to the delay after each failed attempt.
  final double backoffFactor;

  Duration delayFor(int attempt) {
    // Simple exponential: initialDelay * factor^attempt
    var delay = initialDelayMs.toDouble();
    for (var i = 0; i < attempt; i++) {
      delay *= backoffFactor;
      if (delay >= maxDelayMs) {
        delay = maxDelayMs.toDouble();
        break;
      }
    }
    return Duration(milliseconds: delay.round());
  }
}

/// MCP client — connects to an MCP server, discovers tools, prompts, and
/// resources, and optionally reconnects on transport failures.
///
/// ```dart
/// final client = MCPClient(
///   transport: SseClientTransport(url: Uri.parse('http://localhost:3000/mcp')),
///   reconnectPolicy: MCPReconnectPolicy(),
/// );
/// await client.initialize();
/// final tools = await client.tools();
/// final prompts = await client.listPrompts();
/// final resources = await client.listResources();
/// ```
class MCPClient {
  MCPClient({
    required this.transport,
    this.reconnectPolicy,
    MCPTransportFactory? transportFactory,
  }) : _transportFactory = transportFactory;

  MCPTransport transport;

  /// When set, the client will automatically try to reconnect on failures.
  final MCPReconnectPolicy? reconnectPolicy;

  /// Factory used to create fresh transports during reconnection.
  ///
  /// Required when [reconnectPolicy] is set and the transport cannot be
  /// reused after a failure.
  final MCPTransportFactory? _transportFactory;

  int _nextId = 1;
  int get _id => _nextId++;

  bool _initialized = false;

  /// Resource subscription controllers keyed by resource URI.
  final _resourceSubscriptions = <String, StreamController<MCPResourceContent>>{};

  // ---------------------------------------------------------------------------
  // Initialize + reconnect
  // ---------------------------------------------------------------------------

  /// Perform the MCP initialize handshake.
  ///
  /// Must be called before any other method.  Safe to call multiple times —
  /// subsequent calls are no-ops.
  Future<void> initialize() async {
    if (_initialized) return;
    await _doInitialize();
  }

  Future<void> _doInitialize() async {
    final response = await transport.send(
      _JsonRpcRequest(
        method: 'initialize',
        id: _id,
        params: {
          'protocolVersion': '2024-11-05',
          'capabilities': {
            'tools': {},
            'prompts': {},
            'resources': {'subscribe': true},
          },
          'clientInfo': {'name': 'ai_sdk_dart', 'version': '0.1.0'},
        },
      ),
    );
    if (response.isError) {
      throw MCPException('Initialize failed: ${response.error}');
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

  /// Send a request, retrying with reconnect if the policy allows.
  Future<_JsonRpcResponse> _send(_JsonRpcRequest request) async {
    final policy = reconnectPolicy;
    if (policy == null) {
      return transport.send(request);
    }
    for (var attempt = 0; attempt <= policy.maxAttempts; attempt++) {
      try {
        return await transport.send(request);
      } catch (e) {
        if (attempt >= policy.maxAttempts) rethrow;
        // Try to reconnect.
        final delay = policy.delayFor(attempt);
        await Future<void>.delayed(delay);
        if (_transportFactory != null) {
          await transport.close();
          transport = _transportFactory();
          _initialized = false;
          try {
            await _doInitialize();
          } catch (_) {
            // Will retry on the next loop iteration.
          }
        }
      }
    }
    throw MCPException('Max reconnect attempts reached');
  }

  // ---------------------------------------------------------------------------
  // Tools
  // ---------------------------------------------------------------------------

  /// Discover all tools available on the MCP server.
  ///
  /// Returns a [ToolSet] compatible with `generateText`/`streamText`.
  Future<ToolSet> tools() async {
    await initialize();
    final response = await _send(
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
    final response = await _send(
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
      throw MCPException('tools/call "$name" failed: ${response.error}');
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

  // ---------------------------------------------------------------------------
  // Prompts
  // ---------------------------------------------------------------------------

  /// List all prompts available on the MCP server.
  Future<List<MCPPromptInfo>> listPrompts() async {
    await initialize();
    final response = await _send(
      _JsonRpcRequest(method: 'prompts/list', id: _id),
    );
    if (response.isError) {
      throw MCPException('prompts/list failed: ${response.error}');
    }
    final result = response.result;
    if (result is! Map) return [];
    final prompts = result['prompts'];
    if (prompts is! List) return [];

    return prompts.whereType<Map>().map((p) {
      final args = (p['arguments'] as List?)
              ?.whereType<Map>()
              .map(
                (a) => MCPPromptArgument(
                  name: a['name']?.toString() ?? '',
                  description: a['description']?.toString(),
                  required: a['required'] == true,
                ),
              )
              .toList() ??
          [];
      return MCPPromptInfo(
        name: p['name']?.toString() ?? '',
        description: p['description']?.toString(),
        arguments: args,
      );
    }).toList();
  }

  /// Get (render) a specific prompt by [name], optionally passing [arguments].
  ///
  /// Returns the rendered list of messages.
  Future<MCPPromptResult> getPrompt(
    String name, {
    Map<String, String> arguments = const {},
  }) async {
    await initialize();
    final response = await _send(
      _JsonRpcRequest(
        method: 'prompts/get',
        id: _id,
        params: {
          'name': name,
          if (arguments.isNotEmpty) 'arguments': arguments,
        },
      ),
    );
    if (response.isError) {
      throw MCPException('prompts/get "$name" failed: ${response.error}');
    }
    final result = response.result;
    if (result is! Map) {
      return const MCPPromptResult(messages: []);
    }
    final msgs = (result['messages'] as List?) ?? [];
    final messages = msgs.whereType<Map>().map((m) {
      final contentData = m['content'];
      String text = '';
      if (contentData is Map && contentData['type'] == 'text') {
        text = contentData['text']?.toString() ?? '';
      } else if (contentData is String) {
        text = contentData;
      }
      return MCPPromptMessage(
        role: m['role']?.toString() ?? 'user',
        content: text,
      );
    }).toList();

    return MCPPromptResult(
      messages: messages,
      description: result['description']?.toString(),
    );
  }

  // ---------------------------------------------------------------------------
  // Resources
  // ---------------------------------------------------------------------------

  /// List all resources available on the MCP server.
  Future<List<MCPResourceInfo>> listResources() async {
    await initialize();
    final response = await _send(
      _JsonRpcRequest(method: 'resources/list', id: _id),
    );
    if (response.isError) {
      throw MCPException('resources/list failed: ${response.error}');
    }
    final result = response.result;
    if (result is! Map) return [];
    final resources = result['resources'];
    if (resources is! List) return [];

    return resources.whereType<Map>().map((r) {
      return MCPResourceInfo(
        uri: r['uri']?.toString() ?? '',
        name: r['name']?.toString() ?? '',
        description: r['description']?.toString(),
        mimeType: r['mimeType']?.toString(),
      );
    }).toList();
  }

  /// Read the current content of a resource at [uri].
  Future<MCPResourceContent> readResource(String uri) async {
    await initialize();
    final response = await _send(
      _JsonRpcRequest(
        method: 'resources/read',
        id: _id,
        params: {'uri': uri},
      ),
    );
    if (response.isError) {
      throw MCPException('resources/read "$uri" failed: ${response.error}');
    }
    final result = response.result;
    if (result is! Map) {
      return MCPResourceContent(uri: uri, mimeType: 'application/octet-stream');
    }
    final contents = result['contents'];
    if (contents is! List || contents.isEmpty) {
      return MCPResourceContent(uri: uri, mimeType: 'application/octet-stream');
    }
    final first = contents.first;
    if (first is! Map) {
      return MCPResourceContent(uri: uri, mimeType: 'application/octet-stream');
    }
    return MCPResourceContent(
      uri: first['uri']?.toString() ?? uri,
      mimeType: first['mimeType']?.toString() ?? 'text/plain',
      text: first['text']?.toString(),
      blob: first['blob']?.toString(),
    );
  }

  /// Subscribe to live updates for a resource at [uri].
  ///
  /// Returns a [Stream] that emits whenever the resource changes.
  /// The subscription is automatically cancelled when the stream is cancelled.
  ///
  /// Note: the server must support `resources/subscribe`. Polling is used when
  /// server-push is not available; for full push support, use an SSE transport
  /// and override this via a subclass.
  Stream<MCPResourceContent> subscribeResource(String uri) {
    final existing = _resourceSubscriptions[uri];
    if (existing != null && !existing.isClosed) {
      return existing.stream;
    }

    final controller = StreamController<MCPResourceContent>.broadcast(
      onCancel: () => _unsubscribeResource(uri),
    );
    _resourceSubscriptions[uri] = controller;

    // Send subscribe request (best-effort; server may not support it).
    unawaited(
      _subscribeResourceOnServer(uri).catchError(
        (_) {}, // Silently ignore if server doesn't support subscriptions.
      ),
    );

    return controller.stream;
  }

  Future<void> _subscribeResourceOnServer(String uri) async {
    await initialize();
    final response = await _send(
      _JsonRpcRequest(
        method: 'resources/subscribe',
        id: _id,
        params: {'uri': uri},
      ),
    );
    if (response.isError) {
      throw MCPException(
        'resources/subscribe "$uri" failed: ${response.error}',
      );
    }
  }

  Future<void> _unsubscribeResource(String uri) async {
    _resourceSubscriptions.remove(uri);
    try {
      await initialize();
      await _send(
        _JsonRpcRequest(
          method: 'resources/unsubscribe',
          id: _id,
          params: {'uri': uri},
        ),
      );
    } catch (_) {
      // Best-effort unsubscribe — ignore errors.
    }
  }

  /// Push a resource update to all active subscribers for [uri].
  ///
  /// Call this when the transport receives a `notifications/resources/updated`
  /// message from the server.
  void notifyResourceUpdated(String uri, MCPResourceContent content) {
    _resourceSubscriptions[uri]?.add(content);
  }

  // ---------------------------------------------------------------------------
  // Close
  // ---------------------------------------------------------------------------

  /// Close the transport connection and all resource subscriptions.
  Future<void> close() async {
    for (final controller in _resourceSubscriptions.values) {
      await controller.close();
    }
    _resourceSubscriptions.clear();
    await transport.close();
  }
}

/// Factory function that creates a fresh [MCPTransport] for reconnection.
typedef MCPTransportFactory = MCPTransport Function();
