import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';

import 'http_transport.dart';
import 'json_rpc.dart';

// Re-export the stable JSON-RPC transport surface so callers implementing
// custom MCP transports can use only the package barrel import.
export 'json_rpc.dart'
    show
        JsonRpcRequest,
        JsonRpcResponse,
        JsonRpcNotification,
        MCPTransport,
        MCPException,
        MCPTransportException,
        MCPSessionExpiredException;

// Web-safe HTTP transport (no dart:io).
export 'http_transport.dart' show StreamableHttpClientTransport;

// Stdio transport: real (dart:io) on native, throwing stub on web. The
// top-level library never imports `dart:io` directly — it is reachable only
// through this conditional export.
export 'stdio_transport_stub.dart'
    if (dart.library.io) 'stdio_transport_io.dart'
    show StdioMCPTransport;

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
  const MCPPromptMessage({
    required this.role,
    required this.content,
    this.contentData,
  });

  final String role;

  /// Text projection retained for compatibility with existing callers.
  final String content;

  /// The original MCP content block, including non-text content.
  final Object? contentData;
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
    this.allContents = const [],
  });

  final String uri;
  final String mimeType;

  /// Text content (for text/* MIME types).
  final String? text;

  /// Base64-encoded binary content (for binary MIME types).
  final String? blob;

  /// All content items returned by the same `resources/read` response.
  ///
  /// This is populated on the value returned by [MCPClient.readResource] so
  /// callers can retain the old first-item fields while accessing the full
  /// response. Values created directly or emitted by subscriptions leave it
  /// empty.
  final List<MCPResourceContent> allContents;

  MCPResourceContent _withAllContents(List<MCPResourceContent> contents) {
    return MCPResourceContent(
      uri: uri,
      mimeType: mimeType,
      text: text,
      blob: blob,
      allContents: contents,
    );
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
///   transport: StreamableHttpClientTransport(
///     url: Uri.parse('http://localhost:3000/mcp'),
///   ),
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
  }) : _transportFactory = transportFactory {
    _listenToTransport();
  }

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
  Future<void>? _initializeFuture;

  /// Resource subscription controllers keyed by resource URI.
  final _resourceSubscriptions =
      <String, StreamController<MCPResourceContent>>{};
  final _resourceRefreshStates = <String, _ResourceRefreshState>{};

  /// Subscription to the active transport's server-initiated message stream.
  StreamSubscription<Map<String, dynamic>>? _notificationSub;
  bool _closed = false;

  // ---------------------------------------------------------------------------
  // Transport notifications (server push)
  // ---------------------------------------------------------------------------

  /// Wire the current transport's [MCPTransport.notifications] stream into the
  /// client so server-initiated `notifications/resources/updated` messages
  /// reach resource subscribers automatically.
  void _listenToTransport() {
    _notificationSub?.cancel();
    _notificationSub = transport.notifications.listen(
      _handleServerMessage,
      onError: _handleTransportError,
    );
  }

  void _handleTransportError(Object error, [StackTrace? stackTrace]) {
    if (_closed) return;
    if (error is! MCPSessionExpiredException) {
      return;
    }
    unawaited(_recoverFromSessionExpiry().catchError((_) {}));
  }

  void _handleServerMessage(Map<String, dynamic> json) {
    final method = json['method'];
    if (method != 'notifications/resources/updated') return;
    final params = json['params'];
    if (params is! Map) return;
    final uri = params['uri']?.toString();
    if (uri == null) return;

    final subscription = _resourceSubscriptions[uri];
    if (subscription == null || subscription.isClosed) return;

    _queueResourceRefresh(uri);
  }

  void _queueResourceRefresh(String uri) {
    if (_closed) return;
    final subscription = _resourceSubscriptions[uri];
    if (subscription == null || subscription.isClosed) return;

    var state = _resourceRefreshStates[uri];
    if (state == null || !identical(state.subscription, subscription)) {
      state = _ResourceRefreshState(subscription);
      _resourceRefreshStates[uri] = state;
    }
    state.trailingRefreshQueued = true;
    if (state.inFlight) return;

    state.inFlight = true;
    unawaited(_drainResourceRefreshQueue(uri, state));
  }

  Future<void> _drainResourceRefreshQueue(
    String uri,
    _ResourceRefreshState state,
  ) async {
    try {
      while (state.trailingRefreshQueued && !_closed) {
        state.trailingRefreshQueued = false;

        final currentSubscription = _resourceSubscriptions[uri];
        if (currentSubscription == null ||
            currentSubscription.isClosed ||
            !identical(currentSubscription, state.subscription)) {
          break;
        }

        try {
          final content = await readResource(uri);
          if (_closed) break;

          final currentSubscription = _resourceSubscriptions[uri];
          if (currentSubscription == null ||
              currentSubscription.isClosed ||
              !identical(currentSubscription, state.subscription)) {
            break;
          }
          currentSubscription.add(content);
        } catch (_) {
          if (_closed) break;
        }
      }
    } finally {
      state.inFlight = false;

      final currentState = _resourceRefreshStates[uri];
      final currentSubscription = _resourceSubscriptions[uri];
      if (_closed ||
          currentSubscription == null ||
          currentSubscription.isClosed ||
          !identical(currentState, state) ||
          !identical(currentSubscription, state.subscription)) {
        if (identical(currentState, state)) {
          _resourceRefreshStates.remove(uri);
        }
      } else if (state.trailingRefreshQueued) {
        state.inFlight = true;
        unawaited(_drainResourceRefreshQueue(uri, state));
      } else {
        _resourceRefreshStates.remove(uri);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Initialize + reconnect
  // ---------------------------------------------------------------------------

  /// Perform the MCP initialize handshake.
  ///
  /// Must be called before any other method.  Safe to call multiple times —
  /// subsequent calls are no-ops.
  Future<void> initialize() async {
    await _ensureInitialized();
  }

  Future<void> _ensureInitialized({
    bool forceReinitialize = false,
    bool replayResourceSubscriptions = false,
  }) {
    if (_closed) {
      throw const MCPException('MCP client is closed');
    }
    if (_initialized && !forceReinitialize) {
      return Future.value();
    }
    final existing = _initializeFuture;
    if (existing != null) {
      return existing;
    }

    final future = _runInitialize(
      replayResourceSubscriptions: replayResourceSubscriptions,
    );
    _initializeFuture = future;
    return future.whenComplete(() {
      if (identical(_initializeFuture, future)) {
        _initializeFuture = null;
      }
    });
  }

  Future<void> _runInitialize({
    required bool replayResourceSubscriptions,
  }) async {
    _initialized = false;
    try {
      await _doInitialize(
        replayResourceSubscriptions: replayResourceSubscriptions,
      );
      _initialized = true;
    } catch (_) {
      _initialized = false;
      if (transport
          case final StreamableHttpClientTransport streamableTransport) {
        await streamableTransport.resetHandshakeState();
      }
      rethrow;
    }
  }

  Future<void> _doInitialize({
    required bool replayResourceSubscriptions,
  }) async {
    final response = await transport.send(
      JsonRpcRequest(
        method: 'initialize',
        id: _id,
        params: {
          'protocolVersion': '2025-06-18',
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

    final result = response.result;
    if (result is! Map) {
      throw const MCPException(
        'Initialize failed: result must contain protocolVersion',
      );
    }
    final protocolVersion = result['protocolVersion'];
    if (protocolVersion is! String) {
      throw const MCPException(
        'Initialize failed: result.protocolVersion must be a string',
      );
    }
    if (protocolVersion != '2025-06-18') {
      throw MCPException(
        'Unsupported protocolVersion "$protocolVersion" from initialize',
      );
    }

    if (transport
        case final StreamableHttpClientTransport streamableTransport) {
      streamableTransport.setProtocolVersion(protocolVersion);
    }

    await transport.sendNotification(
      JsonRpcNotification(method: 'notifications/initialized'),
    );

    if (replayResourceSubscriptions) {
      await _replayActiveResourceSubscriptions();
    }

    if (transport
        case final StreamableHttpClientTransport streamableTransport) {
      await streamableTransport.startNotificationListener();
    }
  }

  Future<void> _replayActiveResourceSubscriptions() async {
    for (final entry in _resourceSubscriptions.entries.toList()) {
      final subscription = entry.value;
      if (subscription.isClosed) {
        continue;
      }
      final response = await transport.send(
        JsonRpcRequest(
          method: 'resources/subscribe',
          id: _id,
          params: {'uri': entry.key},
        ),
      );
      if (response.isError) {
        throw MCPException(
          'resources/subscribe "${entry.key}" failed: ${response.error}',
        );
      }
    }
  }

  Future<void> _recoverFromSessionExpiry() {
    if (_closed) {
      return Future.value();
    }
    return _ensureInitialized(
      forceReinitialize: true,
      replayResourceSubscriptions: true,
    );
  }

  /// Send a request, retrying with reconnect if the policy allows.
  Future<JsonRpcResponse> _send(JsonRpcRequest request) async {
    final policy = reconnectPolicy;
    if (policy == null) {
      try {
        return await transport.send(request);
      } on MCPSessionExpiredException {
        await _recoverFromSessionExpiry();
        return transport.send(request);
      }
    }
    for (var attempt = 0; attempt <= policy.maxAttempts; attempt++) {
      try {
        return await transport.send(request);
      } on MCPSessionExpiredException {
        await _recoverFromSessionExpiry();
        return transport.send(request);
      } catch (e) {
        if (attempt >= policy.maxAttempts) rethrow;
        // Try to reconnect.
        final delay = policy.delayFor(attempt);
        await Future<void>.delayed(delay);
        if (_transportFactory != null) {
          await transport.close();
          transport = _transportFactory();
          _listenToTransport();
          _initialized = false;
          try {
            await _ensureInitialized();
          } catch (_) {
            // Will retry on the next loop iteration.
          }
        }
      }
    }
    throw const MCPException('Max reconnect attempts reached');
  }

  // ---------------------------------------------------------------------------
  // Tools
  // ---------------------------------------------------------------------------

  Future<List<Map>> _paginate(String method, String key) async {
    await initialize();
    final entries = <Map>[];
    final seenCursors = <String>{};
    String? cursor;

    while (true) {
      final response = await _send(
        JsonRpcRequest(method: method, id: _id, params: {'cursor': ?cursor}),
      );
      if (response.isError) {
        throw MCPException('$method failed: ${response.error}');
      }
      final result = response.result;
      if (result is! Map) return entries;

      final page = result[key];
      if (page is List) entries.addAll(page.whereType<Map>());

      final nextCursor = result['nextCursor'];
      if (nextCursor is! String || nextCursor.isEmpty) return entries;
      if (!seenCursors.add(nextCursor)) {
        throw MCPException('$method returned a repeated cursor');
      }
      cursor = nextCursor;
    }
  }

  /// Discover all tools available on the MCP server.
  ///
  /// Returns a [ToolSet] compatible with `generateText`/`streamText`.
  Future<ToolSet> tools() async {
    final toolsList = await _paginate('tools/list', 'tools');

    final toolSet = <String, Tool<dynamic, dynamic>>{};
    for (final toolData in toolsList) {
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
      JsonRpcRequest(
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
      final textParts = content
          .whereType<Map>()
          .where((p) => p['type'] == 'text')
          .map((p) => p['text']?.toString() ?? '')
          .toList();
      if (isError) {
        throw MCPException(
          'Tool "$name" returned error: ${content.join('\n')}',
        );
      }
      final hasOnlyText = content.every(
        (part) => part is Map && part['type'] == 'text',
      );
      return hasOnlyText ? textParts.join('\n') : List<Object?>.from(content);
    }
    if (isError) throw MCPException('Tool "$name" returned error');
    return result;
  }

  // ---------------------------------------------------------------------------
  // Prompts
  // ---------------------------------------------------------------------------

  /// List all prompts available on the MCP server.
  Future<List<MCPPromptInfo>> listPrompts() async {
    final prompts = await _paginate('prompts/list', 'prompts');

    return prompts.map((p) {
      final args =
          (p['arguments'] as List?)
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
      JsonRpcRequest(
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
        contentData: contentData,
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
    final resources = await _paginate('resources/list', 'resources');

    return resources.map((r) {
      return MCPResourceInfo(
        uri: r['uri']?.toString() ?? '',
        name: r['name']?.toString() ?? '',
        description: r['description']?.toString(),
        mimeType: r['mimeType']?.toString(),
      );
    }).toList();
  }

  /// Read the current content of a resource at [uri].
  ///
  /// The legacy singular fields expose the first item. Use [allContents] or
  /// [readResourceContents] when the server returns multiple items.
  Future<MCPResourceContent> readResource(String uri) async {
    final contents = await readResourceContents(uri);
    if (contents.isEmpty) {
      return MCPResourceContent(
        uri: uri,
        mimeType: 'application/octet-stream',
        allContents: const [],
      );
    }
    return contents.first._withAllContents(contents);
  }

  /// Read all content items returned for a resource at [uri].
  Future<List<MCPResourceContent>> readResourceContents(String uri) async {
    await initialize();
    final response = await _send(
      JsonRpcRequest(method: 'resources/read', id: _id, params: {'uri': uri}),
    );
    if (response.isError) {
      throw MCPException('resources/read "$uri" failed: ${response.error}');
    }
    final result = response.result;
    if (result is! Map) {
      return const [];
    }
    final contents = result['contents'];
    if (contents is! List || contents.isEmpty) {
      return const [];
    }
    return contents.whereType<Map>().map((content) {
      return MCPResourceContent(
        uri: content['uri']?.toString() ?? uri,
        mimeType: content['mimeType']?.toString() ?? 'text/plain',
        text: content['text']?.toString(),
        blob: content['blob']?.toString(),
      );
    }).toList();
  }

  /// Subscribe to live updates for a resource at [uri].
  ///
  /// Returns a [Stream] that emits whenever the resource changes.
  /// The subscription is automatically cancelled when the stream is cancelled.
  ///
  /// The server must support `resources/subscribe`. When the transport is an
  /// [StreamableHttpClientTransport], server-pushed
  /// `notifications/resources/updated` messages are delivered automatically.
  /// For transports without server push, call [notifyResourceUpdated] yourself.
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
      JsonRpcRequest(
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
    _resourceRefreshStates.remove(uri);
    try {
      await initialize();
      await _send(
        JsonRpcRequest(
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
  /// Called automatically for [StreamableHttpClientTransport] when the server
  /// sends a
  /// `notifications/resources/updated` message. Call it manually when using a
  /// transport without server push.
  void notifyResourceUpdated(String uri, MCPResourceContent content) {
    _resourceSubscriptions[uri]?.add(content);
  }

  // ---------------------------------------------------------------------------
  // Close
  // ---------------------------------------------------------------------------

  /// Close the transport connection and all resource subscriptions.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _notificationSub?.cancel();
    for (final subscription in _resourceSubscriptions.values.toList()) {
      await subscription.close();
    }
    _resourceSubscriptions.clear();
    _resourceRefreshStates.clear();
    await transport.close();
  }
}

/// Factory function that creates a fresh [MCPTransport] for reconnection.
typedef MCPTransportFactory = MCPTransport Function();

class _ResourceRefreshState {
  _ResourceRefreshState(this.subscription);

  final StreamController<MCPResourceContent> subscription;
  bool inFlight = false;
  bool trailingRefreshQueued = false;
}
