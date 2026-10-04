import 'dart:convert';
import 'dart:math';

import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';
import 'package:ai_sdk_remote/ai_sdk_remote.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  test('SSE framing survives every two-chunk UTF-8 byte split', () async {
    const seed = 0x5EED51;
    const expectedText = 'first é🧪 second';
    final body =
        [
          {'type': 'start', 'messageId': 'assistant-sweep'},
          {'type': 'text-start', 'id': 'text-sweep'},
          {'type': 'text-delta', 'id': 'text-sweep', 'delta': expectedText},
          {'type': 'text-end', 'id': 'text-sweep'},
          {'type': 'finish'},
          '[DONE]',
        ].map((event) {
          final payload = event is String ? event : jsonEncode(event);
          return 'data: $payload\r\n\r\n';
        }).join();
    final bytes = utf8.encode(body);
    final splits = List<int>.generate(bytes.length + 1, (index) => index)
      ..shuffle(Random(seed));
    final caseCount = splits.length;

    for (final split in splits) {
      final client = _TwoChunkClient(bytes, split);
      final transport = RemoteConversationTransport(
        endpoint: Uri.parse('https://backend.test/chat'),
        client: client,
      );
      try {
        final snapshots = await transport
            .send(Conversation(id: 'c-$split', messages: const []))
            .toList();
        final assistant = snapshots.last.messages.single;
        expect(
          assistant.id,
          'assistant-sweep',
          reason: 'seed=$seed split=$split',
        );
        expect(
          assistant.parts.whereType<TextPart>().single.text,
          expectedText,
          reason: 'seed=$seed split=$split',
        );
      } finally {
        transport.dispose();
        client.close();
      }
    }
    expect(caseCount, 275);
  });
}

class _TwoChunkClient extends http.BaseClient {
  _TwoChunkClient(this.bytes, this.split);
  final List<int> bytes;
  final int split;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (closed) throw StateError('client closed');
    expect(request.method, 'POST');
    final first = bytes.sublist(0, split);
    final second = bytes.sublist(split);
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable([
        if (first.isNotEmpty) first,
        if (second.isNotEmpty) second,
      ]),
      200,
      headers: const {
        'content-type': 'text/event-stream; charset=utf-8',
        'x-vercel-ai-ui-message-stream': 'v1',
      },
      request: request,
    );
  }

  @override
  void close() => closed = true;
}
