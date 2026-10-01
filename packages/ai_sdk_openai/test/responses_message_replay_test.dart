import 'dart:convert';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

import 'support/fake_adapter.dart';

void main() {
  test('streamed assistant messages replay their text once', () async {
    final requests = <Map<String, dynamic>>[];
    final dio = Dio()
      ..httpClientAdapter = FakeHttpAdapter((request) async {
        requests.add(Map<String, dynamic>.from(request.data as Map));
        final events = [
          {
            'type': 'response.output_text.delta',
            'item_id': 'message-1',
            'delta': 'Hello',
          },
          {
            'type': 'response.output_item.done',
            'item': {
              'type': 'message',
              'id': 'message-1',
              'role': 'assistant',
              'status': 'completed',
              'content': [
                {'type': 'output_text', 'text': 'Hello', 'annotations': []},
              ],
            },
          },
          {
            'type': 'response.completed',
            'response': {'id': 'response-1', 'status': 'completed'},
          },
        ];
        return ResponseBody.fromString(
          events.map((event) => 'data: ${jsonEncode(event)}\n\n').join(),
          200,
          headers: {
            'content-type': ['text/event-stream'],
          },
        );
      });
    addTearDown(() => dio.close(force: true));
    final model = OpenAIProvider(apiKey: 'fixture', client: dio).responses('m');
    final first = await streamText(model: model, prompt: 'hi');
    final firstEvents = first.stream.toList();
    expect(await first.text, 'Hello');
    final history = (await firstEvents)
        .whereType<StreamTextFinishEvent>()
        .single
        .responseMessages;
    final second = await streamText(
      model: model,
      messages: [
        for (final message in history)
          ModelMessage.parts(
            role: ModelMessageRole.assistant,
            parts: message.content,
          ),
      ],
    );
    await second.text;
    expect(requests.last['input'], [
      {
        'role': 'assistant',
        'content': [
          {'type': 'input_text', 'text': 'Hello'},
        ],
      },
    ]);
  });
}
