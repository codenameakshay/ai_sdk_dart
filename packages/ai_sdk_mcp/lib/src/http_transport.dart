import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'json_rpc.dart';

/// Streamable HTTP transport for MCP 2025-06-18.
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
    http.Client? client,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final Uri url;
  final Map<String, String>? headers;
  final Duration requestTimeout;
  final Duration listenerReconnectDelay;

  final http.Client _client;
  final bool _ownsClient;
  final _notifications = StreamController<Map<String, dynamic>>.broadcast();

  static const _maxBufferedResponseChars = 1024 * 1024;

  StreamSubscription<_SseEvent>? _listenerSubscription;
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

  @override
  Stream<Map<String, dynamic>> get notifications => _notifications.stream;

  /// Called by [MCPClient] after initialize negotiation succeeds.
  void setProtocolVersion(String protocolVersion) {
    _sessionId = _pendingSessionId;
    _pendingSessionId = null;
    _protocolVersion = protocolVersion;
    _sessionExpired = false;
  }

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
      return await _client.send(request).timeout(requestTimeout);
    } catch (error) {
      throw _transportError(
        method: request.method,
        uri: request.url,
        context: error.runtimeType.toString(),
      );
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
          unawaited(subscription.cancel());
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
        unawaited(
          _sendCancelledNotification(
            request.id,
            'Request timed out after ${requestTimeout.inMilliseconds}ms',
          ),
        );
        throw MCPException(
          'Request timed out waiting for ${request.method} response',
        );
      },
    );
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

  @override
  Future<void> sendNotification(JsonRpcNotification notification) async {
    _ensureOpen();
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

    if (_sessionId != null && !_sessionExpired && _protocolVersion != null) {
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
