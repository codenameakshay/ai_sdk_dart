import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_sdk_google/ai_sdk_google.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  test(
    'preserves distinct same-name function calls across stream chunks',
    () async {
      final adapter = _Adapter();
      final client = Dio()..httpClientAdapter = adapter;
      addTearDown(() => client.close(force: true));
      final model = GoogleGenerativeAIProvider(
        apiKey: 'test',
        client: client,
      ).call('gemini-test');
      final result = await model.doStream(
        const LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(messages: []),
        ),
      );
      final parts = await result.stream.toList();
      expect(parts.whereType<StreamPartError>(), isEmpty);
      final calls = parts
          .whereType<StreamPartToolCall>()
          .map((part) => part.toolCall)
          .toList();
      expect(calls.map((call) => call.toolCallId), ['call-1', 'call-2']);
      expect(calls.map((call) => call.toolName), ['lookup', 'lookup']);
      expect(calls.map((call) => call.input), [
        {'q': 'first'},
        {'q': 'second'},
      ]);
      expect(parts.whereType<StreamPartToolInputEnd>().map((part) => part.id), [
        'call-1',
        'call-2',
      ]);
      expect(parts.whereType<StreamPartFinish>(), hasLength(1));
    },
  );
}

class _Adapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final events = [
      for (final entry in {'call-1': 'first', 'call-2': 'second'}.entries)
        {
          'candidates': [
            {
              'content': {
                'parts': [
                  {
                    'functionCall': {
                      'id': entry.key,
                      'name': 'lookup',
                      'args': {'q': entry.value},
                    },
                  },
                ],
              },
            },
          ],
        },
      {
        'candidates': [
          {'finishReason': 'STOP'},
        ],
      },
    ];
    return ResponseBody.fromString(
      events.map((event) => 'data: ${jsonEncode(event)}\n\n').join(),
      200,
      headers: {
        'content-type': ['text/event-stream'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
