import 'dart:async';
import 'dart:convert';
import 'dart:io';

class RecordedHttpRequest {
  RecordedHttpRequest({
    required this.method,
    required this.headers,
    required this.body,
  });

  final String method;
  final Map<String, String> headers;
  final Map<String, dynamic>? body;
}

class FakeSseFrame {
  const FakeSseFrame({
    this.event = 'message',
    this.id,
    this.dataLines = const [],
    this.comment,
  });

  final String event;
  final String? id;
  final List<String> dataLines;
  final String? comment;

  factory FakeSseFrame.json(
    Map<String, dynamic> json, {
    String event = 'message',
    String? id,
  }) {
    return FakeSseFrame(event: event, id: id, dataLines: [jsonEncode(json)]);
  }
}

class _QueuedResponse {
  _QueuedResponse.json({
    required this.statusCode,
    required this.jsonBody,
    this.headers = const {},
    this.waitFor,
    this.injectRequestId = true,
  }) : sseFrames = const [],
       closeSseStream = true;

  _QueuedResponse.sse({
    required this.statusCode,
    required this.sseFrames,
    this.headers = const {},
    this.closeSseStream = true,
    this.waitFor,
    this.injectRequestId = true,
  }) : jsonBody = null;

  final int statusCode;
  final Map<String, String> headers;
  final Map<String, dynamic>? jsonBody;
  final List<FakeSseFrame> sseFrames;
  final bool closeSseStream;
  final Future<void>? waitFor;
  final bool injectRequestId;
}

class FakeStreamableHttpServer {
  FakeStreamableHttpServer._(this._server);

  final HttpServer _server;
  final _queuedResponses = <_QueuedResponse>[];
  final _queuedGetStatusCodes = <int>[];
  final _requestLog = <RecordedHttpRequest>[];
  final _listenerEventHistory = <FakeSseFrame>[];
  final _listenerReconnectHeaders = <String?>[];
  final _listenerConnected = StreamController<void>.broadcast();

  HttpResponse? _listenerResponse;
  String? _activeSessionId;
  String? _expiredSessionId;
  bool _closeListenerAfterNextPush = false;

  int get listenerConnectionCount => _listenerReconnectHeaders.length;
  List<RecordedHttpRequest> get requestLog => List.unmodifiable(_requestLog);
  List<String?> get listenerLastEventIds =>
      List.unmodifiable(_listenerReconnectHeaders);

  int get getRequestCount =>
      _requestLog.where((request) => request.method == 'GET').length;

  int get deleteRequestCount =>
      _requestLog.where((request) => request.method == 'DELETE').length;

  int get cancelNotificationCount => _requestLog
      .where((request) => request.body?['method'] == 'notifications/cancelled')
      .length;

  bool getListenerSupported = false;
  int deleteStatusCode = 204;

  static Future<FakeStreamableHttpServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakeStreamableHttpServer._(server);
    unawaited(fake._serve());
    return fake;
  }

  Uri get uri =>
      Uri.parse('http://${_server.address.address}:${_server.port}/mcp');

  void queueInitializeResponse({
    String protocolVersion = '2025-06-18',
    String? sessionId,
    Map<String, dynamic> capabilities = const {
      'tools': {},
      'prompts': {},
      'resources': {'subscribe': true},
    },
    Map<String, dynamic> serverInfo = const {
      'name': 'test-server',
      'version': '1.0.0',
    },
    Future<void>? waitFor,
  }) {
    queueJsonResponse(
      {
        'jsonrpc': '2.0',
        'result': {
          'protocolVersion': protocolVersion,
          'capabilities': capabilities,
          'serverInfo': serverInfo,
        },
      },
      headers: sessionId == null ? const {} : {'Mcp-Session-Id': sessionId},
      waitFor: waitFor,
    );
  }

  void queueJsonResponse(
    Map<String, dynamic> jsonBody, {
    int statusCode = 200,
    Map<String, String> headers = const {},
    Future<void>? waitFor,
    bool injectRequestId = true,
  }) {
    _queuedResponses.add(
      _QueuedResponse.json(
        statusCode: statusCode,
        jsonBody: jsonBody,
        headers: headers,
        waitFor: waitFor,
        injectRequestId: injectRequestId,
      ),
    );
  }

  void queueSseResponse(
    List<FakeSseFrame> frames, {
    int statusCode = 200,
    Map<String, String> headers = const {},
    bool closeStream = true,
    Future<void>? waitFor,
    bool injectRequestId = true,
  }) {
    _queuedResponses.add(
      _QueuedResponse.sse(
        statusCode: statusCode,
        sseFrames: frames,
        headers: headers,
        closeSseStream: closeStream,
        waitFor: waitFor,
        injectRequestId: injectRequestId,
      ),
    );
  }

  void queueGetStatusCode(int statusCode) {
    _queuedGetStatusCodes.add(statusCode);
  }

  void expireCurrentSession() {
    _expiredSessionId = _activeSessionId;
  }

  void disconnectListenerAfterNextPush() {
    _closeListenerAfterNextPush = true;
  }

  Future<void> waitForListenerConnection() async {
    if (_listenerReconnectHeaders.isNotEmpty) {
      return;
    }
    await _listenerConnected.stream.first;
  }

  Future<void> pushListenerFrame(FakeSseFrame frame) async {
    await waitForListenerConnection();
    if (frame.id != null) {
      _listenerEventHistory.add(frame);
    }
    _writeSseFrame(_listenerResponse, frame);
    await _listenerResponse?.flush();
    if (_closeListenerAfterNextPush) {
      _closeListenerAfterNextPush = false;
      await disconnectActiveListener();
    }
  }

  Future<void> pushListenerJson(
    Map<String, dynamic> json, {
    String? id,
    String event = 'message',
  }) {
    return pushListenerFrame(FakeSseFrame.json(json, event: event, id: id));
  }

  Future<void> disconnectActiveListener() async {
    final response = _listenerResponse;
    _listenerResponse = null;
    try {
      await response?.close();
    } catch (_) {}
  }

  Future<void> close() async {
    await disconnectActiveListener();
    await _listenerConnected.close();
    await _server.close(force: true);
  }

  Future<void> _serve() async {
    await for (final request in _server) {
      final headers = <String, String>{};
      request.headers.forEach((name, values) {
        headers[name.toLowerCase()] = values.join(', ');
      });
      final body = await _readJsonBody(request);
      _requestLog.add(
        RecordedHttpRequest(
          method: request.method,
          headers: headers,
          body: body,
        ),
      );

      if (_isExpiredSessionRequest(headers)) {
        request.response.statusCode = 404;
        await request.response.close();
        continue;
      }

      switch (request.method) {
        case 'GET':
          await _handleGet(request);
        case 'DELETE':
          await _handleDelete(request);
        case 'POST':
          await _handlePost(request, body);
        default:
          request.response.statusCode = 405;
          await request.response.close();
      }
    }
  }

  Future<Map<String, dynamic>?> _readJsonBody(HttpRequest request) async {
    if (request.method == 'GET' || request.method == 'DELETE') {
      await request.drain<void>();
      return null;
    }

    final bodyText = await utf8.decoder.bind(request).join();
    if (bodyText.trim().isEmpty) {
      return null;
    }
    return (jsonDecode(bodyText) as Map).cast<String, dynamic>();
  }

  bool _isExpiredSessionRequest(Map<String, String> headers) {
    final sessionId = headers['mcp-session-id'];
    return sessionId != null &&
        _expiredSessionId != null &&
        sessionId == _expiredSessionId;
  }

  Future<void> _handleGet(HttpRequest request) async {
    if (_queuedGetStatusCodes.isNotEmpty) {
      final statusCode = _queuedGetStatusCodes.removeAt(0);
      request.response.statusCode = statusCode;
      await request.response.close();
      return;
    }

    if (!getListenerSupported) {
      request.response.statusCode = 405;
      await request.response.close();
      return;
    }

    request.response.statusCode = 200;
    request.response.headers.set('Content-Type', 'text/event-stream');
    request.response.headers.set('Cache-Control', 'no-cache');
    request.response.bufferOutput = false;
    _listenerResponse = request.response;
    _listenerReconnectHeaders.add(request.headers.value('Last-Event-ID'));
    _listenerConnected.add(null);

    final lastEventId = request.headers.value('Last-Event-ID');
    if (lastEventId != null) {
      var replay = false;
      for (final frame in _listenerEventHistory) {
        if (replay) {
          _writeSseFrame(_listenerResponse, frame);
        }
        if (frame.id == lastEventId) {
          replay = true;
        }
      }
      await _listenerResponse?.flush();
    }
  }

  Future<void> _handleDelete(HttpRequest request) async {
    request.response.statusCode = deleteStatusCode;
    await request.response.close();
  }

  Future<void> _handlePost(
    HttpRequest request,
    Map<String, dynamic>? body,
  ) async {
    if (body == null) {
      request.response.statusCode = 400;
      await request.response.close();
      return;
    }

    if (!body.containsKey('id')) {
      request.response.statusCode = 202;
      await request.response.close();
      return;
    }

    final queued = _queuedResponses.isEmpty
        ? _QueuedResponse.json(
            statusCode: 200,
            jsonBody: {'jsonrpc': '2.0', 'id': body['id'], 'result': {}},
          )
        : _queuedResponses.removeAt(0);

    await queued.waitFor;

    for (final entry in queued.headers.entries) {
      request.response.headers.set(entry.key, entry.value);
    }

    final sessionId = queued.headers['Mcp-Session-Id'];
    if (sessionId != null) {
      _activeSessionId = sessionId;
      _expiredSessionId = null;
    }

    request.response.statusCode = queued.statusCode;
    if (queued.jsonBody != null) {
      request.response.headers.contentType = ContentType.json;
      final jsonBody = Map<String, dynamic>.of(queued.jsonBody!);
      if (queued.injectRequestId && !jsonBody.containsKey('id')) {
        jsonBody['id'] = body['id'];
      }
      request.response.write(jsonEncode(jsonBody));
      await request.response.close();
      return;
    }

    request.response.headers.set('Content-Type', 'text/event-stream');
    request.response.bufferOutput = false;
    if (queued.sseFrames.isEmpty) {
      request.response.write(': open\r\n\r\n');
    }
    for (final frame in queued.sseFrames) {
      _writeSseFrame(
        request.response,
        queued.injectRequestId &&
                frame.id == null &&
                frame.dataLines.length == 1 &&
                _looksLikeJsonObject(frame.dataLines.single)
            ? _injectRequestId(frame, body['id'])
            : frame,
      );
    }
    await request.response.flush();
    if (queued.closeSseStream) {
      await request.response.close();
    }
  }

  FakeSseFrame _injectRequestId(FakeSseFrame frame, Object? id) {
    final decoded = jsonDecode(frame.dataLines.single);
    if (decoded is! Map || decoded.containsKey('id')) {
      return frame;
    }
    final patched = Map<String, dynamic>.of(decoded.cast<String, dynamic>())
      ..['id'] = id;
    return FakeSseFrame.json(patched, event: frame.event, id: frame.id);
  }

  bool _looksLikeJsonObject(String value) {
    final trimmed = value.trimLeft();
    return trimmed.startsWith('{');
  }

  void _writeSseFrame(HttpResponse? response, FakeSseFrame frame) {
    if (response == null) {
      return;
    }
    if (frame.comment != null) {
      response.write(': ${frame.comment}\r\n');
    }
    if (frame.id != null) {
      response.write('id: ${frame.id}\r\n');
    }
    if (frame.event.isNotEmpty) {
      response.write('event: ${frame.event}\r\n');
    }
    for (final line in frame.dataLines) {
      response.write('data: $line\r\n');
    }
    response.write('\r\n');
  }
}
