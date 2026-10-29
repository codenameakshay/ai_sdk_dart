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

final _budgetOptions = {
  'anthropic': const AnthropicLanguageModelOptions(
    thinking: AnthropicThinkingOptions(budgetTokens: 1024),
  ).toMap(),
};

List<Map> _replayedAssistantContent(Map<String, dynamic> request) {
  final messages = (request['messages'] as List).cast<Map>();
  final assistant = messages.lastWhere((m) => m['role'] == 'assistant');
  return (assistant['content'] as List).cast<Map>();
}

LanguageModelV4Prompt _assistantPrompt(
  List<LanguageModelV4ContentPart> content,
) => LanguageModelV4Prompt(
  messages: [
    LanguageModelV4Message(
      role: LanguageModelV4Role.user,
      content: [const LanguageModelV4TextPart(text: 'continue')],
    ),
    LanguageModelV4Message(
      role: LanguageModelV4Role.assistant,
      content: content,
    ),
    LanguageModelV4Message(
      role: LanguageModelV4Role.user,
      content: [const LanguageModelV4TextPart(text: 'continue')],
    ),
  ],
);

Future<List<Map>> _serializePromptReasoning(
  List<LanguageModelV4ContentPart> content, {
  ProviderOptions? providerOptions,
}) async {
  final (server, requests) = await _scriptedServer([
    jsonEncode(_message('msg_1', const [], 'end_turn')),
  ], stream: false);
  await AnthropicProvider(apiKey: 'test', baseUrl: server.baseUrl)
      .call('claude-haiku-5-5')
      .doGenerate(
        LanguageModelV4CallOptions(
          prompt: _assistantPrompt(content),
          providerOptions: providerOptions,
        ),
      );
  final messages = (requests.single['messages'] as List).cast<Map>();
  final assistant = messages.where((message) => message['role'] == 'assistant');
  return assistant.isEmpty
      ? const []
      : (assistant.last['content'] as List).cast<Map>();
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

  group('prompt reasoning replay', () {
    test(
      'signature wins over stale redacted metadata; unsigned text is dropped',
      () async {
        final stale = {
          'anthropic': {'redactedData': 'stale'},
        };
        final content = <LanguageModelV4ContentPart>[
          LanguageModelV4ReasoningPart(
            text: 'budget thoughts',
            signature: 'signed',
            providerOptions: stale,
          ),
          LanguageModelV4ReasoningPart(
            text: '',
            signature: 'signature-only',
            providerOptions: stale,
          ),
          LanguageModelV4ReasoningPart(
            text: 'unsigned thoughts',
            providerOptions: stale,
          ),
          LanguageModelV4ReasoningPart(
            text: 'mixed metadata',
            signature: 'mixed-signed',
            providerOptions: {
              'anthropic': {'redactedData': 'stale'},
              'other': {'signature': 'must-not-override'},
            },
          ),
          LanguageModelV4ReasoningPart(
            text: '',
            providerOptions: {
              'anthropic': {'redactedData': 'ciphertext'},
            },
          ),
        ];

        expect(
          await _serializePromptReasoning(
            content,
            providerOptions: _budgetOptions,
          ),
          [
            {
              'type': 'thinking',
              'thinking': 'budget thoughts',
              'signature': 'signed',
            },
            {'type': 'thinking', 'thinking': '', 'signature': 'signature-only'},
            {
              'type': 'thinking',
              'thinking': 'mixed metadata',
              'signature': 'mixed-signed',
            },
            {'type': 'redacted_thinking', 'data': 'ciphertext'},
          ],
        );
      },
    );

    test(
      'invalid redacted metadata never turns unsigned reasoning into redacted',
      () async {
        final invalidOptions = <Map<String, dynamic>>[
          {
            'anthropic': {'redactedData': ''},
          },
          {
            'anthropic': {'redactedData': 123},
          },
          {'anthropic': 'malformed'},
          {
            'other': {'redactedData': 'unrelated'},
          },
          const {},
        ];

        expect(
          await _serializePromptReasoning([
            for (final providerOptions in invalidOptions)
              LanguageModelV4ReasoningPart(
                text: '',
                providerOptions: providerOptions,
              ),
            const LanguageModelV4TextPart(text: 'assistant text'),
          ]),
          [
            {'type': 'text', 'text': 'assistant text'},
          ],
        );
      },
    );

    test(
      'drops empty unsigned reasoning but retains signed and redacted parts',
      () async {
        expect(
          await _serializePromptReasoning([
            const LanguageModelV4ReasoningPart(text: '', signature: ''),
            const LanguageModelV4ReasoningPart(text: 'plain unsigned'),
            const LanguageModelV4ReasoningPart(text: '', signature: 'valid'),
            const LanguageModelV4ReasoningPart(
              text: '',
              providerOptions: {
                'anthropic': {'redactedData': 'ciphertext'},
              },
            ),
          ]),
          [
            {'type': 'thinking', 'thinking': '', 'signature': 'valid'},
            {'type': 'redacted_thinking', 'data': 'ciphertext'},
          ],
        );
      },
    );
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

    test(
      'fragmented signature without start is flushed at message end',
      () async {
        final (server, _) = await _scriptedServer([
          _sse([
            {
              'type': 'message_start',
              'message': _message('msg_1', const [], 'end_turn'),
            },
            for (final fragment in ['CAQS', 'signedAdaptiveThinking', '=='])
              {
                'type': 'content_block_delta',
                'index': 4,
                'delta': {'type': 'signature_delta', 'signature': fragment},
              },
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
      },
    );

    test(
      'empty unsigned blocks are silent at block stop and terminal flush',
      () async {
        for (final terminalFlush in [false, true]) {
          final events = _streamEvents('msg_1', [
            {'type': 'thinking', 'thinking': '', 'signature': ''},
            {'type': 'text', 'text': 'ok'},
            _signedEmptyThinking,
          ], 'end_turn');
          if (terminalFlush) {
            events.removeWhere(
              (event) =>
                  event['type'] == 'content_block_stop' && event['index'] != 1,
            );
          }
          final (server, _) = await _scriptedServer([
            _sse(events),
          ], stream: true);

          final result =
              await AnthropicProvider(apiKey: 'test', baseUrl: server.baseUrl)
                  .call('claude-haiku-5-5')
                  .doStream(
                    LanguageModelV4CallOptions(prompt: userPrompt('hi')),
                  );
          final parts = await result.stream.toList();
          expect(parts.whereType<StreamPartReasoningStart>(), hasLength(1));
          expect(parts.whereType<StreamPartReasoningDelta>(), isEmpty);
          expect(
            parts.whereType<StreamPartReasoningEnd>().single.signature,
            _signature,
          );
          expect(parts.whereType<StreamPartTextDelta>().single.delta, 'ok');
        }
      },
    );

    test('redacted blocks without data are silent', () async {
      final (server, _) = await _scriptedServer([
        _sse(
          _streamEvents('msg_1', [
            {'type': 'redacted_thinking'},
            {'type': 'redacted_thinking', 'data': ''},
            {'type': 'text', 'text': 'ok'},
          ], 'end_turn'),
        ),
      ], stream: true);

      final result =
          await AnthropicProvider(apiKey: 'test', baseUrl: server.baseUrl)
              .call('claude-haiku-5-5')
              .doStream(LanguageModelV4CallOptions(prompt: userPrompt('hi')));
      final parts = await result.stream.toList();

      expect(parts.whereType<StreamPartReasoningStart>(), isEmpty);
      expect(parts.whereType<StreamPartReasoningEnd>(), isEmpty);
      expect(parts.whereType<StreamPartTextDelta>().single.delta, 'ok');
    });

    test(
      'reused block index does not leak redacted metadata or signatures',
      () async {
        final (server, _) = await _scriptedServer([
          _sse([
            {
              'type': 'message_start',
              'message': _message('msg_1', const [], 'end_turn'),
            },
            {
              'type': 'content_block_start',
              'index': 0,
              'content_block': {
                'type': 'redacted_thinking',
                'data': 'ciphertext',
              },
            },
            {'type': 'content_block_stop', 'index': 0},
            {
              'type': 'content_block_start',
              'index': 0,
              'content_block': {
                'type': 'thinking',
                'thinking': '',
                'signature': '',
              },
            },
            {
              'type': 'content_block_delta',
              'index': 0,
              'delta': {
                'type': 'signature_delta',
                'signature': 'next-signature',
              },
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
        final starts = parts.whereType<StreamPartReasoningStart>().toList();
        final ends = parts.whereType<StreamPartReasoningEnd>().toList();

        expect(starts, hasLength(2));
        expect(starts[0].providerMetadata, {
          'anthropic': {'redactedData': 'ciphertext'},
        });
        expect(starts[1].providerMetadata, isNull);
        expect(ends.map((part) => part.signature), [null, 'next-signature']);
      },
    );

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

    test('streamText omits an unsigned empty reasoning part', () async {
      final (server, _) = await _scriptedServer([
        _sse(
          _streamEvents('msg_1', [
            {'type': 'thinking', 'thinking': '', 'signature': ''},
            {'type': 'text', 'text': 'ok'},
          ], 'end_turn'),
        ),
      ], stream: true);

      final result = await streamText(
        model: AnthropicProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).call('claude-haiku-5-5'),
        prompt: 'hi',
        maxRetries: 0,
      );

      expect(await result.reasoning, isEmpty);
      expect(await result.text, 'ok');
    });
  });

  group('tool-loop continuation replays the signed thinking block', () {
    // Budget-mode thinking with text and a redacted block must keep working
    // next to the adaptive empty-text case.
    final cases = {
      'adaptive empty text': (
        blocks: [_signedEmptyThinking, _toolUse],
        options: _adaptiveOptions,
      ),
      'budget text and redacted': (
        blocks: [
          {
            'type': 'thinking',
            'thinking': 'I should call the tool.',
            'signature': _signature,
          },
          {'type': 'redacted_thinking', 'data': 'EmwKAhgBEgy3va3pzix'},
          _toolUse,
        ],
        options: _budgetOptions,
      ),
      'combined thinking blocks': (
        blocks: [
          _signedEmptyThinking,
          {
            'type': 'thinking',
            'thinking': 'Budget-mode thought.',
            'signature': 'budget-signature',
          },
          {'type': 'redacted_thinking', 'data': 'opaque'},
          _signedEmptyThinking,
          _toolUse,
        ],
        options: _budgetOptions,
      ),
    };

    for (final MapEntry(key: name, value: testCase) in cases.entries) {
      final firstBlocks = testCase.blocks;
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
          providerOptions: testCase.options,
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
          providerOptions: testCase.options,
        );

        expect(await result.text, 'It is sunny in Paris.');
        expect(requests, hasLength(2));
        expect(_replayedAssistantContent(requests[1]), firstBlocks);
      });
    }

    test(
      'streamText keeps reasoning metadata isolated across tool steps',
      () async {
        final secondToolUse = {..._toolUse, 'id': 'toolu_02'};
        final firstBlocks = [
          {'type': 'redacted_thinking', 'data': 'first-cipher'},
          _toolUse,
        ];
        final secondBlocks = [
          {
            'type': 'thinking',
            'thinking': 'second step',
            'signature': 'second-signature',
          },
          secondToolUse,
        ];
        final (server, requests) = await _scriptedServer([
          _sse(_streamEvents('msg_1', firstBlocks, 'tool_use')),
          _sse(_streamEvents('msg_2', secondBlocks, 'tool_use')),
          _sse(
            _streamEvents('msg_3', [
              {'type': 'text', 'text': 'done'},
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
          providerOptions: _budgetOptions,
        );

        expect(await result.text, 'done');
        expect(requests, hasLength(3));
        final assistantContents = (requests.last['messages'] as List)
            .cast<Map>()
            .where((message) => message['role'] == 'assistant')
            .map((message) => (message['content'] as List).cast<Map>())
            .toList();
        expect(assistantContents, [firstBlocks, secondBlocks]);
      },
    );
  });
}
