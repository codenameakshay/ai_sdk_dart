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
        MCPAmbiguousToolCompletionException,
        MCPTransportException,
        MCPSessionExpiredException;

// Web-safe HTTP transport (no dart:io).
export 'http_transport.dart'
    show
        StreamableHttpClientTransport,
        MCPAuthConfiguration,
        MCPAccessTokenProvider,
        MCPProtectedResourceMetadata,
        MCPAuthorizationServerMetadata,
        MCPAuthDiscovery;

// Stdio transport: real (dart:io) on native, throwing stub on web. The
// top-level library never imports `dart:io` directly — it is reachable only
// through this conditional export.
export 'stdio_transport_stub.dart'
    if (dart.library.io) 'stdio_transport_io.dart'
    show StdioMCPTransport;

/// Protocol eras supported by [MCPClient].
enum MCPProtocolMode { legacy, modern }

class _MCPModernProtocolException extends MCPException {
  const _MCPModernProtocolException(super.message);
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

/// An MCP modern-era multi-round-trip result requesting additional input.
class MCPInputRequiredResult {
  const MCPInputRequiredResult({
    required this.inputRequests,
    this.requestState,
    this.meta,
  });

  /// Server-assigned request IDs mapped to protocol input requests.
  final Map<String, dynamic> inputRequests;
  final Object? requestState;
  final Map<String, dynamic>? meta;
}

/// A validated MCP `notifications/progress` update.
class MCPProgressUpdate {
  const MCPProgressUpdate({
    required this.progressToken,
    required this.progress,
    this.total,
    this.message,
  });

  final Object progressToken;
  final num progress;
  final num? total;
  final String? message;
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
    this.protocolMode = MCPProtocolMode.legacy,
    MCPTransportFactory? transportFactory,
  }) : _transportFactory = transportFactory {
    _listenToTransport();
  }

  MCPTransport transport;

  /// When set, the client will automatically try to reconnect on failures.
  final MCPReconnectPolicy? reconnectPolicy;

  /// Selects the explicit legacy handshake or modern stateless strategy.
  final MCPProtocolMode protocolMode;

  static const modernProtocolVersion = '2026-07-28';
  static const legacyProtocolVersion = '2025-06-18';

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
  final _modernSubscriptionRequestIds = <String, int>{};
  final _progress = StreamController<MCPProgressUpdate>.broadcast();
  final _activeProgress = <Object, num>{};
  final _progressTotals = <Object, num?>{};

  /// Subscription to the active transport's server-initiated message stream.
  StreamSubscription<Map<String, dynamic>>? _notificationSub;
  bool _closed = false;
  final _closedSignal = Completer<void>();

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
    if (json['method'] == 'notifications/progress') {
      final params = json['params'];
      if (params is! Map) return;
      final token = params['progressToken'];
      final value = params['progress'];
      if ((token is! String && token is! int) || value is! num) return;
      final total = params['total'];
      if (!value.isFinite ||
          (total is num && (!total.isFinite || total < 0 || value > total))) {
        return;
      }
      final previous = _activeProgress[token];
      // Ignore stale, unknown, or malformed updates. Progress is monotonic.
      if (previous == null || value <= previous) return;
      if (_progressTotals.containsKey(token) &&
          _progressTotals[token] != null &&
          (total is! num || total != _progressTotals[token])) {
        return;
      }
      _progressTotals[token] = total is num ? total : null;
      _activeProgress[token] = value;
      _progress.add(
        MCPProgressUpdate(
          progressToken: token,
          progress: value,
          total: total is num ? total : null,
          message: params['message']?.toString(),
        ),
      );
      return;
    }
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

  /// Progress updates for active requests that supplied a progress token.
  Stream<MCPProgressUpdate> get progress => _progress.stream;

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
    if (protocolMode == MCPProtocolMode.modern) {
      await _doModernDiscover();
      if (replayResourceSubscriptions) {
        await _replayActiveResourceSubscriptions();
      }
      return;
    }
    final response = await transport.send(
      JsonRpcRequest(
        method: 'initialize',
        id: _id,
        params: {
          'protocolVersion': legacyProtocolVersion,
          'capabilities': <String, dynamic>{},
          'clientInfo': {'name': 'ai_sdk_dart', 'version': '2.0.0'},
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
    if (protocolVersion != legacyProtocolVersion) {
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

  Future<void> _doModernDiscover() async {
    if (transport case final StreamableHttpClientTransport http) {
      http.setProtocolVersion(modernProtocolVersion);
    }
    final response = await transport.send(
      JsonRpcRequest(method: 'server/discover', id: _id, params: _modernMeta()),
    );
    if (response.isError) {
      throw MCPException('Modern server discovery failed: ${response.error}');
    }
    final result = response.result;
    if (result is! Map) {
      throw const MCPException('Modern server discovery returned no result');
    }
    final supported = result['supportedVersions'];
    if (supported is! List || supported.isEmpty) {
      throw const MCPException(
        'Modern server discovery result must contain supportedVersions',
      );
    }
    if (!supported
        .map((value) => value.toString())
        .contains(modernProtocolVersion)) {
      throw MCPException(
        'Modern server does not support $modernProtocolVersion '
        '(supported: ${supported.join(', ')})',
      );
    }
  }

  Map<String, dynamic> _modernMeta([Map<String, dynamic>? existing]) => {
    '_meta': {
      ...?existing,
      'io.modelcontextprotocol/protocolVersion': modernProtocolVersion,
      'io.modelcontextprotocol/clientCapabilities': <String, dynamic>{},
      'io.modelcontextprotocol/clientInfo': {
        'name': 'ai_sdk_dart',
        'version': '2.0.0',
      },
    },
  };

  JsonRpcRequest _modernRequest(JsonRpcRequest request) {
    final params = <String, dynamic>{
      ...?request.params,
      ..._modernMeta(
        request.params?['_meta'] is Map
            ? (request.params!['_meta'] as Map).cast<String, dynamic>()
            : null,
      ),
    };
    return JsonRpcRequest(
      method: request.method,
      id: request.id,
      params: params,
    );
  }

  Future<void> _replayActiveResourceSubscriptions() async {
    for (final entry in _resourceSubscriptions.entries.toList()) {
      final subscription = entry.value;
      if (subscription.isClosed) {
        continue;
      }
      final requestId = _id;
      final response = await _send(
        protocolMode == MCPProtocolMode.modern
            ? JsonRpcRequest(
                method: 'subscriptions/listen',
                id: requestId,
                params: {
                  'notifications': {
                    'resourceSubscriptions': [entry.key],
                  },
                },
              )
            : JsonRpcRequest(
                method: 'resources/subscribe',
                id: requestId,
                params: {'uri': entry.key},
              ),
      );
      if (response.isError) {
        throw MCPException(
          '${protocolMode == MCPProtocolMode.modern ? 'subscriptions/listen' : 'resources/subscribe'} "${entry.key}" failed: ${response.error}',
        );
      }
      if (protocolMode == MCPProtocolMode.modern) {
        _modernSubscriptionRequestIds[entry.key] = requestId;
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

  Future<JsonRpcResponse> _send(
    JsonRpcRequest request, {
    bool? retryOnTransportFailure,
  }) async {
    final policy = reconnectPolicy;
    final retrySafe =
        retryOnTransportFailure ??
        const {
          'tools/list',
          'prompts/list',
          'prompts/get',
          'resources/list',
          'resources/templates/list',
          'resources/read',
          'resources/subscribe',
          'resources/unsubscribe',
          'ping',
        }.contains(request.method);
    final maxAttempts = policy?.maxAttempts ?? 0;
    for (var attempt = 0; attempt <= maxAttempts; attempt++) {
      if (_closed) throw const MCPException('Client is closed');
      try {
        try {
          final wireRequest =
              protocolMode == MCPProtocolMode.modern && attempt > 0
              ? JsonRpcRequest(
                  method: request.method,
                  id: _id,
                  params: request.params,
                )
              : request;
          final wireResponse = await transport.send(
            protocolMode == MCPProtocolMode.modern
                ? _modernRequest(wireRequest)
                : wireRequest,
          );
          _validateModernResult(wireRequest, wireResponse);
          return wireResponse;
        } on MCPSessionExpiredException {
          await _recoverFromSessionExpiry();
          if (_closed) throw const MCPException('Client is closed');
          final recoveredRequest = protocolMode == MCPProtocolMode.modern
              ? JsonRpcRequest(
                  method: request.method,
                  id: _id,
                  params: request.params,
                )
              : request;
          final wireResponse = await transport.send(
            protocolMode == MCPProtocolMode.modern
                ? _modernRequest(recoveredRequest)
                : recoveredRequest,
          );
          _validateModernResult(recoveredRequest, wireResponse);
          return wireResponse;
        }
      } catch (error, stackTrace) {
        if (error is MCPSessionExpiredException) rethrow;
        // A malformed modern result was received successfully, so the
        // operation is not transport-ambiguous. Preserve its protocol error
        // instead of converting it into a tool replay warning.
        if (error is _MCPModernProtocolException) {
          rethrow;
        }
        if (request.method == 'tools/call' &&
            (!retrySafe || attempt >= maxAttempts)) {
          Error.throwWithStackTrace(
            MCPAmbiguousToolCompletionException(
              toolName: request.params?['name']?.toString() ?? '',
              requestId: request.id,
              cause: error,
            ),
            stackTrace,
          );
        }
        if (!retrySafe || attempt >= maxAttempts) rethrow;
        await _waitForReconnect(policy!.delayFor(attempt));
        if (_transportFactory != null) {
          await transport.close();
          if (_closed) throw const MCPException('Client is closed');
          transport = _transportFactory();
          _listenToTransport();
          _initialized = false;
          await _ensureInitialized(replayResourceSubscriptions: true);
        }
      }
    }
    throw const MCPException('Max reconnect attempts reached');
  }

  void _validateModernResult(JsonRpcRequest request, JsonRpcResponse response) {
    if (protocolMode != MCPProtocolMode.modern || response.isError) return;

    // `server/discover` predates the result envelope and advertises the
    // modern strategy before ordinary requests begin.
    if (request.method == 'server/discover') return;
    final result = response.result;
    if (result is! Map) {
      throw const _MCPModernProtocolException(
        'Modern MCP result must be an object with resultType',
      );
    }
    final resultType = result['resultType'];
    if (resultType != 'complete' && resultType != 'input_required') {
      throw const _MCPModernProtocolException(
        'Modern MCP result must contain resultType "complete" or '
        '"input_required"',
      );
    }
    if (resultType != 'input_required') return;

    const supportsInputRequired = {
      'prompts/get',
      'resources/read',
      'tools/call',
    };
    if (!supportsInputRequired.contains(request.method)) {
      throw _MCPModernProtocolException(
        'Modern MCP method ${request.method} cannot return input_required',
      );
    }
    final inputRequests = result['inputRequests'];
    final requestState = result['requestState'];
    if (inputRequests == null && requestState == null) {
      throw const _MCPModernProtocolException(
        'Modern input_required result must contain inputRequests or '
        'requestState',
      );
    }
    if (inputRequests != null && inputRequests is! Map) {
      throw const _MCPModernProtocolException(
        'Modern input_required inputRequests must be an object',
      );
    }
    if (requestState != null && requestState is! String) {
      throw const _MCPModernProtocolException(
        'Modern input_required requestState must be a string',
      );
    }
    if (inputRequests is Map) {
      const supportedInputRequestMethods = {
        'elicitation/create',
        'sampling/createMessage',
        'roots/list',
      };
      for (final entry in inputRequests.entries) {
        if (entry.key is! String || (entry.key as String).isEmpty) {
          throw const _MCPModernProtocolException(
            'Modern input_required request IDs must be non-empty strings',
          );
        }
        final inputRequest = entry.value;
        if (inputRequest is! Map ||
            inputRequest['method'] is! String ||
            !supportedInputRequestMethods.contains(inputRequest['method'])) {
          throw const _MCPModernProtocolException(
            'Modern input_required entries must be JSON-RPC requests',
          );
        }
      }
    }
  }

  Future<void> _waitForReconnect(Duration delay) async {
    final elapsed = Completer<void>();
    final timer = Timer(delay, elapsed.complete);
    try {
      await Future.any([elapsed.future, _closedSignal.future]);
    } finally {
      timer.cancel();
    }
    if (_closed) throw const MCPException('Client is closed');
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
  /// Set [retryOnTransportFailure] only when replay is safe for this operation.
  /// This requires a reconnect policy and does not provide exactly-once execution.
  Future<Object?> callTool(
    String name,
    Object? input, {
    bool retryOnTransportFailure = false,
    Map<String, dynamic>? inputResponses,
    Object? requestState,
    Object? progressToken,
  }) async {
    if (progressToken != null &&
        progressToken is! String &&
        progressToken is! int) {
      throw const MCPException('progressToken must be a string or integer');
    }
    if (progressToken != null && _activeProgress.containsKey(progressToken)) {
      throw const MCPException('progressToken is already active');
    }
    if (progressToken != null) {
      _activeProgress[progressToken] = -double.infinity;
      _progressTotals[progressToken] = null;
    }
    try {
      await initialize();
      final response = await _send(
        JsonRpcRequest(
          method: 'tools/call',
          id: _id,
          params: {
            'name': name,
            'arguments': input is Map ? input : {'value': input},
            ...?inputResponses == null
                ? null
                : {'inputResponses': inputResponses},
            ...?requestState == null ? null : {'requestState': requestState},
            if (progressToken != null)
              '_meta': {'progressToken': progressToken},
          },
        ),
        retryOnTransportFailure: retryOnTransportFailure,
      );
      if (response.isError) {
        throw MCPException('tools/call "$name" failed: ${response.error}');
      }
      final result = response.result;
      if (result is! Map) return result;
      if (result['resultType'] == 'input_required') {
        final requests = result['inputRequests'];
        final state = result['requestState'];
        if (requests is! Map && state == null) {
          throw const MCPException(
            'tools/call returned input_required without inputRequests or requestState',
          );
        }
        return MCPInputRequiredResult(
          inputRequests: requests is Map
              ? requests.cast<String, dynamic>()
              : const {},
          requestState: state,
          meta: result['_meta'] is Map
              ? (result['_meta'] as Map).cast<String, dynamic>()
              : null,
        );
      }
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
    } finally {
      if (progressToken != null) {
        // Let notifications already queued by the transport drain before the
        // token stops being associated with the request.
        scheduleMicrotask(() => _activeProgress.remove(progressToken));
        scheduleMicrotask(() => _progressTotals.remove(progressToken));
      }
    }
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
    if (protocolMode == MCPProtocolMode.modern) {
      final requestId = _id;
      final response = await _send(
        JsonRpcRequest(
          method: 'subscriptions/listen',
          id: requestId,
          params: {
            'notifications': {
              'resourceSubscriptions': [uri],
            },
          },
        ),
      );
      if (response.isError) {
        throw MCPException(
          'subscriptions/listen "$uri" failed: ${response.error}',
        );
      }
      _modernSubscriptionRequestIds[uri] = requestId;
      return;
    }
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
      if (protocolMode == MCPProtocolMode.modern) {
        final requestId = _modernSubscriptionRequestIds.remove(uri);
        if (requestId != null) {
          if (transport case final StreamableHttpClientTransport http) {
            await http.cancelSubscription(requestId);
          }
          await transport.sendNotification(
            JsonRpcNotification(
              method: 'notifications/cancelled',
              params: {
                'requestId': requestId,
                'reason': 'resource subscription cancelled',
              },
            ),
          );
        }
        return;
      }
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
    _closedSignal.complete();
    await _notificationSub?.cancel();
    for (final subscription in _resourceSubscriptions.values.toList()) {
      await subscription.close();
    }
    _resourceSubscriptions.clear();
    _resourceRefreshStates.clear();
    _activeProgress.clear();
    _progressTotals.clear();
    await _progress.close();
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
