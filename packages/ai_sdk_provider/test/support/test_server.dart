import 'dart:async';
import 'dart:io';

/// A minimal loopback HTTP server for provider tests.
///
/// [pathSuffix] is appended to [baseUrl] so provider clients that expect a
/// versioned/prefixed base URL (e.g. `/v1`, `/v1beta`, `/api`) can be pointed
/// at this server directly.
class TestServer {
  TestServer._(this._server, this._pathSuffix);

  final HttpServer _server;
  final String _pathSuffix;

  static Future<TestServer> start(
    Future<void> Function(HttpRequest request) handler, {
    String pathSuffix = '',
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(() async {
      await for (final request in server) {
        await handler(request);
      }
    }());
    return TestServer._(server, pathSuffix);
  }

  String get baseUrl =>
      'http://${_server.address.host}:${_server.port}$_pathSuffix';

  Future<void> close() => _server.close(force: true);
}
