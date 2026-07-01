import 'dart:async';

import 'json_rpc.dart';

/// Web/Flutter-web stub for [StdioMCPTransport].
///
/// The stdio transport spawns an OS process and talks to it over stdin/stdout,
/// which requires `dart:io` and is therefore unavailable on the web. This stub
/// preserves the public API so code that merely references the type still
/// compiles for web, but throws [UnsupportedError] when actually used.
///
/// On non-web platforms the real implementation in `stdio_transport_io.dart` is
/// selected via a conditional import.
class StdioMCPTransport implements MCPTransport {
  StdioMCPTransport({required this.command, this.args = const []});

  final String command;
  final List<String> args;

  static const _unsupported =
      'Stdio MCP transport is not available on web/Flutter web. '
      'Use SseClientTransport or HttpClientTransport instead.';

  @override
  Stream<Map<String, dynamic>> get notifications =>
      throw UnsupportedError(_unsupported);

  @override
  Future<JsonRpcResponse> send(JsonRpcRequest request) =>
      throw UnsupportedError(_unsupported);

  @override
  Future<void> close() async {}
}
