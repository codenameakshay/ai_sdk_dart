import 'dart:convert';

import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:test/test.dart';

void main() {
  test('line byte limit applies to each row, not a network chunk', () async {
    final lines = [
      for (final id in ['input-1', 'input-2'])
        jsonEncode({
          'custom_id': id,
          'response': {'status_code': 200},
          'error': null,
        }),
    ];
    final rows = await decodeOpenAIBatchResults(
      Stream.value(utf8.encode('${lines.join('\n')}\n')),
      maxLineBytes: utf8.encode(lines.first).length,
    ).toList();
    expect(rows.map((row) => row.customId), ['input-1', 'input-2']);
  });

  test('batch error file permits a null response', () async {
    final rows = await decodeOpenAIBatchResults(
      Stream.value(
        utf8.encode(
          '${jsonEncode({
            'id': 'batch_req_1',
            'custom_id': 'input-1',
            'response': null,
            'error': {
              'code': 'batch_expired',
              'message': 'This request could not be executed before expiry.',
            },
          })}\n',
        ),
      ),
    ).toList();
    expect(rows.single.customId, 'input-1');
    expect(rows.single.error?['code'], 'batch_expired');
    expect(rows.single.response, isNull);
  });

  test('complete final JSONL row does not require a trailing newline', () async {
    final rows = await decodeOpenAIBatchResults(
      Stream.value(
        utf8.encode(
          jsonEncode({
            'id': 'batch_req_2',
            'custom_id': 'input-2',
            'response': {
              'status_code': 200,
              'request_id': 'req_2',
              'body': {'output': []},
            },
            'error': null,
          }),
        ),
      ),
    ).toList();
    expect(rows.single.customId, 'input-2');
    expect(rows.single.statusCode, 200);
  });
}
