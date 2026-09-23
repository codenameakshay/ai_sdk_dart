import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Starts the documented loopback backend fixture.
///
/// Port `0` asks the OS for an ephemeral port, which is useful for tests.
Future<HttpServer> startRemoteBackendServer({int port = 8080}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  server.listen(_handleRequest);
  return server;
}

Future<void> _handleRequest(HttpRequest request) async {
  request.response.headers
    ..set('access-control-allow-origin', '*')
    ..set('access-control-allow-methods', 'POST, OPTIONS')
    ..set('access-control-expose-headers', 'x-vercel-ai-ui-message-stream')
    ..set(
      'access-control-allow-headers',
      'content-type, x-vercel-ai-ui-message-stream',
    );
  if (request.method == 'OPTIONS') {
    request.response.statusCode = HttpStatus.noContent;
    await request.response.close();
    return;
  }
  if (request.uri.path != '/chat') {
    await _jsonError(
      request.response,
      HttpStatus.notFound,
      'Unknown endpoint.',
    );
    return;
  }
  if (request.method != 'POST') {
    await _jsonError(
      request.response,
      HttpStatus.methodNotAllowed,
      'Use POST /chat.',
    );
    return;
  }

  late final String body;
  try {
    body = await utf8.decoder.bind(request).join();
  } on FormatException {
    await _jsonError(
      request.response,
      HttpStatus.badRequest,
      'Request body must be valid UTF-8 JSON.',
    );
    return;
  }
  final decoded = _decodeRequest(body);
  if (decoded case final String error) {
    await _jsonError(request.response, HttpStatus.badRequest, error);
    return;
  }

  request.response
    ..statusCode = HttpStatus.ok
    ..headers.contentType = ContentType('text', 'event-stream')
    ..headers.set('cache-control', 'no-cache')
    ..headers.set('x-vercel-ai-ui-message-stream', 'v1');
  for (final event in [
    {'type': 'start', 'messageId': 'example-assistant'},
    {'type': 'text-start', 'id': 'example-text'},
    {
      'type': 'text-delta',
      'id': 'example-text',
      'delta': 'Hello from the trusted backend.',
    },
    {'type': 'text-end', 'id': 'example-text'},
    {'type': 'finish'},
  ]) {
    request.response.write('data: ${jsonEncode(event)}\n\n');
  }
  request.response.write('data: [DONE]\n\n');
  await request.response.close();
}

Object _decodeRequest(String body) {
  final value = _tryJsonDecode(body.trim());
  if (value is! Map) return 'Request body must be a JSON object.';
  final messages = value['messages'];
  if (messages is! List || messages.isEmpty) {
    return 'Request body must contain a non-empty messages array.';
  }
  for (var index = 0; index < messages.length; index++) {
    final message = messages[index];
    if (message is! Map ||
        message['role'] is! String ||
        message['parts'] is! List) {
      return 'messages[$index] must contain string role and array parts.';
    }
  }
  return value;
}

Object? _tryJsonDecode(String value) {
  try {
    return jsonDecode(value);
  } on FormatException {
    return null;
  }
}

Future<void> _jsonError(
  HttpResponse response,
  int status,
  String message,
) async {
  response
    ..statusCode = status
    ..headers.contentType = ContentType.json;
  response.write(jsonEncode({'error': message}));
  await response.close();
}

Future<void> main(List<String> args) async {
  final requestedPort = int.tryParse(
    Platform.environment['PORT'] ??
        args
            .where((arg) => arg.startsWith('--port='))
            .map((arg) => arg.substring('--port='.length))
            .firstOrNull ??
        '8080',
  );
  if (requestedPort == null || requestedPort < 0 || requestedPort > 65535) {
    stderr.writeln('PORT/--port must be an integer from 0 to 65535.');
    exitCode = 64;
    return;
  }
  final server = await startRemoteBackendServer(port: requestedPort);
  stdout.writeln(
    'Listening on http://${server.address.host}:${server.port}/chat',
  );
  final shutdown = Completer<void>();
  final signalSubscriptions = <StreamSubscription<ProcessSignal>>[];
  for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    signalSubscriptions.add(
      signal.watch().listen((_) {
        if (!shutdown.isCompleted) shutdown.complete();
      }),
    );
  }
  await shutdown.future;
  await Future.wait(
    signalSubscriptions.map((subscription) => subscription.cancel()),
  );
  await server.close();
}
