import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'json_rpc.dart';

typedef MCPAccessTokenProvider = Future<String?> Function();

/// Host-owned authorization hooks. Token storage and browser login remain
/// outside the SDK; the transport only asks the host for a current token.
class MCPAuthConfiguration {
  MCPAuthConfiguration({
    required this.resource,
    this.issuer,
    this.accessToken,
    this.refreshAccessToken,
    this.retryAfterUnauthorized = false,
  }) {
    if (!resource.hasScheme || resource.host.isEmpty || resource.hasFragment) {
      throw ArgumentError.value(
        resource,
        'resource',
        'must be an absolute URI without a fragment',
      );
    }
    if (issuer != null && (!issuer!.hasScheme || issuer!.host.isEmpty)) {
      throw ArgumentError.value(issuer, 'issuer', 'must be an absolute URI');
    }
  }

  final Uri resource;
  final Uri? issuer;
  final MCPAccessTokenProvider? accessToken;
  final MCPAccessTokenProvider? refreshAccessToken;

  /// Explicitly opt into replaying a request after refresh. Keep false for
  /// mutating calls when a server could have executed before returning 401.
  final bool retryAfterUnauthorized;

  /// Validates RFC 9207 issuer binding before a host exchanges an auth code.
  void validateAuthorizationIssuer(
    String? responseIssuer, {
    required bool issuerParameterSupported,
  }) {
    if (issuerParameterSupported && responseIssuer == null) {
      throw const MCPException('Authorization response is missing issuer');
    }
    if (responseIssuer != null &&
        (issuer == null || responseIssuer != issuer.toString())) {
      throw const MCPException('Authorization response issuer mismatch');
    }
  }

  /// Accepts only HTTPS redirects or loopback HTTP redirects, without a
  /// fragment or embedded credentials.
  static Uri validateRedirectUri(Uri redirectUri) {
    final loopback =
        redirectUri.host == 'localhost' ||
        redirectUri.host == '127.0.0.1' ||
        redirectUri.host == '::1';
    if (redirectUri.userInfo.isNotEmpty ||
        redirectUri.hasFragment ||
        (redirectUri.scheme != 'https' &&
            !(redirectUri.scheme == 'http' && loopback))) {
      throw ArgumentError.value(
        redirectUri,
        'redirectUri',
        'must use HTTPS or loopback HTTP without credentials or fragments',
      );
    }
    return redirectUri;
  }

  void validateProtectedResource(MCPProtectedResourceMetadata metadata) {
    if (metadata.resource != resource) {
      throw const MCPException('Protected resource metadata resource mismatch');
    }
    if (issuer != null && !metadata.authorizationServers.contains(issuer)) {
      throw const MCPException(
        'Protected resource metadata authorization server mismatch',
      );
    }
  }
}

class MCPProtectedResourceMetadata {
  const MCPProtectedResourceMetadata({
    required this.resource,
    required this.authorizationServers,
    this.scopesSupported = const [],
  });

  final Uri resource;
  final List<Uri> authorizationServers;
  final List<String> scopesSupported;

  factory MCPProtectedResourceMetadata.fromJson(Map<String, dynamic> json) {
    final resource = _metadataUri(json['resource']);
    final serverValues = json['authorization_servers'];
    final scopes = json['scopes_supported'];
    if (serverValues is! List ||
        serverValues.isEmpty ||
        (scopes != null &&
            (scopes is! List || scopes.any((item) => item is! String)))) {
      throw const MCPException('Invalid protected resource metadata');
    }
    final servers = serverValues.map(_metadataUri).toList();

    return MCPProtectedResourceMetadata(
      resource: resource,
      authorizationServers: List.unmodifiable(servers),
      scopesSupported: List.unmodifiable(
        (scopes as List?)?.cast<String>() ?? const <String>[],
      ),
    );
  }
}

class MCPAuthorizationServerMetadata {
  const MCPAuthorizationServerMetadata({
    required this.issuer,
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    this.authorizationResponseIssuerSupported = false,
  });

  final Uri issuer;
  final Uri authorizationEndpoint;
  final Uri tokenEndpoint;
  final bool authorizationResponseIssuerSupported;

  factory MCPAuthorizationServerMetadata.fromJson(
    Map<String, dynamic> json,
    Uri expectedIssuer,
  ) {
    final issuer = _metadataUri(json['issuer']);
    final authorization = _metadataUri(json['authorization_endpoint']);
    final token = _metadataUri(json['token_endpoint']);
    if (json['issuer'] != expectedIssuer.toString() || issuer.hasQuery) {
      throw const MCPException('Invalid authorization server metadata');
    }

    return MCPAuthorizationServerMetadata(
      issuer: issuer,
      authorizationEndpoint: authorization,
      tokenEndpoint: token,
      authorizationResponseIssuerSupported:
          json['authorization_response_iss_parameter_supported'] == true,
    );
  }
}

Uri _metadataUri(Object? value) {
  final uri = value is String ? Uri.tryParse(value) : null;
  final loopback =
      uri != null && const {'localhost', '127.0.0.1', '::1'}.contains(uri.host);
  if (uri == null ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment ||
      (uri.scheme != 'https' && !(uri.scheme == 'http' && loopback))) {
    throw const MCPException('Invalid authorization metadata URI');
  }
  return uri;
}

/// Fetches RFC 9728 protected-resource metadata and RFC 8414/OIDC metadata.
/// The host owns the HTTP client and any resulting credentials.
class MCPAuthDiscovery {
  /// Discovers protected-resource metadata for the requested MCP resource.
  ///
  /// A `resource_metadata` URL in a Bearer challenge wins. Without one, RFC
  /// 9728 path-insertion discovery is attempted before the origin-level
  /// fallback. Metadata requests intentionally contain no Authorization
  /// header; credentials belong to the host's authorization flow.
  static Future<MCPProtectedResourceMetadata> discoverProtectedResource(
    Uri resource, {
    String? wwwAuthenticate,
    http.Client? client,
  }) async {
    _validateResourceUri(resource);
    final metadataFromHeader = _resourceMetadataUrl(wwwAuthenticate);
    final candidates = metadataFromHeader == null
        ? _protectedResourceCandidates(resource)
        : [metadataFromHeader];
    MCPException? lastError;
    for (final candidate in candidates) {
      try {
        final metadata = await protectedResource(candidate, client: client);
        if (metadata.resource != resource) {
          throw const MCPException(
            'Protected resource metadata resource mismatch',
          );
        }
        return metadata;
      } on MCPException catch (error) {
        lastError = error;
        if (metadataFromHeader != null) rethrow;
      }
    }
    throw lastError ??
        const MCPException('Protected resource metadata unavailable');
  }

  static Future<MCPProtectedResourceMetadata> protectedResource(
    Uri metadataUri, {
    http.Client? client,
  }) async {
    final owns = client == null;
    final httpClient = client ?? http.Client();
    try {
      final response = await httpClient.get(
        metadataUri,
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode != 200) {
        throw MCPException(
          'Protected resource metadata failed: HTTP ${response.statusCode}',
        );
      }
      final body = jsonDecode(response.body);
      if (body is! Map) {
        throw const MCPException('Invalid protected resource metadata');
      }
      return MCPProtectedResourceMetadata.fromJson(
        body.cast<String, dynamic>(),
      );
    } finally {
      if (owns) httpClient.close();
    }
  }

  static Future<MCPAuthorizationServerMetadata> authorizationServer(
    Uri issuer, {
    http.Client? client,
  }) async {
    final owns = client == null;
    final httpClient = client ?? http.Client();
    try {
      _metadataUri(issuer.toString());
      if (issuer.hasQuery) {
        throw const MCPException('Issuer must not contain a query');
      }
      final issuerPath = issuer.path == '/' ? '' : issuer.path;
      final paths = <String>{
        '/.well-known/oauth-authorization-server$issuerPath',
        '/.well-known/openid-configuration$issuerPath',
        if (issuerPath.isNotEmpty)
          '${issuerPath.endsWith('/') ? issuerPath.substring(0, issuerPath.length - 1) : issuerPath}/.well-known/openid-configuration',
      };
      http.Response? response;
      for (final path in paths) {
        final candidate = issuer.replace(path: path, query: '', fragment: '');
        final attempt = await httpClient.get(
          candidate,
          headers: {'Accept': 'application/json'},
        );
        if (attempt.statusCode == 200) {
          response = attempt;
          break;
        }
      }
      if (response == null) {
        throw const MCPException('Authorization server metadata unavailable');
      }
      final body = jsonDecode(response.body);
      if (body is! Map) {
        throw const MCPException('Invalid authorization server metadata');
      }
      return MCPAuthorizationServerMetadata.fromJson(
        body.cast<String, dynamic>(),
        issuer,
      );
    } finally {
      if (owns) httpClient.close();
    }
  }
}

void _validateResourceUri(Uri resource) {
  final loopback = const {
    'localhost',
    '127.0.0.1',
    '::1',
  }.contains(resource.host);
  if (!resource.hasScheme ||
      resource.host.isEmpty ||
      resource.hasFragment ||
      (resource.scheme != 'https' &&
          !(resource.scheme == 'http' && loopback))) {
    throw const MCPException(
      'Protected resource must use HTTPS or loopback HTTP without a fragment',
    );
  }
}

List<Uri> _protectedResourceCandidates(Uri resource) {
  final path = resource.path.isEmpty ? '/' : resource.path;
  final insertion = path == '/'
      ? '/.well-known/oauth-protected-resource'
      : '/.well-known/oauth-protected-resource$path';
  final root = '/.well-known/oauth-protected-resource';
  return [
    resource.replace(path: insertion, query: '', fragment: ''),
    if (insertion != root)
      resource.replace(path: root, query: '', fragment: ''),
  ];
}

Uri? _resourceMetadataUrl(String? header) {
  if (header == null || header.trim().isEmpty) return null;
  Uri? found;
  String? scheme;
  final parameters = <String, String>{};
  void finishChallenge() {
    if (scheme?.toLowerCase() != 'bearer') return;
    final value = parameters['resource_metadata'];
    if (value == null) return;
    final uri = _metadataUri(value);
    if (found != null && found != uri) {
      throw const MCPException('Ambiguous resource_metadata challenges');
    }
    found = uri;
  }

  for (final segment in _splitAuthenticateChallenges(header)) {
    final match = RegExp(
      r'^([A-Za-z][A-Za-z0-9_-]*)\s+(.*)$',
    ).firstMatch(segment);
    if (match != null) {
      finishChallenge();
      scheme = match.group(1);
      parameters.clear();
      parameters.addAll(_parseChallengeParameters(match.group(2)!));
    } else {
      if (scheme == null) {
        throw const MCPException('Malformed WWW-Authenticate challenge');
      }
      final additional = _parseChallengeParameters(segment);
      if (additional.keys.any(parameters.containsKey)) {
        throw const MCPException('Duplicate WWW-Authenticate parameter');
      }
      parameters.addAll(additional);
    }
  }
  finishChallenge();
  return found;
}

List<String> _splitAuthenticateChallenges(String header) {
  final parts = <String>[];
  var start = 0;
  var quoted = false;
  var escaped = false;
  for (var i = 0; i < header.length; i++) {
    final char = header[i];
    if (escaped) {
      escaped = false;
    } else if (quoted && char == '\\') {
      escaped = true;
    } else if (char == '"') {
      quoted = !quoted;
    } else if (char == ',' && !quoted) {
      parts.add(header.substring(start, i).trim());
      start = i + 1;
    }
  }
  if (quoted || escaped) {
    throw const MCPException('Malformed WWW-Authenticate header');
  }
  final tail = header.substring(start).trim();
  if (tail.isNotEmpty) parts.add(tail);
  return parts;
}

Map<String, String> _parseChallengeParameters(String value) {
  final result = <String, String>{};
  if (value.isEmpty) return result;
  for (final parameter in _splitCommaValues(value)) {
    final equals = parameter.indexOf('=');
    if (equals <= 0) {
      throw const MCPException('Malformed WWW-Authenticate parameter');
    }
    final key = parameter.substring(0, equals).trim().toLowerCase();
    var raw = parameter.substring(equals + 1).trim();
    if (raw.isEmpty) {
      throw const MCPException('Malformed WWW-Authenticate value');
    }
    if (raw.startsWith('"')) {
      if (!raw.endsWith('"') || raw.length < 2) {
        throw const MCPException('Malformed WWW-Authenticate quoted value');
      }
      final buffer = StringBuffer();
      var escaped = false;
      for (final char in raw.substring(1, raw.length - 1).split('')) {
        if (escaped) {
          buffer.write(char);
          escaped = false;
        } else if (char == '\\') {
          escaped = true;
        } else {
          buffer.write(char);
        }
      }
      if (escaped) {
        throw const MCPException('Malformed WWW-Authenticate escape');
      }
      raw = buffer.toString();
    } else if (!RegExp(r"^[A-Za-z0-9!#$%&'*+\-.^_`|~]+$").hasMatch(raw)) {
      throw const MCPException('Malformed WWW-Authenticate token');
    }
    if (result.containsKey(key)) {
      throw const MCPException('Duplicate WWW-Authenticate parameter');
    }
    result[key] = raw;
  }
  return result;
}

List<String> _splitCommaValues(String value) {
  final parts = <String>[];
  var start = 0;
  var quoted = false;
  var escaped = false;
  for (var i = 0; i < value.length; i++) {
    final char = value[i];
    if (escaped) {
      escaped = false;
    } else if (quoted && char == '\\') {
      escaped = true;
    } else if (char == '"') {
      quoted = !quoted;
    } else if (char == ',' && !quoted) {
      parts.add(value.substring(start, i).trim());
      start = i + 1;
    }
  }
  if (quoted || escaped) {
    throw const MCPException('Malformed WWW-Authenticate parameter');
  }
  parts.add(value.substring(start).trim());
  return parts;
}

/// Streamable HTTP transport for MCP legacy and modern protocol eras.
///
/// This transport uses a single HTTP endpoint for POST, GET, and DELETE. It
/// supports:
/// - JSON or SSE responses to POSTed JSON-RPC requests
/// - optional server-push notifications over a GET SSE listener
/// - session IDs via `Mcp-Session-Id`
/// - negotiated protocol version headers on post-initialize requests
class StreamableHttpClientTransport implements MCPTransport {
  StreamableHttpClientTransport({
    required this.url,
    this.headers,
    this.requestTimeout = const Duration(seconds: 30),
    this.listenerReconnectDelay = const Duration(milliseconds: 250),
    this.auth,
    http.Client? client,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final Uri url;
  final Map<String, String>? headers;
  final Duration requestTimeout;
  final Duration listenerReconnectDelay;
  final MCPAuthConfiguration? auth;

  final http.Client _client;
  final bool _ownsClient;
  final _notifications = StreamController<Map<String, dynamic>>.broadcast();

  static const _maxBufferedResponseChars = 1024 * 1024;

  StreamSubscription<_SseEvent>? _listenerSubscription;
  final _subscriptionStreams = <int, StreamSubscription<_SseEvent>>{};
  Timer? _listenerReconnectTimer;
  bool _listenerConnecting = false;
  bool _listenerStarted = false;
  bool _listenerUnsupported = false;

  String? _sessionId;
  String? _pendingSessionId;
  String? _protocolVersion;
  String? _lastEventId;
  bool _sessionExpired = false;
  bool _closed = false;
  Future<String?>? _refreshFuture;

  @override
  Stream<Map<String, dynamic>> get notifications => _notifications.stream;

  /// Called by [MCPClient] after initialize negotiation succeeds.
  void setProtocolVersion(String protocolVersion) {
    if (protocolVersion == '2026-07-28') {
      // Modern MCP has no protocol-level session. Ignore any accidental
      // session header from a dual-era server.
      _sessionId = null;
      _pendingSessionId = null;
    }
    _sessionId = _pendingSessionId;
    _pendingSessionId = null;
    _protocolVersion = protocolVersion;
    _sessionExpired = false;
  }

  bool get _modern => _protocolVersion == '2026-07-28';

  Future<void> resetHandshakeState() async {
    _pendingSessionId = null;
    _sessionId = null;
    _protocolVersion = null;
    _lastEventId = null;
    _sessionExpired = false;
    _listenerStarted = false;
    _listenerUnsupported = false;
    await _stopListener();
  }

  /// Called by [MCPClient] after `notifications/initialized` is sent.
  Future<void> startNotificationListener() async {
    if (_closed || _listenerUnsupported || _listenerStarted) {
      return;
    }
    _listenerStarted = true;
    unawaited(_ensureListenerRunning());
  }

  Map<String, String> _baseHeaders() => {...?headers};

  Map<String, String> _postHeaders({required bool includeSessionAndVersion}) {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/event-stream',
      ..._baseHeaders(),
      if (includeSessionAndVersion && _protocolVersion != null)
        'MCP-Protocol-Version': _protocolVersion!,
      if (includeSessionAndVersion && _sessionId != null)
        'Mcp-Session-Id': _sessionId!,
    };
  }

  Map<String, String> _modernPostHeaders(JsonRpcRequest request) {
    final name = request.params?['name'] ?? request.params?['uri'];
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/event-stream',
      ..._baseHeaders(),
      'MCP-Protocol-Version': _protocolVersion!,
      'Mcp-Method': request.method,
      if (name is String && name.isNotEmpty)
        'Mcp-Name': _encodeHeaderValue(name),
    };
  }

  String _encodeHeaderValue(String value) {
    if (value.codeUnits.every((unit) => unit >= 0x20 && unit <= 0x7e)) {
      return value;
    }
    return '=?base64?${base64Encode(utf8.encode(value))}?=';
  }

  Map<String, String> _getHeaders() {
    return {
      'Accept': 'text/event-stream',
      ..._baseHeaders(),
      'MCP-Protocol-Version': ?_protocolVersion,
      'Mcp-Session-Id': ?_sessionId,
      'Last-Event-ID': ?_lastEventId,
    };
  }

  Map<String, String> _deleteHeaders() {
    return {
      ..._baseHeaders(),
      'MCP-Protocol-Version': ?_protocolVersion,
      'Mcp-Session-Id': ?_sessionId,
    };
  }

  String? _responseHeader(Map<String, String> headers, String name) {
    return headers[name] ?? headers[name.toLowerCase()];
  }

  bool _isJsonContentType(String? contentType) {
    return contentType != null &&
        contentType.toLowerCase().startsWith('application/json');
  }

  bool _isSseContentType(String? contentType) {
    return contentType != null &&
        contentType.toLowerCase().startsWith('text/event-stream');
  }

  String? _safeResponseContext(String responseBody) {
    if (responseBody.trim().isEmpty) {
      return 'empty response body';
    }
    return null;
  }

  MCPTransportException _transportError({
    required String method,
    required Uri uri,
    int? statusCode,
    String? context,
  }) {
    return MCPTransportException(
      method: method,
      uri: uri,
      statusCode: statusCode,
      context: context,
    );
  }

  MCPSessionExpiredException _sessionExpiredError({
    required String method,
    required Uri uri,
  }) {
    return MCPSessionExpiredException(
      method: method,
      uri: uri,
      statusCode: 404,
      context: 'session expired',
    );
  }

  void _ensureOpen() {
    if (_closed) {
      throw const MCPException('Streamable HTTP transport is closed');
    }
  }

  void _ensureSessionUsable(String method) {
    if (_sessionExpired) {
      throw _sessionExpiredError(method: method, uri: url);
    }
  }

  void _capturePendingSessionId(http.StreamedResponse response) {
    final sessionId = _responseHeader(response.headers, 'mcp-session-id');
    if (sessionId == null) {
      _pendingSessionId = null;
      return;
    }
    if (!_isVisibleAscii(sessionId)) {
      throw const MCPException(
        'Invalid Mcp-Session-Id header: expected visible ASCII characters only',
      );
    }
    _pendingSessionId = sessionId;
  }

  bool _isVisibleAscii(String value) {
    if (value.isEmpty) {
      return false;
    }
    for (final codeUnit in value.codeUnits) {
      if (codeUnit < 0x21 || codeUnit > 0x7e) {
        return false;
      }
    }
    return true;
  }

  void _markSessionExpired() {
    _pendingSessionId = null;
    _sessionExpired = true;
    _listenerStarted = false;
    _listenerUnsupported = false;
    _lastEventId = null;
    unawaited(_stopListener());
  }

  Future<http.StreamedResponse> _sendRequest(http.BaseRequest request) async {
    try {
      final token = await auth?.accessToken?.call();
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      var response = await _client.send(request).timeout(requestTimeout);
      if (response.statusCode == 401 &&
          auth?.refreshAccessToken != null &&
          auth?.retryAfterUnauthorized == true) {
        await response.stream.drain<void>();
        final refreshed = await _refreshAccessToken();
        if (refreshed != null &&
            refreshed.isNotEmpty &&
            request is http.Request) {
          final retry = http.Request(request.method, request.url)
            ..headers.addAll(request.headers)
            ..body = request.body;
          retry.headers['Authorization'] = 'Bearer $refreshed';
          response = await _client.send(retry).timeout(requestTimeout);
        }
      }
      return response;
    } catch (error) {
      throw _transportError(
        method: request.method,
        uri: request.url,
        context: error.runtimeType.toString(),
      );
    }
  }

  Future<String?> _refreshAccessToken() async {
    final active = _refreshFuture;
    if (active != null) return active;

    final refresh = auth!.refreshAccessToken!.call();
    _refreshFuture = refresh;
    try {
      return await refresh;
    } finally {
      if (identical(_refreshFuture, refresh)) {
        _refreshFuture = null;
      }
    }
  }

  Future<http.StreamedResponse> _post(
    Map<String, dynamic> body, {
    required bool includeSessionAndVersion,
  }) async {
    final request = http.Request('POST', url);
    request.headers.addAll(
      _postHeaders(includeSessionAndVersion: includeSessionAndVersion),
    );
    request.body = jsonEncode(body);
    return _sendRequest(request);
  }

  Future<void> _drainResponse(http.StreamedResponse response) async {
    await response.stream.drain<void>();
  }

  Future<JsonRpcResponse> _parseJsonResponse(
    http.StreamedResponse response, {
    required int expectedId,
  }) async {
    final bodyText = await _readBoundedResponseBody(response, method: 'POST');
    final decoded = jsonDecode(bodyText);
    if (decoded is! Map) {
      throw MCPException('Unexpected MCP response format: $decoded');
    }
    final message = decoded.cast<String, dynamic>();
    _validateResponseMessage(message, expectedId: expectedId);
    return JsonRpcResponse.fromJson(message);
  }

  Future<String> _readBoundedResponseBody(
    http.StreamedResponse response, {
    required String method,
  }) async {
    final buffer = StringBuffer();
    await for (final chunk in response.stream.transform(utf8.decoder)) {
      if (buffer.length + chunk.length > _maxBufferedResponseChars) {
        throw MCPTransportException(
          method: method,
          uri: url,
          statusCode: response.statusCode,
          context:
              'response body exceeded $_maxBufferedResponseChars characters',
        );
      }
      buffer.write(chunk);
    }
    return buffer.toString();
  }

  void _dispatchMessage(Map<String, dynamic> message) {
    if (_notifications.isClosed) {
      return;
    }
    _notifications.add(message);
  }

  Future<JsonRpcResponse> _parseSseResponse(
    http.StreamedResponse response,
    JsonRpcRequest request,
  ) async {
    final completer = Completer<JsonRpcResponse>();
    unawaited(completer.future.then<void>((_) {}, onError: (_, _) {}));

    late final StreamSubscription<_SseEvent> subscription;
    subscription = _parseSse(response.stream).listen(
      (event) {
        final data = event.data.trim();
        if (data.isEmpty) {
          return;
        }
        Object? decoded;
        try {
          decoded = jsonDecode(data);
        } catch (_) {
          return;
        }
        if (decoded is! Map) {
          return;
        }
        final message = decoded.cast<String, dynamic>();
        if (request.method == 'subscriptions/listen' &&
            message['method'] == 'notifications/subscriptions/acknowledged') {
          if (!completer.isCompleted) {
            _subscriptionStreams[request.id] = subscription;
            completer.complete(
              JsonRpcResponse(
                id: request.id,
                result: const {'resultType': 'complete'},
              ),
            );
          }
          _dispatchMessage(message);
          return;
        }
        final isResponseLike =
            message.containsKey('result') || message.containsKey('error');
        if (isResponseLike) {
          try {
            _validateResponseMessage(message, expectedId: request.id);
            if (!completer.isCompleted) {
              completer.complete(JsonRpcResponse.fromJson(message));
            }
          } catch (error, stackTrace) {
            if (!completer.isCompleted) {
              completer.completeError(error, stackTrace);
            }
          }
          if (request.method == 'subscriptions/listen') {
            _subscriptionStreams[request.id] = subscription;
          } else {
            unawaited(subscription.cancel());
          }
          return;
        }
        _dispatchMessage(message);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(
            MCPException('SSE response stream error: $error'),
            stackTrace,
          );
        }
      },
      onDone: () {
        _subscriptionStreams.remove(request.id);
        if (!completer.isCompleted) {
          completer.completeError(
            MCPException(
              'SSE response stream closed before responding to ${request.method}',
            ),
          );
        }
      },
      cancelOnError: false,
    );

    return completer.future.timeout(
      requestTimeout,
      onTimeout: () {
        unawaited(subscription.cancel());
        if (!_modern) {
          unawaited(
            _sendCancelledNotification(
              request.id,
              'Request timed out after ${requestTimeout.inMilliseconds}ms',
            ),
          );
        }
        throw MCPException(
          'Request timed out waiting for ${request.method} response',
        );
      },
    );
  }

  /// Stops a modern `subscriptions/listen` response stream.
  Future<void> cancelSubscription(int requestId) async {
    final subscription = _subscriptionStreams.remove(requestId);
    await subscription?.cancel();
  }

  Future<void> _sendCancelledNotification(int requestId, String reason) async {
    if (_closed || _sessionExpired) {
      return;
    }
    try {
      await sendNotification(
        JsonRpcNotification(
          method: 'notifications/cancelled',
          params: {'requestId': requestId, 'reason': reason},
        ),
      );
    } catch (_) {
      // Cancellation is best-effort; timeout callers must still return promptly.
    }
  }

  @override
  Future<JsonRpcResponse> send(JsonRpcRequest request) async {
    _ensureOpen();
    if (_modern) {
      final response = await _postModern(request);
      return response;
    }
    final isInitialize = request.method == 'initialize';
    if (!isInitialize) {
      _ensureSessionUsable('POST');
    }

    final response = await _post(
      request.toJson(),
      includeSessionAndVersion: !isInitialize,
    );

    if (!isInitialize && _sessionId != null && response.statusCode == 404) {
      await _drainResponse(response);
      _markSessionExpired();
      throw _sessionExpiredError(method: 'POST', uri: url);
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final bodyText = await _readBoundedResponseBody(response, method: 'POST');
      throw _transportError(
        method: 'POST',
        uri: url,
        statusCode: response.statusCode,
        context: _safeResponseContext(bodyText),
      );
    }

    if (isInitialize) {
      _capturePendingSessionId(response);
    }

    final contentType = _responseHeader(response.headers, 'content-type');
    if (_isJsonContentType(contentType)) {
      return _parseJsonResponse(response, expectedId: request.id);
    }
    if (_isSseContentType(contentType)) {
      return _parseSseResponse(response, request);
    }

    await _drainResponse(response);
    throw MCPException(
      'Unexpected MCP response Content-Type: ${contentType ?? 'missing'}',
    );
  }

  Future<JsonRpcResponse> _postModern(JsonRpcRequest request) async {
    final httpRequest = http.Request('POST', url)
      ..headers.addAll(_modernPostHeaders(request))
      ..body = jsonEncode(request.toJson());
    final response = await _sendRequest(httpRequest);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final bodyText = await _readBoundedResponseBody(response, method: 'POST');
      throw _transportError(
        method: 'POST',
        uri: url,
        statusCode: response.statusCode,
        context: _safeResponseContext(bodyText),
      );
    }
    final contentType = _responseHeader(response.headers, 'content-type');
    if (_isJsonContentType(contentType)) {
      return _parseJsonResponse(response, expectedId: request.id);
    }
    if (_isSseContentType(contentType)) {
      return _parseSseResponse(response, request);
    }
    await _drainResponse(response);
    throw MCPException(
      'Unexpected MCP response Content-Type: ${contentType ?? 'missing'}',
    );
  }

  @override
  Future<void> sendNotification(JsonRpcNotification notification) async {
    _ensureOpen();
    if (_modern) {
      final request = JsonRpcRequest(
        method: notification.method,
        id: 0,
        params: notification.params,
      );
      final httpRequest = http.Request('POST', url)
        ..headers.addAll(_modernPostHeaders(request))
        ..body = jsonEncode(notification.toJson());
      final response = await _sendRequest(httpRequest);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final bodyText = await _readBoundedResponseBody(
          response,
          method: 'POST',
        );
        throw _transportError(
          method: 'POST',
          uri: url,
          statusCode: response.statusCode,
          context: _safeResponseContext(bodyText),
        );
      }
      await _drainResponse(response);
      return;
    }
    _ensureSessionUsable('POST');

    final response = await _post(
      notification.toJson(),
      includeSessionAndVersion: true,
    );

    if (_sessionId != null && response.statusCode == 404) {
      await _drainResponse(response);
      _markSessionExpired();
      throw _sessionExpiredError(method: 'POST', uri: url);
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final bodyText = await _readBoundedResponseBody(response, method: 'POST');
      throw _transportError(
        method: 'POST',
        uri: url,
        statusCode: response.statusCode,
        context: _safeResponseContext(bodyText),
      );
    }

    await _drainResponse(response);
  }

  Future<void> _ensureListenerRunning() async {
    if (_closed ||
        !_listenerStarted ||
        _listenerUnsupported ||
        _listenerConnecting ||
        _listenerSubscription != null ||
        _sessionExpired ||
        _sessionId == null ||
        _protocolVersion == null) {
      return;
    }

    _listenerConnecting = true;
    try {
      final request = http.Request('GET', url);
      request.headers.addAll(_getHeaders());
      final response = await _sendRequest(request);

      if (_closed || !_listenerStarted) {
        await _drainResponse(response);
        return;
      }

      if (_sessionId != null && response.statusCode == 404) {
        await _drainResponse(response);
        _markSessionExpired();
        if (!_notifications.isClosed) {
          _notifications.addError(
            _sessionExpiredError(method: 'GET', uri: url),
          );
        }
        return;
      }

      if (response.statusCode == 405) {
        await _drainResponse(response);
        _listenerUnsupported = true;
        _listenerStarted = false;
        return;
      }

      final contentType = _responseHeader(response.headers, 'content-type');
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          !_isSseContentType(contentType)) {
        await _drainResponse(response);
        _scheduleListenerReconnect();
        return;
      }

      _listenerSubscription = _parseSse(response.stream).listen(
        _handleListenerEvent,
        onError: (_, _) {
          _listenerSubscription = null;
          _scheduleListenerReconnect();
        },
        onDone: () {
          _listenerSubscription = null;
          _scheduleListenerReconnect();
        },
        cancelOnError: false,
      );
    } catch (_) {
      _scheduleListenerReconnect();
    } finally {
      _listenerConnecting = false;
    }
  }

  void _handleListenerEvent(_SseEvent event) {
    if (event.id != null && event.id!.isNotEmpty) {
      _lastEventId = event.id;
    }

    final data = event.data.trim();
    if (data.isEmpty) {
      return;
    }

    Object? decoded;
    try {
      decoded = jsonDecode(data);
    } catch (_) {
      return;
    }
    if (decoded is! Map) {
      return;
    }
    _dispatchMessage(decoded.cast<String, dynamic>());
  }

  void _scheduleListenerReconnect() {
    if (_closed ||
        !_listenerStarted ||
        _listenerUnsupported ||
        _sessionExpired ||
        _listenerReconnectTimer != null) {
      return;
    }
    _listenerReconnectTimer = Timer(listenerReconnectDelay, () {
      _listenerReconnectTimer = null;
      unawaited(_ensureListenerRunning());
    });
  }

  Future<void> _stopListener() async {
    _listenerReconnectTimer?.cancel();
    _listenerReconnectTimer = null;
    final subscription = _listenerSubscription;
    _listenerSubscription = null;
    await subscription?.cancel();
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;

    Object? closeError;
    await _stopListener();
    for (final subscription in _subscriptionStreams.values.toList()) {
      await subscription.cancel();
    }
    _subscriptionStreams.clear();

    if (!_modern &&
        _sessionId != null &&
        !_sessionExpired &&
        _protocolVersion != null) {
      final request = http.Request('DELETE', url);
      request.headers.addAll(_deleteHeaders());
      try {
        final response = await _sendRequest(request);
        if (!((response.statusCode >= 200 && response.statusCode < 300) ||
            response.statusCode == 405)) {
          final bodyText = await _readBoundedResponseBody(
            response,
            method: 'DELETE',
          );
          closeError = _transportError(
            method: 'DELETE',
            uri: url,
            statusCode: response.statusCode,
            context: _safeResponseContext(bodyText),
          );
        } else {
          await _drainResponse(response);
        }
      } catch (error) {
        closeError = error;
      }
    }

    _sessionId = null;
    _pendingSessionId = null;
    _protocolVersion = null;
    _lastEventId = null;
    _sessionExpired = false;
    if (!_notifications.isClosed) {
      await _notifications.close();
    }
    if (_ownsClient) {
      _client.close();
    }
    if (closeError != null) {
      throw closeError;
    }
  }

  Stream<_SseEvent> _parseSse(Stream<List<int>> byteStream) {
    return Stream<_SseEvent>.eventTransformed(
      byteStream
          .transform(utf8.decoder)
          .transform(const _BoundedLineSplitter()),
      (sink) => _SseLineSink(sink),
    );
  }

  void _validateResponseMessage(
    Map<String, dynamic> message, {
    required int expectedId,
  }) {
    if (message['jsonrpc'] != '2.0') {
      throw MCPException('Unexpected JSON-RPC response format: $message');
    }

    final hasResult = message.containsKey('result');
    final hasError = message.containsKey('error');
    if (hasResult == hasError) {
      throw MCPException('Unexpected JSON-RPC response format: $message');
    }

    if (message['id'] != expectedId) {
      throw MCPException(
        'Unexpected JSON-RPC response id: ${message['id']} (expected $expectedId)',
      );
    }
  }
}

class _SseEvent {
  _SseEvent({required this.event, required this.data, this.id});

  final String event;
  final String data;
  final String? id;
}

class _SseLineSink implements EventSink<String> {
  _SseLineSink(this._out);

  final EventSink<_SseEvent> _out;
  String _event = '';
  String? _id;
  final _dataLines = <String>[];
  bool _hasEvent = false;
  bool _hasData = false;
  bool _hasId = false;
  int _bufferedChars = 0;

  @override
  void add(String line) {
    if (line.isEmpty) {
      _flush();
      return;
    }
    if (line.startsWith(':')) {
      return;
    }

    final separator = line.indexOf(':');
    final field = separator == -1 ? line : line.substring(0, separator);
    var value = separator == -1 ? '' : line.substring(separator + 1);
    if (value.startsWith(' ')) {
      value = value.substring(1);
    }

    switch (field) {
      case 'event':
        _bufferedChars -= _event.length;
        _event = value;
        _checkBuffer(value.length);
        _hasEvent = true;
      case 'data':
        if (_hasData) {
          _checkBuffer(1);
        }
        _checkBuffer(value.length);
        _dataLines.add(value);
        _hasData = true;
      case 'id':
        _bufferedChars -= _id?.length ?? 0;
        _id = value;
        _checkBuffer(value.length);
        _hasId = true;
      default:
        break;
    }
  }

  void _flush() {
    if (!_hasEvent && !_hasData && !_hasId) {
      return;
    }
    _out.add(_SseEvent(event: _event, data: _dataLines.join('\n'), id: _id));
    _event = '';
    _id = null;
    _dataLines.clear();
    _hasEvent = false;
    _hasData = false;
    _hasId = false;
    _bufferedChars = 0;
  }

  void _checkBuffer(int additionalChars) {
    _bufferedChars += additionalChars;
    if (_bufferedChars >
        StreamableHttpClientTransport._maxBufferedResponseChars) {
      throw MCPException(
        'SSE event exceeded '
        '${StreamableHttpClientTransport._maxBufferedResponseChars} characters',
      );
    }
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _out.addError(error, stackTrace);
  }

  @override
  void close() {
    _flush();
    _out.close();
  }
}

class _BoundedLineSplitter extends StreamTransformerBase<String, String> {
  const _BoundedLineSplitter();

  @override
  Stream<String> bind(Stream<String> stream) {
    final line = StringBuffer();
    var pendingCarriageReturn = false;
    return stream.transform(
      StreamTransformer<String, String>.fromHandlers(
        handleData: (chunk, sink) {
          for (var index = 0; index < chunk.length; index++) {
            final character = chunk[index];
            if (pendingCarriageReturn) {
              pendingCarriageReturn = false;
              if (character == '\n') {
                continue;
              }
            }

            if (character == '\r' || character == '\n') {
              sink.add(line.toString());
              line.clear();
              pendingCarriageReturn = character == '\r';
              continue;
            }

            line.write(character);
            if (line.length >
                StreamableHttpClientTransport._maxBufferedResponseChars) {
              throw MCPException(
                'SSE line exceeded '
                '${StreamableHttpClientTransport._maxBufferedResponseChars} characters',
              );
            }
          }
        },
        handleDone: (sink) {
          if (line.isNotEmpty) {
            sink.add(line.toString());
          }
          sink.close();
        },
      ),
    );
  }
}
