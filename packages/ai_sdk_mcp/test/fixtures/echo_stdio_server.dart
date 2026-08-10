// A tiny JSON-RPC-over-stdio MCP-style server used to drive StdioMCPTransport
// in tests. It speaks the same framing the transport uses: newline-delimited
// JSON objects on stdin (requests) and stdout (responses / notifications).
//
// Behavior:
//   * `initialize`            → success result with serverInfo.
//   * `tools/list`            → a single `echo` tool.
//   * `tools/call` name=echo  → echoes back the `value` argument as text.
//   * `notifications/...`     → no response (fire-and-forget).
//   * `emit_notification`     → first replies with a result, then pushes an
//                               unsolicited server→client notification (used to
//                               exercise the notifications stream + the
//                               "incomplete JSON across lines" buffering path).
//   * anything else           → a JSON-RPC error response.
//
// The script intentionally splits one notification across two stdout writes
// (without a trailing newline on the first) so the transport's line-buffer
// reassembly is exercised.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  void writeMessage(Map<String, dynamic> message) {
    stdout.write('${jsonEncode(message)}\n');
  }

  var dropResponses = false;

  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.trim().isEmpty) continue;
    Map<String, dynamic> req;
    try {
      req = (jsonDecode(line) as Map).cast<String, dynamic>();
    } catch (_) {
      continue;
    }
    final id = req['id'];
    final method = req['method'] as String?;

    if (method != null && method.startsWith('notifications/')) {
      continue;
    }

    if (dropResponses) {
      continue;
    }

    if (method == 'initialize') {
      writeMessage({
        'jsonrpc': '2.0',
        'id': id,
        'result': {
          'protocolVersion': '2025-06-18',
          'capabilities': {'tools': {}},
          'serverInfo': {'name': 'echo-stdio', 'version': '1.0.0'},
        },
      });
      continue;
    }

    if (method == 'tools/list') {
      writeMessage({
        'jsonrpc': '2.0',
        'id': id,
        'result': {
          'tools': [
            {
              'name': 'echo',
              'description': 'Echoes the input value back',
              'inputSchema': {
                'type': 'object',
                'properties': {
                  'value': {'type': 'string'},
                },
              },
            },
          ],
        },
      });
      continue;
    }

    if (method == 'tools/call') {
      final params = (req['params'] as Map).cast<String, dynamic>();
      final args = (params['arguments'] as Map?) ?? const {};
      final value = args['value']?.toString() ?? '';
      writeMessage({
        'jsonrpc': '2.0',
        'id': id,
        'result': {
          'content': [
            {'type': 'text', 'text': 'echo: $value'},
          ],
          'isError': false,
        },
      });
      continue;
    }

    if (method == 'emit_notification') {
      // Reply to the request first.
      writeMessage({'jsonrpc': '2.0', 'id': id, 'result': {}});
      // Then push an unsolicited notification, split across two writes so the
      // first write is an incomplete JSON fragment (no newline yet). The
      // transport must buffer the first line and only decode once the second
      // line completes the JSON object.
      final notification = jsonEncode({
        'jsonrpc': '2.0',
        'method': 'notifications/message',
        'params': {'level': 'info', 'data': 'hello from stdio'},
      });
      final mid = notification.length ~/ 2;
      stdout.write('${notification.substring(0, mid)}\n');
      stdout.write('${notification.substring(mid)}\n');
      continue;
    }

    if (method == 'ack_then_stall') {
      final params =
          (req['params'] as Map?)?.cast<String, dynamic>() ?? const {};
      writeMessage({
        'jsonrpc': '2.0',
        'method': 'notifications/message',
        'params': {'ack': params['ack'] ?? 'stall-ready'},
      });
      await Completer<void>().future;
    }

    if (method == 'stall') {
      await Completer<void>().future;
    }

    if (method == 'exit_after_delay') {
      dropResponses = true;
      Timer(const Duration(milliseconds: 100), () {
        stderr.writeln('scheduled-exit');
        exit(17);
      });
      continue;
    }

    if (method == 'exit_with_stderr') {
      stderr
        ..write(List.filled(6000, 'A').join())
        ..writeln('stderr-tail-marker');
      exit(23);
    }

    if (method == 'exit_with_secret_stderr') {
      stderr
        ..writeln('Authorization: Bearer sk-live-stdio-token')
        ..writeln('refresh_token=rt-secret-value');
      exit(29);
    }

    writeMessage({
      'jsonrpc': '2.0',
      'id': id,
      'error': {'code': -32601, 'message': 'Method not found: $method'},
    });
  }
}
