import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'json_rpc.dart';

/// Stdio transport for MCP — spawns [command] and communicates via stdin/stdout.
///
/// Desktop/CLI only. This implementation depends on `dart:io` (process
/// spawning) and is selected via a conditional import; on Flutter web the stub
/// in `stdio_transport_stub.dart` is used instead and throws
/// [UnsupportedError].
class StdioMCPTransport implements MCPTransport {
  StdioMCPTransport({required this.command, this.args = const []});

  final String command;
  final List<String> args;

  Process? _process;
  StreamSubscription<String>? _stdoutSub;
  final _pending = <int, Completer<JsonRpcResponse>>{};
  final _buffer = StringBuffer();
  final _notifications = StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> get notifications => _notifications.stream;

  Future<void> _ensureStarted() async {
    if (_process != null) return;
    _process = await Process.start(command, args);
    _stdoutSub = _process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleLine);
  }

  void _handleLine(String line) {
    if (line.trim().isEmpty) return;
    _buffer.write(line);
    try {
      final json = jsonDecode(_buffer.toString());
      _buffer.clear();
      if (json is Map<String, dynamic>) {
        final id = json['id'];
        if (id is int && _pending.containsKey(id)) {
          _pending.remove(id)!.complete(JsonRpcResponse.fromJson(json));
        } else if (!_notifications.isClosed) {
          // Server-initiated message (notification or request).
          _notifications.add(json);
        }
      }
    } catch (_) {
      // Incomplete JSON — accumulate more lines.
    }
  }

  @override
  Future<JsonRpcResponse> send(JsonRpcRequest request) async {
    await _ensureStarted();
    final completer = Completer<JsonRpcResponse>();
    _pending[request.id] = completer;
    final line = '${jsonEncode(request.toJson())}\n';
    _process!.stdin.write(line);
    await _process!.stdin.flush();
    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _pending.remove(request.id);
        throw MCPException('Timeout waiting for response to ${request.method}');
      },
    );
  }

  @override
  Future<void> close() async {
    await _stdoutSub?.cancel();
    _process?.stdin.close();
    _process?.kill();
    _process = null;
    if (!_notifications.isClosed) await _notifications.close();
  }
}
