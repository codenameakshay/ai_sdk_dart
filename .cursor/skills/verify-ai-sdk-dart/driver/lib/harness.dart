/// Shared harness for the AI SDK Dart verification checks.
///
/// A check drives one user-facing feature through a package's public API and
/// records what crossed the boundary: every HTTP exchange with a fixture
/// server (or, in live mode, with the real provider through [CheckContext.
/// recordingDio]), plus the values the caller observed. The runner in
/// `bin/verify.dart` writes one JSON evidence file per check.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

/// Whether a check talks to an in-process fixture or to a real provider.
enum CheckMode { fixture, live }

/// One verifiable behavior of a package.
class Check {
  Check({
    required this.id,
    required this.feature,
    required this.description,
    required this.run,
    this.mode = CheckMode.fixture,
    this.requiresEnv = const [],
    this.timeout,
  });

  /// Stable id, unique within the package, e.g. `generate-text`.
  final String id;

  /// Sub-feature id from the package's feature file, e.g. `text-generate`.
  final String feature;

  /// One sentence: what the user does and what must be observed.
  final String description;

  final CheckMode mode;

  /// Environment variables a live check needs. Missing ones skip the check.
  final List<String> requiresEnv;

  final Duration? timeout;

  final Future<void> Function(CheckContext ctx) run;
}

/// The checks for one package.
class PackageChecks {
  const PackageChecks(this.package, this.checks);

  final String package;
  final List<Check> checks;
}

/// Thrown by [CheckContext.expect] and friends.
class CheckFailure implements Exception {
  CheckFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Thrown by [CheckContext.skip]; the runner records the reason.
class CheckSkipped implements Exception {
  CheckSkipped(this.reason);
  final String reason;
  @override
  String toString() => reason;
}

/// Names of the secrets the harness knows about. Their values are scrubbed
/// from every evidence file.
const secretEnvNames = [
  'OPENAI_API_KEY',
  'ANTHROPIC_API_KEY',
  'GOOGLE_API_KEY',
  'AZURE_API_KEY',
  'COHERE_API_KEY',
  'GROQ_API_KEY',
  'MISTRAL_API_KEY',
];

const _redactedHeaders = {
  'authorization',
  'x-api-key',
  'api-key',
  'x-goog-api-key',
  'cookie',
  'set-cookie',
  'openai-organization',
  'openai-project',
};

const _maxBody = 16 * 1024;

List<String> get environmentSecrets => [
  for (final name in secretEnvNames)
    if ((Platform.environment[name] ?? '').isNotEmpty)
      Platform.environment[name]!,
]..sort((a, b) => b.length.compareTo(a.length));

List<String> _secretForms(List<String> secrets) {
  final forms = <String>{};
  for (final secret in secrets) {
    if (secret.isEmpty) continue;
    final encoded = jsonEncode(secret);
    forms.addAll([
      secret,
      encoded.substring(1, encoded.length - 1),
      Uri.encodeComponent(secret),
      Uri.encodeQueryComponent(secret),
    ]);
  }
  final sorted = forms.toList()..sort((a, b) => b.length.compareTo(a.length));
  return sorted;
}

String scrubSecrets(String text, List<String> secrets) {
  final sorted = _secretForms(secrets);
  if (sorted.isEmpty) return text;
  return text.replaceAll(
    RegExp(sorted.map(RegExp.escape).join('|')),
    '<redacted>',
  );
}

Object? scrubEvidence(Object? value, List<String> secrets) {
  if (value is String) return scrubSecrets(value, secrets);
  if (value is Map) {
    return {
      for (final e in value.entries)
        scrubSecrets('${e.key}', secrets): scrubEvidence(e.value, secrets),
    };
  }
  if (value is Iterable) {
    return [for (final v in value) scrubEvidence(v, secrets)];
  }
  return value;
}

Map<String, String> redactHeaders(Map<String, String> headers) => {
  for (final e in headers.entries)
    e.key.toLowerCase(): _redactedHeaders.contains(e.key.toLowerCase())
        ? '<redacted>'
        : e.value,
};

String _redactQuery(Uri uri) {
  const sensitive = {'key', 'api_key', 'apikey', 'access_token', 'token'};
  return uri.queryParametersAll.entries
      .expand(
        (entry) => entry.value.map(
          (value) => MapEntry(
            entry.key,
            sensitive.contains(entry.key.toLowerCase()) ? '<redacted>' : value,
          ),
        ),
      )
      .map(
        (entry) =>
            '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
      )
      .join('&');
}

Object? _bodyEvidence(String text) {
  if (text.isEmpty) return null;
  text = scrubSecrets(text, environmentSecrets);
  try {
    return jsonDecode(text);
  } on FormatException {
    return text.length > _maxBody
        ? '${_scrubTruncatedBody(text.substring(0, _maxBody))}…(${text.length} chars)'
        : text;
  }
}

String _scrubTruncatedBody(String text) {
  text = scrubSecrets(text, environmentSecrets);
  for (final secret in _secretForms(environmentSecrets)) {
    for (var length = secret.length - 1; length > 0; length--) {
      if (length <= text.length && text.endsWith(secret.substring(0, length))) {
        return '${text.substring(0, text.length - length)}<redacted>';
      }
    }
  }
  return text;
}

/// A request the fixture server received.
class FixtureRequest {
  FixtureRequest({
    required this.index,
    required this.method,
    required this.uri,
    required this.headers,
    required this.bodyBytes,
  });

  /// 0-based position among all requests this server received.
  final int index;
  final String method;
  final Uri uri;

  /// Lower-cased header names.
  final Map<String, String> headers;
  final List<int> bodyBytes;

  String get path => uri.path;
  String get bodyText => utf8.decode(bodyBytes, allowMalformed: true);

  /// The body decoded as JSON, or null when it is not JSON.
  Object? get json {
    try {
      return jsonDecode(bodyText);
    } on FormatException {
      return null;
    }
  }

  /// The body as a JSON object; throws [CheckFailure] otherwise.
  Map<String, dynamic> get jsonObject {
    final value = json;
    if (value is Map<String, dynamic>) return value;
    throw CheckFailure('$method $path body is not a JSON object: $bodyText');
  }
}

/// One server-sent event. [data] is JSON-encoded unless it is a String.
class SseEvent {
  const SseEvent(this.data, {this.event, this.id});
  final Object data;
  final String? event;
  final String? id;

  String encode() {
    final buffer = StringBuffer();
    if (id != null) buffer.writeln('id: $id');
    if (event != null) buffer.writeln('event: $event');
    final payload = data is String ? data as String : jsonEncode(data);
    for (final line in payload.split('\n')) {
      buffer.writeln('data: $line');
    }
    buffer.writeln();
    return buffer.toString();
  }
}

/// What a fixture handler sends back.
class FixtureResponse {
  FixtureResponse._(this.status, this.headers, this.chunks, this.chunkDelay);

  /// A JSON body.
  factory FixtureResponse.json(
    Object? body, {
    int status = 200,
    Map<String, String> headers = const {},
  }) => FixtureResponse._(
    status,
    {'content-type': 'application/json', ...headers},
    [utf8.encode(jsonEncode(body))],
    null,
  );

  /// A `text/event-stream` body. Each item is an [SseEvent], a JSON-encodable
  /// value (sent as `data: <json>`), or a raw String (sent as `data: <str>`).
  /// [done] appends `data: [DONE]`, as OpenAI-style APIs do.
  factory FixtureResponse.sse(
    List<Object> events, {
    bool done = false,
    int status = 200,
    Map<String, String> headers = const {},
    Duration? delay,
  }) {
    final chunks = [
      for (final e in events)
        utf8.encode((e is SseEvent ? e : SseEvent(e)).encode()),
      if (done) utf8.encode(const SseEvent('[DONE]').encode()),
    ];
    return FixtureResponse._(
      status,
      {
        'content-type': 'text/event-stream',
        'cache-control': 'no-cache',
        ...headers,
      },
      chunks,
      delay,
    );
  }

  /// Newline-delimited JSON (Ollama-style streaming).
  factory FixtureResponse.ndjson(
    List<Object> lines, {
    int status = 200,
    Duration? delay,
  }) => FixtureResponse._(
    status,
    {'content-type': 'application/x-ndjson'},
    [for (final l in lines) utf8.encode('${jsonEncode(l)}\n')],
    delay,
  );

  factory FixtureResponse.text(
    String body, {
    int status = 200,
    String contentType = 'text/plain',
    Map<String, String> headers = const {},
  }) => FixtureResponse._(
    status,
    {'content-type': contentType, ...headers},
    [utf8.encode(body)],
    null,
  );

  factory FixtureResponse.bytes(
    List<int> body, {
    int status = 200,
    String contentType = 'application/octet-stream',
  }) => FixtureResponse._(status, {'content-type': contentType}, [body], null);

  final int status;
  final Map<String, String> headers;
  final List<List<int>> chunks;
  final Duration? chunkDelay;
}

typedef FixtureHandler =
    FutureOr<FixtureResponse> Function(FixtureRequest request);

/// One recorded request/response pair.
class Exchange {
  Exchange({
    required this.source,
    required this.method,
    required this.url,
    required this.requestHeaders,
    required this.requestBody,
  });

  /// `fixture` or `live`.
  final String source;
  final String method;
  final String url;
  final Map<String, String> requestHeaders;
  Object? requestBody;
  int? status;
  Map<String, String>? responseHeaders;
  String? responseContentType;
  Object? responseBody;
  String? error;

  Map<String, Object?> toJson() => {
    'source': source,
    'method': method,
    'url': url,
    'requestHeaders': requestHeaders,
    'requestBody': requestBody,
    'status': status,
    'responseHeaders': responseHeaders,
    'responseContentType': responseContentType,
    'responseBody': responseBody,
    if (error != null) 'error': error,
  };
}

/// An in-process HTTP server on 127.0.0.1 that answers with [FixtureHandler]
/// and records every exchange into the owning check's evidence.
class FixtureServer {
  FixtureServer._(this._server, this._handler, this._record);

  final HttpServer _server;
  final FixtureHandler _handler;
  final void Function(Exchange) _record;
  final List<FixtureRequest> requests = [];

  static Future<FixtureServer> start(
    FixtureHandler handler,
    void Function(Exchange) record,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fixture = FixtureServer._(server, handler, record);
    server.listen(fixture._serve);
    return fixture;
  }

  int get port => _server.port;

  /// `http://127.0.0.1:<port>`, no trailing slash.
  String get origin => 'http://127.0.0.1:$port';

  /// [origin] joined with [path], e.g. `url('/v1')`.
  String url(String path) => '$origin$path';

  Future<void> _serve(HttpRequest request) async {
    final headers = <String, String>{};
    request.headers.forEach(
      (name, values) => headers[name] = values.join(', '),
    );
    final query = _redactQuery(request.uri);
    final body = <int>[];
    final exchange = Exchange(
      source: 'fixture',
      method: request.method,
      url: '${request.uri.path}${query.isEmpty ? '' : '?$query'}',
      requestHeaders: redactHeaders(headers),
      requestBody: null,
    );
    _record(exchange);
    final response = request.response..bufferOutput = false;
    var responseStarted = false;
    final sent = <int>[];
    try {
      await for (final chunk in request) {
        body.addAll(chunk);
      }
      final fixtureRequest = FixtureRequest(
        index: requests.length,
        method: request.method,
        uri: request.uri,
        headers: headers,
        bodyBytes: body,
      );
      requests.add(fixtureRequest);
      exchange.requestBody = _bodyEvidence(fixtureRequest.bodyText);
      final reply = await _handler(fixtureRequest);
      response.statusCode = reply.status;
      reply.headers.forEach(response.headers.set);
      exchange
        ..status = reply.status
        ..responseHeaders = redactHeaders(reply.headers)
        ..responseContentType = reply.headers['content-type'];
      for (final chunk in reply.chunks) {
        if (reply.chunkDelay != null) {
          await Future<void>.delayed(reply.chunkDelay!);
        }
        response.add(chunk);
        responseStarted = true;
        sent.addAll(chunk);
        await response.flush();
      }
    } catch (error) {
      exchange.error = 'fixture request/response failed: $error';
      if (!responseStarted) {
        exchange.status = 500;
        try {
          response.statusCode = 500;
          response.write('fixture request/response failed');
        } catch (_) {}
      }
    } finally {
      exchange.requestBody = _bodyEvidence(
        utf8.decode(body, allowMalformed: true),
      );
      exchange.responseBody = _bodyEvidence(
        utf8.decode(sent, allowMalformed: true),
      );
    }
    try {
      await response.close();
    } catch (error) {
      exchange.error ??= 'fixture response close failed: $error';
    }
  }

  Future<void> close() => _server.close(force: true);
}

/// Per-check API handed to every [Check.run].
class CheckContext {
  CheckContext({
    required this.package,
    required this.check,
    required this.live,
    required this.repoRoot,
    required this.artifactDir,
  });

  final String package;
  final Check check;

  /// True when the runner was started with `--live`.
  final bool live;

  /// Absolute path of the repository checkout.
  final String repoRoot;

  /// Directory for extra artifacts of this check (created on first use).
  final Directory artifactDir;

  final Map<String, Object?> observed = {};
  final List<Exchange> exchanges = [];
  final List<String> notes = [];
  final List<Future<void> Function()> _cleanups = [];
  bool _closed = false;
  Future<void>? _disposing;

  void _ensureOpen() {
    if (_closed) throw StateError('check context is closed');
  }

  /// Starts a loopback fixture server for this check. It is closed when the
  /// check ends.
  Future<FixtureServer> server(FixtureHandler handler) async {
    _ensureOpen();
    final server = await FixtureServer.start(handler, exchanges.add);
    if (_closed) {
      await server.close();
      throw StateError('check context is closed');
    }
    _cleanups.add(server.close);
    return server;
  }

  /// A Dio client that records every live request and response in this
  /// check's evidence, including a bounded prefix of streamed bodies.
  Dio recordingDio({String? baseUrl}) {
    _ensureOpen();
    final dio = Dio(BaseOptions(baseUrl: baseUrl ?? ''));
    dio.interceptors.add(_RecordingInterceptor(exchanges.add));
    _cleanups.add(() async => dio.close(force: true));
    return dio;
  }

  /// Starts [executable] and kills its process tree when the check ends.
  /// stdout/stderr go to `<artifactDir>/<name>.log`.
  Future<Process> spawn(
    String name,
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    _ensureOpen();
    final log = artifact('$name.log');
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
    final output = StringBuffer();
    Future<void> capture(Stream<List<int>> stream) async {
      try {
        await for (final chunk in stream.transform(
          const Utf8Decoder(allowMalformed: true),
        )) {
          output.write(chunk);
        }
      } catch (error) {
        output.write('process log failed: $error');
      }
    }

    final streams = Future.wait([
      capture(process.stdout),
      capture(process.stderr),
    ]);
    var descendants = <int>[];
    void kill(ProcessSignal signal) {
      for (final pid in descendants.reversed) {
        Process.killPid(pid, signal);
      }
      process.kill(signal);
    }

    Future<void> cleanup() async {
      if (Platform.isLinux || Platform.isMacOS) {
        final snapshot = await Process.run('ps', ['-eo', 'pid=,ppid=']);
        final parents = <int, int>{};
        for (final line in '${snapshot.stdout}'.trim().split('\n')) {
          final fields = line.trim().split(RegExp(r'\s+'));
          if (fields.length == 2) {
            final pid = int.tryParse(fields[0]);
            final parent = int.tryParse(fields[1]);
            if (pid != null && parent != null) parents[pid] = parent;
          }
        }
        final tree = {process.pid};
        var previous = 0;
        while (previous != tree.length) {
          previous = tree.length;
          for (final entry in parents.entries) {
            if (tree.contains(entry.value)) tree.add(entry.key);
          }
        }
        descendants = tree.where((pid) => pid != process.pid).toList();
      }
      kill(ProcessSignal.sigterm);
      await process.exitCode.timeout(
        const Duration(seconds: 1),
        onTimeout: () {
          kill(ProcessSignal.sigkill);
          return -1;
        },
      );
      kill(ProcessSignal.sigkill);
      await process.exitCode;
      await streams.timeout(const Duration(seconds: 2));
      log.writeAsStringSync(scrubSecrets('$output', environmentSecrets));
    }

    if (_closed) {
      await cleanup();
      throw StateError('check context is closed');
    }
    _cleanups.add(cleanup);
    return process;
  }

  /// Registers [cleanup] to run when the check ends, in reverse order.
  void onCleanup(Future<void> Function() cleanup) {
    if (_closed) {
      unawaited(Future<void>.sync(cleanup).catchError((Object _) {}));
    } else {
      _cleanups.add(cleanup);
    }
  }

  /// A file in this check's artifact directory.
  File artifact(String name) {
    _ensureOpen();
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        name.contains('/') ||
        name.contains('\\')) {
      throw ArgumentError.value(name, 'name', 'must be a file name');
    }
    artifactDir.createSync(recursive: true);
    return File('${artifactDir.path}/$name');
  }

  /// Records a value the caller observed through the public API.
  void observe(String key, Object? value) {
    _ensureOpen();
    observed[key] = _jsonSafe(value);
  }

  /// Records free-form context, e.g. why a fixture shape was chosen.
  void note(String text) {
    _ensureOpen();
    notes.add(text);
  }

  void expect(bool condition, String message) {
    if (!condition) throw CheckFailure(message);
  }

  void expectEquals(Object? actual, Object? expected, String what) {
    if (!_deepEquals(actual, expected)) {
      throw CheckFailure(
        '$what: expected ${jsonEncode(_jsonSafe(expected))}, got ${jsonEncode(_jsonSafe(actual))}',
      );
    }
  }

  /// Runs [body] and requires it to throw [T]; returns the error.
  Future<T> expectThrows<T extends Object>(
    Future<void> Function() body,
    String what,
  ) async {
    try {
      await body();
    } on T catch (error) {
      observe('$what.error', '${error.runtimeType}: $error');
      return error;
    }
    throw CheckFailure('$what: expected $T to be thrown, nothing was');
  }

  /// The value of [name], or skips the check when it is unset.
  String requireEnv(String name) {
    final value = Platform.environment[name];
    if (value == null || value.isEmpty) skip('$name is not set');
    return value;
  }

  /// [name] from the environment, or [fallback].
  String env(String name, String fallback) {
    final value = Platform.environment[name];
    return value == null || value.isEmpty ? fallback : value;
  }

  Never skip(String reason) => throw CheckSkipped(reason);

  /// Requests [server] received at [path] (and [method] when given).
  List<FixtureRequest> requestsTo(
    FixtureServer server,
    String path, {
    String? method,
  }) => [
    for (final r in server.requests)
      if (r.path == path && (method == null || r.method == method)) r,
  ];

  /// Exactly one request to [path]; fails otherwise.
  FixtureRequest singleRequest(
    FixtureServer server,
    String path, {
    String? method,
  }) {
    final matches = requestsTo(server, path, method: method);
    if (matches.length != 1) {
      throw CheckFailure(
        'expected one ${method ?? ''} request to $path, got ${matches.length} '
        '(all: ${server.requests.map((r) => '${r.method} ${r.path}').join(', ')})',
      );
    }
    return matches.single;
  }

  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    _closed = true;
    final failures = <Object>[];
    for (final cleanup in _cleanups.reversed) {
      try {
        await cleanup().timeout(const Duration(seconds: 5));
      } catch (error) {
        notes.add('cleanup failed: $error');
        failures.add(error);
      }
    }
    if (artifactDir.existsSync()) {
      for (final file
          in artifactDir
              .listSync(recursive: true, followLinks: false)
              .whereType<File>()) {
        var bytes = String.fromCharCodes(file.readAsBytesSync());
        final forms = _secretForms(environmentSecrets)
            .map(
              (form) => RegExp.escape(String.fromCharCodes(utf8.encode(form))),
            )
            .toList();
        if (forms.isNotEmpty) {
          final scrubbed = bytes.replaceAll(
            RegExp(forms.join('|')),
            '<redacted>',
          );
          if (scrubbed != bytes) file.writeAsBytesSync(scrubbed.codeUnits);
        }
      }
    }
    if (failures.isNotEmpty) throw CheckFailure(failures.join('; '));
  }
}

class _RecordingInterceptor extends Interceptor {
  _RecordingInterceptor(this._record);
  final void Function(Exchange) _record;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final headers = {
      for (final e in options.headers.entries) e.key: '${e.value}',
    };
    final data = options.data;
    final exchange = Exchange(
      source: 'live',
      method: options.method,
      url: options.uri.replace(query: _redactQuery(options.uri)).toString(),
      requestHeaders: redactHeaders(headers),
      requestBody: data is String
          ? _bodyEvidence(data)
          : data is Map || data is List
          ? _jsonSafe(data)
          : data == null
          ? null
          : '<${data.runtimeType}>',
    );
    options.extra['verifyExchange'] = exchange;
    _record(exchange);
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final exchange = response.requestOptions.extra['verifyExchange'];
    if (exchange is Exchange) {
      final data = response.data;
      exchange
        ..status = response.statusCode
        ..responseHeaders = redactHeaders(
          response.headers.map.map(
            (key, values) => MapEntry(key, values.join(', ')),
          ),
        )
        ..responseContentType = response.headers.value('content-type')
        ..responseBody = data is ResponseBody
            ? null
            : data is String
            ? _bodyEvidence(data)
            : data is List<int>
            ? '<${data.length} bytes>'
            : _jsonSafe(data);
      if (data is ResponseBody) _captureStream(data, exchange);
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final exchange = err.requestOptions.extra['verifyExchange'];
    if (exchange is Exchange) {
      final data = err.response?.data;
      exchange
        ..status = err.response?.statusCode
        ..responseHeaders = err.response == null
            ? null
            : redactHeaders(
                err.response!.headers.map.map(
                  (key, values) => MapEntry(key, values.join(', ')),
                ),
              )
        ..error = '${err.type}: ${err.message}'
        ..responseBody = data is ResponseBody ? null : _jsonSafe(data);
      if (data is ResponseBody) _captureStream(data, exchange);
    }
    handler.next(err);
  }

  void _captureStream(ResponseBody body, Exchange exchange) {
    final bytes = <int>[];
    var count = 0;
    void update() {
      final text = utf8.decode(bytes, allowMalformed: true);
      exchange.responseBody = count > _maxBody
          ? '${_scrubTruncatedBody(text)}…($count bytes, truncated)'
          : _bodyEvidence(text);
    }

    body.stream = body.stream
        .map((chunk) {
          count += chunk.length;
          final remaining = _maxBody - bytes.length;
          if (remaining > 0) bytes.addAll(chunk.take(remaining));
          update();
          return chunk;
        })
        .transform(
          StreamTransformer.fromHandlers(
            handleError: (Object error, StackTrace stack, sink) {
              exchange.error = 'response stream failed: $error';
              update();
              sink.addError(error, stack);
            },
            handleDone: (sink) {
              update();
              sink.close();
            },
          ),
        );
  }
}

Object? _jsonSafe(Object? value) {
  if (value == null || value is num || value is bool || value is String) {
    return value;
  }
  if (value is Map) {
    return {for (final e in value.entries) '${e.key}': _jsonSafe(e.value)};
  }
  if (value is Iterable) return [for (final v in value) _jsonSafe(v)];
  if (value is Uri || value is DateTime || value is Duration) return '$value';
  try {
    return _jsonSafe((value as dynamic).toJson());
  } catch (_) {
    return '$value';
  }
}

bool _deepEquals(Object? a, Object? b) =>
    jsonEncode(_jsonSafe(a)) == jsonEncode(_jsonSafe(b));
