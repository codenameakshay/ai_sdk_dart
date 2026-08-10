import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'json_rpc.dart';

class _PendingRequest {
  _PendingRequest(this.method) : completer = Completer<JsonRpcResponse>();

  final String method;
  final Completer<JsonRpcResponse> completer;
}

/// Stdio transport for MCP — spawns [command] and communicates via stdin/stdout.
///
/// Desktop/CLI only. This implementation depends on `dart:io` (process
/// spawning) and is selected via a conditional import; on Flutter web the stub
/// in `stdio_transport_stub.dart` is used instead and throws
/// [UnsupportedError].
class StdioMCPTransport implements MCPTransport {
  StdioMCPTransport({required this.command, this.args = const []});

  static const _requestTimeout = Duration(seconds: 30);
  static const _maxStderrChars = 4096;

  final String command;
  final List<String> args;

  Process? _process;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  final _pending = <int, _PendingRequest>{};
  final _buffer = StringBuffer();
  final _notifications = StreamController<Map<String, dynamic>>.broadcast();
  String _stderrTail = '';
  Future<void>? _closeFuture;
  bool _closed = false;
  MCPException? _terminalError;

  @override
  Stream<Map<String, dynamic>> get notifications => _notifications.stream;

  Future<void> _ensureStarted() async {
    _throwIfClosedOrExited();
    if (_process != null) return;
    try {
      final process = await Process.start(command, args);
      if (_closed) {
        _safeCloseStdin(process);
        _safeKill(process);
        throw const MCPException('Stdio transport closed');
      }

      _process = process;
      _stdoutSub = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            _handleLine,
            onError: _handleStdoutError,
            cancelOnError: false,
          );
      _stderrSub = process.stderr.transform(utf8.decoder).listen(_appendStderr);
      unawaited(process.exitCode.then(_handleProcessExit));
    } catch (error) {
      if (error is MCPException) rethrow;
      throw MCPException('Failed to start stdio MCP process: $error');
    }
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
          final pending = _pending.remove(id)!;
          if (!pending.completer.isCompleted) {
            pending.completer.complete(JsonRpcResponse.fromJson(json));
          }
        } else if (!_notifications.isClosed) {
          // Server-initiated message (notification or request).
          _notifications.add(json);
        }
      }
    } catch (_) {
      // Incomplete JSON — accumulate more lines.
    }
  }

  void _handleStdoutError(Object error) {
    unawaited(
      _terminate(
        MCPException('Stdio MCP stdout stream error: $error'),
        killProcess: true,
      ),
    );
  }

  void _appendStderr(String chunk) {
    if (chunk.isEmpty) return;
    _stderrTail += chunk;
    if (_stderrTail.length > _maxStderrChars) {
      _stderrTail = _stderrTail.substring(_stderrTail.length - _maxStderrChars);
    }
  }

  Future<void> _handleProcessExit(int exitCode) async {
    if (_closed) {
      _process = null;
      return;
    }
    await _terminate(_buildExitError(exitCode));
  }

  MCPException _buildExitError(int exitCode) {
    final stderr = _stderrTail.trim();
    if (stderr.isEmpty) {
      return MCPException('Stdio MCP process exited with code $exitCode');
    }
    return MCPException(
      'Stdio MCP process exited with code $exitCode. '
      'Recent stderr:\n$stderr',
    );
  }

  void _throwIfClosedOrExited() {
    final error = _terminalError;
    if (error != null) throw error;
    if (_closed) throw const MCPException('Stdio transport closed');
  }

  void _failAllPending(MCPException error) {
    final pending = List.of(_pending.values);
    _pending.clear();
    for (final request in pending) {
      if (!request.completer.isCompleted) {
        request.completer.completeError(error);
      }
    }
  }

  Future<void> _cancelSubscriptions() async {
    final stdoutSub = _stdoutSub;
    final stderrSub = _stderrSub;
    _stdoutSub = null;
    _stderrSub = null;
    await stdoutSub?.cancel();
    await stderrSub?.cancel();
  }

  Future<void> _terminate(
    MCPException error, {
    bool killProcess = false,
  }) async {
    _terminalError ??= error;
    _closed = true;
    _failAllPending(_terminalError!);
    final process = _process;
    _process = null;
    _buffer.clear();
    if (killProcess && process != null) {
      _safeCloseStdin(process);
      _safeKill(process);
    }
    await _cancelSubscriptions();
    if (!_notifications.isClosed) await _notifications.close();
  }

  void _safeCloseStdin(Process process) {
    try {
      process.stdin.close();
    } catch (_) {}
  }

  void _safeKill(Process process) {
    try {
      process.kill();
    } catch (_) {}
  }

  @override
  Future<JsonRpcResponse> send(JsonRpcRequest request) async {
    await _ensureStarted();
    _throwIfClosedOrExited();
    final pending = _PendingRequest(request.method);
    _pending[request.id] = pending;
    unawaited(pending.completer.future.then((_) {}, onError: (_) {}));
    final line = '${jsonEncode(request.toJson())}\n';
    try {
      _process!.stdin.write(line);
      await _process!.stdin.flush();
    } catch (error) {
      final removed = _pending.remove(request.id);
      if (removed != null && !removed.completer.isCompleted) {
        removed.completer.completeError(
          _terminalError ??
              MCPException('Failed to write to stdio MCP process: $error'),
        );
      }
    }
    return pending.completer.future.timeout(
      _requestTimeout,
      // coverage:ignore-start
      // Hardcoded 30s timeout; covering it would require a 30s+ hang, which is
      // not deterministic to test quickly. Exercised in integration only.
      onTimeout: () {
        _pending.remove(request.id);
        throw MCPException('Timeout waiting for response to ${request.method}');
      },
      // coverage:ignore-end
    );
  }

  @override
  Future<void> sendNotification(JsonRpcNotification notification) async {
    await _ensureStarted();
    _throwIfClosedOrExited();
    final line = '${jsonEncode(notification.toJson())}\n';
    try {
      _process!.stdin.write(line);
      await _process!.stdin.flush();
    } catch (error) {
      throw _terminalError ??
          MCPException(
            'Failed to write notification to stdio MCP process: $error',
          );
    }
  }

  @override
  Future<void> close() async {
    final existing = _closeFuture;
    if (existing != null) return existing;
    _closeFuture = _terminate(
      _terminalError ?? const MCPException('Stdio transport closed'),
      killProcess: true,
    );
    return _closeFuture;
  }
}
