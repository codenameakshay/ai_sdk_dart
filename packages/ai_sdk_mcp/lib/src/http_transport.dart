import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'json_rpc.dart';

// ---------------------------------------------------------------------------
// HTTP (request/response) transport
// ---------------------------------------------------------------------------

/// Plain HTTP request/response transport for MCP.
///
/// Each [send] performs a single `POST` to [postUrl] with the JSON-RPC request
/// body and parses the HTTP response body as the JSON-RPC response. This is a
/// simple, stateless transport that works anywhere `package:http` works —
/// including Flutter web — but it cannot receive server-initiated messages
/// (notifications / server→client requests). For server push, use
/// [SseClientTransport].
class HttpClientTransport implements MCPTransport {
  HttpClientTransport({required this.url, Uri? postUrl, this.headers})
    : postUrl = postUrl ?? url;

  /// Base URL for the transport. Used as the default [postUrl].
  final Uri url;

  /// URL that JSON-RPC requests are POSTed to.
  final Uri postUrl;

  /// Extra headers sent with every request.
  final Map<String, String>? headers;

  final _client = http.Client();

  @override
  Stream<Map<String, dynamic>> get notifications => const Stream.empty();

  @override
  Future<JsonRpcResponse> send(JsonRpcRequest request) async {
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
    return JsonRpcResponse.fromJson(body.cast<String, dynamic>());
  }

  @override
  Future<void> close() async {
    _client.close();
  }
}

// ---------------------------------------------------------------------------
// SSE transport (MCP HTTP+SSE, protocol 2024-11-05)
// ---------------------------------------------------------------------------

/// Real Server-Sent-Events transport for MCP (HTTP+SSE, protocol 2024-11-05).
///
/// This transport opens a long-lived streaming `GET` to the server's SSE
/// endpoint ([url]). The server's first event is an `endpoint` event whose data
/// is the (possibly relative) URL that client→server requests must be POSTed
/// to. All server→client traffic — responses, notifications, and server→client
/// requests — arrives over the SSE stream as `message` events carrying a
/// JSON-RPC payload.
///
/// Because responses arrive over the stream rather than as the body of the
/// POST, [send] correlates the outgoing request id with the incoming stream
/// message. Server-initiated messages (those without a matching pending id, or
/// with no id at all) are surfaced via [notifications].
///
/// Works anywhere `package:http` works, including Flutter web.
///
/// ```dart
/// final transport = SseClientTransport(
///   url: Uri.parse('http://localhost:3000/sse'),
/// );
/// ```
class SseClientTransport implements MCPTransport {
  SseClientTransport({
    required this.url,
    Uri? postUrl,
    this.headers,
    this.connectTimeout = const Duration(seconds: 30),
    this.requestTimeout = const Duration(seconds: 30),
    http.Client? client,
  }) : _explicitPostUrl = postUrl,
       _client = client ?? http.Client();

  /// SSE endpoint opened with a streaming `GET`.
  final Uri url;

  /// Extra headers sent with the SSE `GET` and every POST.
  final Map<String, String>? headers;

  /// How long to wait for the SSE connection (and the initial `endpoint`
  /// event) before failing.
  final Duration connectTimeout;

  /// How long to wait for a JSON-RPC response to arrive over the stream.
  final Duration requestTimeout;

  /// When set, overrides the POST URL advertised by the server's `endpoint`
  /// event. Mainly useful for servers that do not emit an `endpoint` event.
  final Uri? _explicitPostUrl;

  final http.Client _client;

  /// Broadcast stream of server-initiated messages (no matching pending id).
  final _notifications = StreamController<Map<String, dynamic>>.broadcast();

  /// Pending requests keyed by JSON-RPC id, awaiting a response over the SSE
  /// stream.
  final _pending = <int, Completer<JsonRpcResponse>>{};

  /// Completes once the SSE connection is open and (if the server emits one)
  /// the `endpoint` event has been received.
  Completer<void>? _ready;

  /// The URL to POST client→server requests to, resolved from the server's
  /// `endpoint` event (or [_explicitPostUrl] / [url] as a fallback).
  Uri? _postUrl;

  StreamSubscription<_SseEvent>? _eventSub;

  /// Bounds the wait for the `endpoint` event so callers don't hang. Held in a
  /// field so it can be cancelled once the endpoint arrives or the transport
  /// closes, rather than firing after the fact.
  Timer? _connectTimer;
  bool _closed = false;

  @override
  Stream<Map<String, dynamic>> get notifications => _notifications.stream;

  /// The resolved POST endpoint, once known. Exposed for diagnostics/tests.
  Uri? get resolvedPostUrl => _postUrl;

  Future<void> _ensureConnected() async {
    if (_closed) throw const MCPException('SSE transport is closed');
    final existing = _ready;
    if (existing != null) return existing.future;

    final ready = Completer<void>();
    _ready = ready;

    // If a POST URL was supplied explicitly, we don't need the endpoint event
    // to start sending — but we still resolve it from the server if it arrives.
    if (_explicitPostUrl != null) {
      _postUrl = _explicitPostUrl;
    }

    try {
      final request = http.Request('GET', url);
      request.headers.addAll({
        'Accept': 'text/event-stream',
        'Cache-Control': 'no-cache',
        ...?headers,
      });

      final streamed = await _client.send(request).timeout(connectTimeout);

      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        throw MCPException('SSE connect failed: HTTP ${streamed.statusCode}');
      }

      _eventSub = _parseSse(streamed.stream).listen(
        _handleEvent,
        onError: _handleStreamError,
        onDone: _handleStreamDone,
        cancelOnError: false,
      );

      // If we already have a POST URL we can proceed without waiting for the
      // endpoint event; otherwise wait for it (bounded by connectTimeout).
      if (_postUrl != null && !ready.isCompleted) {
        ready.complete();
      } else {
        // Time out the wait for the endpoint event so callers don't hang.
        _connectTimer = Timer(connectTimeout, () {
          _connectTimer = null;
          if (!ready.isCompleted) {
            // No endpoint event arrived; fall back to the SSE url itself.
            _postUrl ??= url;
            ready.complete();
          }
        });
      }
    } catch (e) {
      // Route the failure to the single `ready` future the caller awaits — and
      // do NOT also rethrow. Rethrowing would surface the error twice: once to
      // the caller (as the raw, unwrapped exception) and once as an *unhandled*
      // error on `ready.future`, which nobody else observes.
      _ready = null;
      _connectTimer?.cancel();
      _connectTimer = null;
      if (!ready.isCompleted) {
        ready.completeError(
          e is MCPException ? e : MCPException('SSE connect failed: $e'),
        );
      }
    }

    return ready.future;
  }

  void _handleEvent(_SseEvent event) {
    switch (event.event) {
      case 'endpoint':
        // The data is the (possibly relative) URL to POST requests to.
        final resolved = _resolveEndpoint(event.data.trim());
        _postUrl = resolved;
        _connectTimer?.cancel();
        _connectTimer = null;
        final ready = _ready;
        if (ready != null && !ready.isCompleted) ready.complete();
      case 'message':
      case '':
      default:
        // Default SSE event name is "message". Treat anything carrying a JSON
        // payload as a JSON-RPC message.
        final data = event.data.trim();
        if (data.isEmpty) return;
        Object? decoded;
        try {
          decoded = jsonDecode(data);
        } catch (_) {
          return; // Ignore non-JSON keep-alive lines.
        }
        if (decoded is! Map) return;
        _dispatchMessage(decoded.cast<String, dynamic>());
    }
  }

  Uri _resolveEndpoint(String raw) {
    final parsed = Uri.parse(raw);
    if (parsed.hasScheme) return parsed;
    // Resolve relative endpoints against the SSE url.
    return url.resolveUri(parsed);
  }

  void _dispatchMessage(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is int && _pending.containsKey(id)) {
      _pending.remove(id)!.complete(JsonRpcResponse.fromJson(json));
      return;
    }
    // Server-initiated message (notification or server→client request).
    if (!_notifications.isClosed) {
      _notifications.add(json);
    }
  }

  void _handleStreamError(Object error, StackTrace stackTrace) {
    _failAllPending(MCPException('SSE stream error: $error'));
  }

  void _handleStreamDone() {
    if (_closed) return;
    _failAllPending(const MCPException('SSE stream closed by server'));
    // Reset so a subsequent send() reconnects.
    _ready = null;
    _postUrl = _explicitPostUrl;
  }

  void _failAllPending(MCPException error) {
    final pending = List.of(_pending.values);
    _pending.clear();
    for (final c in pending) {
      if (!c.isCompleted) c.completeError(error);
    }
  }

  @override
  Future<JsonRpcResponse> send(JsonRpcRequest request) async {
    if (_closed) throw const MCPException('SSE transport is closed');
    await _ensureConnected();

    final postUrl = _postUrl;
    if (postUrl == null) {
      throw const MCPException(
        'SSE transport has no POST endpoint (no `endpoint` event received)',
      );
    }

    final completer = Completer<JsonRpcResponse>();
    _pending[request.id] = completer;
    // Ensure the raw completer future is always observed: the value/error is
    // delivered to the caller through the `.timeout` future below, but if that
    // wrapper has already settled (e.g. timed out) when `close()` rejects the
    // completer, the bare future would otherwise raise an unhandled error.
    unawaited(completer.future.then((_) {}, onError: (_) {}));

    final allHeaders = {
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/event-stream',
      ...?headers,
    };

    http.Response response;
    try {
      response = await _client
          .post(
            postUrl,
            headers: allHeaders,
            body: jsonEncode(request.toJson()),
          )
          .timeout(requestTimeout);
    } catch (e) {
      _pending.remove(request.id);
      throw MCPException('SSE POST failed: $e');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _pending.remove(request.id);
      throw MCPException('HTTP ${response.statusCode}: ${response.body}');
    }

    // Some servers reply inline (200 with the JSON-RPC body) instead of, or in
    // addition to, delivering the response over the SSE stream. Honor that.
    final body = response.body.trim();
    if (body.isNotEmpty) {
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map &&
            (decoded.containsKey('result') || decoded.containsKey('error')) &&
            decoded['id'] == request.id) {
          _pending.remove(request.id);
          if (!completer.isCompleted) {
            completer.complete(
              JsonRpcResponse.fromJson(decoded.cast<String, dynamic>()),
            );
          }
        }
      } catch (_) {
        // Not an inline JSON-RPC response (e.g. "Accepted"); wait for SSE.
      }
    }

    return completer.future.timeout(
      requestTimeout,
      onTimeout: () {
        _pending.remove(request.id);
        throw MCPException(
          'Timeout waiting for SSE response to ${request.method}',
        );
      },
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return; // Idempotent: safe to call repeatedly / on error paths.
    _closed = true;
    _connectTimer?.cancel();
    _connectTimer = null;
    // Fail a connect still in progress (no endpoint event yet) so the awaiting
    // caller gets a single error instead of hanging until connectTimeout.
    final ready = _ready;
    _ready = null;
    if (ready != null && !ready.isCompleted) {
      ready.completeError(const MCPException('SSE transport closed'));
    }
    final sub = _eventSub;
    _eventSub = null;
    await sub?.cancel();
    _failAllPending(const MCPException('SSE transport closed'));
    if (!_notifications.isClosed) await _notifications.close();
    _client.close();
  }

  /// Parse a byte stream of `text/event-stream` data into [_SseEvent]s.
  ///
  /// Implements the SSE wire format: lines `field:value` grouped into events
  /// separated by blank lines. Recognizes `event:` and `data:` fields; multiple
  /// `data:` lines are joined with `\n`. Comment lines (starting with `:`) are
  /// ignored.
  Stream<_SseEvent> _parseSse(Stream<List<int>> byteStream) {
    return Stream<_SseEvent>.eventTransformed(
      byteStream.transform(utf8.decoder).transform(const LineSplitter()),
      (sink) => _SseLineSink(sink),
    );
  }
}

/// A single parsed SSE event.
class _SseEvent {
  _SseEvent(this.event, this.data);
  final String event;
  final String data;
}

/// EventSink that accumulates SSE lines into [_SseEvent]s, flushing on blank
/// lines.
class _SseLineSink implements EventSink<String> {
  _SseLineSink(this._out);

  final EventSink<_SseEvent> _out;
  String _event = '';
  final _data = StringBuffer();
  bool _hasData = false;
  bool _hasEvent = false;

  @override
  void add(String line) {
    if (line.isEmpty) {
      _flush();
      return;
    }
    if (line.startsWith(':')) {
      // Comment / keep-alive — ignore.
      return;
    }
    final colon = line.indexOf(':');
    String field;
    String value;
    if (colon == -1) {
      field = line;
      value = '';
    } else {
      field = line.substring(0, colon);
      value = line.substring(colon + 1);
      if (value.startsWith(' ')) value = value.substring(1);
    }
    switch (field) {
      case 'event':
        _event = value;
        _hasEvent = true;
      case 'data':
        if (_hasData) _data.write('\n');
        _data.write(value);
        _hasData = true;
      default:
        // Ignore `id:` / `retry:` / unknown fields for our purposes.
        break;
    }
  }

  void _flush() {
    if (!_hasData && !_hasEvent) return;
    _out.add(_SseEvent(_event, _data.toString()));
    _event = '';
    _data.clear();
    _hasData = false;
    _hasEvent = false;
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
