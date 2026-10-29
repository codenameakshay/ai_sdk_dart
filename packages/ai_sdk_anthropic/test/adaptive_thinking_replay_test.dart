import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_anthropic/ai_sdk_anthropic.dart';
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import '../../ai_sdk_provider/test/support/prompts.dart';
import '../../ai_sdk_provider/test/support/test_server.dart';

// Adaptive thinking on current Claude models returns a thinking block whose
// text is empty but whose signature is set. The block must survive parsing so
// that tool-use continuations can send it back unchanged.

const _signature = 'CAQSsignedAdaptiveThinking==';

const _signedEmptyThinking = {
  'type': 'thinking',
  'thinking': '',
  'signature': _signature,
};

const _toolUse = {
  'type': 'tool_use',
  'id': 'toolu_01',
  'name': 'getWeather',
  'input': {'city': 'Paris'},
};

Map<String, Object?> _message(
  String id,
  List<Map<String, Object?>> content,
  String stopReason,
) => {
  'id': id,
  'type': 'message',
  'role': 'assistant',
  'model': 'claude-haiku-5-5',
  'content': content,
  'stop_reason': stopReason,
  'stop_sequence': null,
  'usage': {'input_tokens': 10, 'output_tokens': 5},
};

String _sse(List<Map<String, Object?>> events) => [
  for (final event in events)
    'event: ${event['type']}\ndata: ${jsonEncode(event)}\n\n',
].join();

/// The SSE events Anthropic sends for one content block.
List<Map<String, Object?>> _blockEvents(int index, Map<String, Object?> block) {
  Map<String, Object?> start(Map<String, Object?> contentBlock) => {
    'type': 'content_block_start',
    'index': index,
    'content_block': contentBlock,
  };
  Map<String, Object?> delta(Map<String, Object?> delta) => {
    'type': 'content_block_delta',
    'index': index,
    'delta': delta,
  };
  return [
    ...switch (block['type']) {
      'thinking' => [
        start({'type': 'thinking', 'thinking': '', 'signature': ''}),
        if ((block['thinking'] as String).isNotEmpty)
          delta({'type': 'thinking_delta', 'thinking': block['thinking']}),
        delta({'type': 'signature_delta', 'signature': block['signature']}),
      ],
      'redacted_thinking' => [start(block)],
      'tool_use' => [
        start({...block, 'input': const <String, Object?>{}}),
        delta({
          'type': 'input_json_delta',
          'partial_json': jsonEncode(block['input']),
        }),
      ],
      _ => [
        start({'type': 'text', 'text': ''}),
        delta({'type': 'text_delta', 'text': block['text']}),
      ],
    },
    {'type': 'content_block_stop', 'index': index},
  ];
}

List<Map<String, Object?>> _streamEvents(
  String id,
  List<Map<String, Object?>> blocks,
  String stopReason,
) => [
  {
    'type': 'message_start',
    'message': {..._message(id, const [], stopReason), 'stop_reason': null},
  },
  for (var i = 0; i < blocks.length; i++) ..._blockEvents(i, blocks[i]),
  {
    'type': 'message_delta',
    'delta': {'stop_reason': stopReason, 'stop_sequence': null},
    'usage': {'output_tokens': 5},
  },
  {'type': 'message_stop'},
];

/// Answers each request with the next scripted response and records the
/// decoded request bodies.
Future<(TestServer, List<Map<String, dynamic>>)> _scriptedServer(
  List<String> responses, {
  required bool stream,
}) async {
  final requests = <Map<String, dynamic>>[];
  final server = await TestServer.start((request) async {
    final body = await utf8.decoder.bind(request).join();
    requests.add((jsonDecode(body) as Map).cast<String, dynamic>());
    request.response.statusCode = 200;
    request.response.headers.contentType = stream
        ? ContentType('text', 'event-stream')
        : ContentType.json;
    request.response.write(responses[requests.length - 1]);
    await request.response.close();
  }, pathSuffix: '/v1');
  addTearDown(server.close);
  return (server, requests);
}

final _weatherTool = tool<Map<String, dynamic>, String>(
  description: 'Get current weather for a city.',
  inputSchema: Schema<Map<String, dynamic>>(
    jsonSchema: const {
      'type': 'object',
      'properties': {
        'city': {'type': 'string'},
      },
      'required': ['city'],
    },
    fromJson: (json) => json,
  ),
  execute: (input, _) async => 'Sunny in ${input['city']}',
);

final _adaptiveOptions = {
  'anthropic': const AnthropicLanguageModelOptions(
    thinking: AnthropicThinkingOptions(adaptive: true),
    effort: 'high',
  ).toMap(),
};

List<Map> _replayedAssistantContent(Map<String, dynamic> request) {
  final messages = (request['messages'] as List).cast<Map>();
  final assistant = messages.lastWhere((m) => m['role'] == 'assistant');
  return (assistant['content'] as List).cast<Map>();
}

void main() {
  group('doGenerate', () {
    test('keeps an empty-text signed thinking block as reasoning', () async {
      final (server, _) = await _scriptedServer([
        jsonEncode(
          _message('msg_1', [
            _signedEmptyThinking,
            {'type': 'text', 'text': '271'},
          ], 'end_turn'),
        ),
      ], stream: false);

      final result =
          await AnthropicProvider(apiKey: 'test', baseUrl: server.baseUrl)
              .call('claude-haiku-5-5')
              .doGenerate(
                LanguageModelV4CallOptions(
                  prompt: userPrompt('trip length?'),
                  providerOptions: _adaptiveOptions,
                ),
              );

      final reasoning = result.content
          .whereType<LanguageModelV4ReasoningPart>()
          .single;
      expect(reasoning.text, isEmpty);
      expect(reasoning.signature, _signature);
    });

    test('drops a thinking block with neither text nor signature', () async {
      final (server, _) = await _scriptedServer([
        jsonEncode(
          _message('msg_1', [
            {'type': 'thinking', 'thinking': '', 'signature': ''},
            {'type': 'text', 'text': 'ok'},
          ], 'end_turn'),
        ),
      ], stream: false);

      final result =
          await AnthropicProvider(apiKey: 'test', baseUrl: server.baseUrl)
              .call('claude-haiku-5-5')
              .doGenerate(LanguageModelV4CallOptions(prompt: userPrompt('hi')));

      expect(result.content.whereType<LanguageModelV4ReasoningPart>(), isEmpty);
      expect(
        result.content.whereType<LanguageModelV4TextPart>().single.text,
        'ok',
      );
    });
  });

  group('doStream', () {
    test('a signature-only thinking block ends with its signature', () async {
      final (server, _) = await _scriptedServer([
        _sse(
          _streamEvents('msg_1', [
            _signedEmptyThinking,
            {'type': 'text', 'text': '271'},
          ], 'end_turn'),
        ),
      ], stream: true);

      final result =
          await AnthropicProvider(apiKey: 'test', baseUrl: server.baseUrl)
              .call('claude-haiku-5-5')
              .doStream(
                LanguageModelV4CallOptions(
                  prompt: userPrompt('trip length?'),
                  providerOptions: _adaptiveOptions,
                ),
              );
      final parts = await result.stream.toList();

      expect(parts.whereType<StreamPartReasoningDelta>(), isEmpty);
      final start = parts.whereType<StreamPartReasoningStart>().single;
      final end = parts.whereType<StreamPartReasoningEnd>().single;
      expect(end.id, start.id);
      expect(end.signature, _signature);
    });

    test('a signature delta without a block start still ends signed', () async {
      final (server, _) = await _scriptedServer([
        _sse([
          {
            'type': 'message_start',
            'message': _message('msg_1', const [], 'end_turn'),
          },
          {
            'type': 'content_block_delta',
            'index': 0,
            'delta': {'type': 'signature_delta', 'signature': _signature},
          },
          {'type': 'content_block_stop', 'index': 0},
          {
            'type': 'message_delta',
            'delta': {'stop_reason': 'end_turn'},
            'usage': {'output_tokens': 1},
          },
          {'type': 'message_stop'},
        ]),
      ], stream: true);

      final result =
          await AnthropicProvider(apiKey: 'test', baseUrl: server.baseUrl)
              .call('claude-haiku-5-5')
              .doStream(LanguageModelV4CallOptions(prompt: userPrompt('hi')));
      final parts = await result.stream.toList();

      expect(parts.whereType<StreamPartReasoningStart>(), hasLength(1));
      expect(
        parts.whereType<StreamPartReasoningEnd>().single.signature,
        _signature,
      );
    });

    test('streamText exposes the empty signed block as reasoning', () async {
      final (server, _) = await _scriptedServer([
        _sse(
          _streamEvents('msg_1', [
            _signedEmptyThinking,
            {'type': 'text', 'text': '271'},
          ], 'end_turn'),
        ),
      ], stream: true);

      final result = await streamText(
        model: AnthropicProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).call('claude-haiku-5-5'),
        prompt: 'trip length?',
        maxRetries: 0,
        providerOptions: _adaptiveOptions,
      );

      final reasoning = (await result.reasoning).single;
      expect(reasoning.text, isEmpty);
      expect(reasoning.signature, _signature);
      expect(await result.text, '271');
    });
  });

  group('tool-loop continuation replays the signed thinking block', () {
    // Budget-mode thinking with text and a redacted block must keep working
    // next to the adaptive empty-text case.
    final cases = <String, List<Map<String, Object?>>>{
      'adaptive empty text': [_signedEmptyThinking, _toolUse],
      'budget text and redacted': [
        {
          'type': 'thinking',
          'thinking': 'I should call the tool.',
          'signature': _signature,
        },
        {'type': 'redacted_thinking', 'data': 'EmwKAhgBEgy3va3pzix'},
        _toolUse,
      ],
    };

    for (final MapEntry(key: name, value: firstBlocks) in cases.entries) {
      test('generateText: $name', () async {
        final (server, requests) = await _scriptedServer([
          jsonEncode(_message('msg_1', firstBlocks, 'tool_use')),
          jsonEncode(
            _message('msg_2', [
              {'type': 'text', 'text': 'It is sunny in Paris.'},
            ], 'end_turn'),
          ),
        ], stream: false);

        final result = await generateText(
          model: AnthropicProvider(
            apiKey: 'test',
            baseUrl: server.baseUrl,
          ).call('claude-haiku-5-5'),
          prompt: 'Weather in Paris?',
          maxRetries: 0,
          maxSteps: 3,
          tools: {'getWeather': _weatherTool},
          providerOptions: _adaptiveOptions,
        );

        expect(result.text, 'It is sunny in Paris.');
        expect(requests, hasLength(2));
        expect(_replayedAssistantContent(requests[1]), firstBlocks);
      });

      test('streamText: $name', () async {
        final (server, requests) = await _scriptedServer([
          _sse(_streamEvents('msg_1', firstBlocks, 'tool_use')),
          _sse(
            _streamEvents('msg_2', [
              {'type': 'text', 'text': 'It is sunny in Paris.'},
            ], 'end_turn'),
          ),
        ], stream: true);

        final result = await streamText(
          model: AnthropicProvider(
            apiKey: 'test',
            baseUrl: server.baseUrl,
          ).call('claude-haiku-5-5'),
          prompt: 'Weather in Paris?',
          maxRetries: 0,
          maxSteps: 3,
          tools: {'getWeather': _weatherTool},
          providerOptions: _adaptiveOptions,
        );

        expect(await result.text, 'It is sunny in Paris.');
        expect(requests, hasLength(2));
        expect(_replayedAssistantContent(requests[1]), firstBlocks);
      });
    }
  });
}
