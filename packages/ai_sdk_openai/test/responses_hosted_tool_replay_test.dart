import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  test('hosted call and result replay one original wire item', () async {
    final adapter = _Adapter();
    final dio = Dio()..httpClientAdapter = adapter;
    addTearDown(() => dio.close(force: true));
    final model = OpenAIProvider(
      apiKey: 'fixture',
      client: dio,
    ).responses('fixture');
    final first = await model.doGenerate(
      const LanguageModelV4CallOptions(
        prompt: LanguageModelV4Prompt(messages: []),
      ),
    );
    expect(
      first.content.whereType<LanguageModelV4ToolCallPart>(),
      hasLength(1),
    );
    expect(
      first.content.whereType<LanguageModelV4ToolResultPart>(),
      hasLength(1),
    );
    await model.doGenerate(
      LanguageModelV4CallOptions(
        prompt: LanguageModelV4Prompt(
          messages: [
            LanguageModelV4Message(
              role: LanguageModelV4Role.assistant,
              content: first.content,
            ),
          ],
        ),
      ),
    );
    final input = adapter.inputs.last;
    expect(
      input.whereType<Map>().where((item) => item['id'] == 'search-1'),
      hasLength(1),
      reason:
          'One hosted response item must not be replayed once as a call and again as its result',
    );
  });

  test(
    'streamed hosted call and result replay one original wire item',
    () async {
      final adapter = _StreamAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(() => dio.close(force: true));
      final model = OpenAIProvider(
        apiKey: 'fixture',
        client: dio,
      ).responses('fixture');

      final first = await model.doStream(
        const LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(messages: []),
        ),
      );
      final firstParts = await first.stream.toList();
      final firstContent = [
        for (final part in firstParts)
          if (part case StreamPartToolCall(:final toolCall))
            toolCall
          else if (part case StreamPartToolResult(:final toolResult))
            toolResult,
      ];
      expect(firstContent, hasLength(2));

      final second = await model.doStream(
        LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(
            messages: [
              LanguageModelV4Message(
                role: LanguageModelV4Role.assistant,
                content: firstContent,
              ),
            ],
          ),
        ),
      );
      await second.stream.drain<void>();
      final input = adapter.inputs.last;
      expect(
        input.whereType<Map>().where((item) => item['id'] == 'search-1'),
        hasLength(1),
      );
    },
  );
}

class _Adapter implements HttpClientAdapter {
  final inputs = <List<dynamic>>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    inputs.add((options.data as Map)['input'] as List<dynamic>);
    return ResponseBody.fromString(
      jsonEncode({
        'id': 'response-${inputs.length}',
        'status': 'completed',
        'output': inputs.length == 1
            ? [
                {
                  'type': 'web_search_call',
                  'id': 'search-1',
                  'status': 'completed',
                  'action': {'type': 'search', 'query': 'Dart'},
                },
              ]
            : [],
      }),
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _StreamAdapter implements HttpClientAdapter {
  final inputs = <List<dynamic>>[];
  var requests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    inputs.add((options.data as Map)['input'] as List<dynamic>);
    requests++;
    final events = requests == 1
        ? [
            {
              'type': 'response.output_item.done',
              'item': {
                'type': 'web_search_call',
                'id': 'search-1',
                'status': 'completed',
                'action': {'type': 'search', 'query': 'Dart'},
              },
            },
            {
              'type': 'response.completed',
              'response': {'id': 'response-1', 'status': 'completed'},
            },
          ]
        : [
            {
              'type': 'response.completed',
              'response': {'id': 'response-2', 'status': 'completed'},
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
