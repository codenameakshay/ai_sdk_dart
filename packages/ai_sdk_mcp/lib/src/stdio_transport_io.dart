import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'json_rpc.dart';

class _PendingRequest {
  _PendingRequest() : completer = Completer<JsonRpcResponse>();

  final Completer<JsonRpcResponse> completer;
}

/// Stdio transport for MCP — spawns [command] and communicates via stdin/stdout.
///
/// Desktop/CLI only. This implementation depends on `dart:io` (process
/// spawning) and is selected via a conditional import; on Flutter web the stub
/// in `stdio_transport_stub.dart` is used instead and throws
/// [UnsupportedError].
class StdioMCPTransport implements MCPTransport {
  StdioMCPTransport({
    required this.command,
    this.args = const [],
    Future<Process> Function(String command, List<String> args)? processStarter,
  }) : _processStarter = processStarter ?? Process.start;

  static const _requestTimeout = Duration(seconds: 30);
  static const _maxStderrChars = 4096;
  static const _maxBufferedFrameChars = 1024 * 1024;

  final String command;
  final List<String> args;
  final Future<Process> Function(String command, List<String> args)
  _processStarter;

  Process? _process;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  final _pending = <int, _PendingRequest>{};
  final _buffer = StringBuffer();
  final _notifications = StreamController<Map<String, dynamic>>.broadcast();
  String _stderrTail = '';
  int _stderrCharCount = 0;
  Future<void>? _startFuture;
  Future<void> _writeBarrier = Future<void>.value();
  Future<void>? _closeFuture;
  bool _closed = false;
  MCPException? _terminalError;

  @override
  Stream<Map<String, dynamic>> get notifications => _notifications.stream;

  Future<void> _ensureStarted() async {
    _throwIfClosedOrExited();
    if (_process != null) return;
    final existing = _startFuture;
    if (existing != null) return existing;
    final started = _startProcess();
    _startFuture = started;
    return started;
  }

  Future<void> _startProcess() async {
    try {
      final process = await _processStarter(command, args);
      if (_closed || _terminalError != null) {
        _safeCloseStdin(process);
        _safeKill(process);
        throw _terminalError ?? const MCPException('Stdio transport closed');
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
    } finally {
      _startFuture = null;
    }
  }

  void _handleLine(String line) {
    if (line.trim().isEmpty) return;
    _buffer.write(line);
    if (_buffer.length > _maxBufferedFrameChars) {
      _terminateImmediately(
        MCPException(
          'Stdio MCP stdout frame exceeded $_maxBufferedFrameChars '
          'characters without forming valid JSON',
        ),
        killProcess: true,
      );
      unawaited(
        _cancelSubscriptions().then((_) async {
          if (!_notifications.isClosed) {
            await _notifications.close();
          }
        }),
      );
      return;
    }
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
    _stderrCharCount += chunk.length;
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
    if (_stderrCharCount == 0) {
      return MCPException('Stdio MCP process exited with code $exitCode');
    }
    return MCPException(
      'Stdio MCP process exited with code $exitCode after writing '
      '$_stderrCharCount stderr characters',
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
    _terminateImmediately(error, killProcess: killProcess);
    await _cancelSubscriptions();
    if (!_notifications.isClosed) await _notifications.close();
  }

  void _terminateImmediately(MCPException error, {bool killProcess = false}) {
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
    final pending = _PendingRequest();
    _pending[request.id] = pending;
    unawaited(pending.completer.future.then((_) {}, onError: (_) {}));
    final line = '${jsonEncode(request.toJson())}\n';
    try {
      await _queueWrite(line);
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
      await _queueWrite(line);
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
    _closeFuture = _closeInternal();
    return _closeFuture;
  }

  Future<void> _closeInternal() async {
    await _terminate(
      _terminalError ?? const MCPException('Stdio transport closed'),
      killProcess: true,
    );
    final startFuture = _startFuture;
    if (startFuture != null) {
      try {
        await startFuture;
      } catch (_) {}
    }
    await _writeBarrier.catchError((_) {});
  }

  Future<void> _queueWrite(String line) {
    final next = _writeBarrier.catchError((_) {}).then((_) async {
      _throwIfClosedOrExited();
      final process = _process;
      if (process == null) {
        throw _terminalError ?? const MCPException('Stdio transport closed');
      }
      process.stdin.write(line);
      await process.stdin.flush();
    });
    _writeBarrier = next.catchError((_) {});
    return next;
  }
}
