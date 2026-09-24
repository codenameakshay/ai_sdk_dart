import 'dart:async';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'provider_canaries.dart';

void main() {
  test('configuration requires a key and explicit model as a pair', () {
    expect(
      () => ProviderCanaryConfiguration.fromEnvironment({
        'OPENAI_API_KEY': 'present',
      }).configuredProviders,
      throwsFormatException,
    );
    expect(
      () => ProviderCanaryConfiguration.fromEnvironment({
        'OPENAI_CANARY_MODEL': 'account-model',
      }).configuredProviders,
      throwsFormatException,
    );
  });

  test('configuration trims values and keeps only configured providers', () {
    final configured = ProviderCanaryConfiguration.fromEnvironment({
      'OPENAI_API_KEY': ' key ',
      'OPENAI_CANARY_MODEL': ' model ',
    }).configuredProviders;

    expect(configured.map((provider) => provider.name), ['openai']);
    expect(configured.single.model, 'model');
    expect(configured.single.apiKey, 'key');
  });

  test(
    'offline harness executes every canary and preserves reasoning',
    () async {
      final model = _healthyModel();

      await runProviderCanary(_configuration(), modelOverride: model);

      expect(model.generateCalls, hasLength(6));
      expect(model.streamCalls, hasLength(1));
      expect(model.secondGenerationRetainedReasoning, isTrue);
    },
  );

  test('rejects empty and mismatched streaming output', () async {
    await _expectFailure(
      _healthyModel(streamText: ''),
      'text stream was empty',
    );
    await _expectFailure(
      _healthyModel(streamText: 'WRONG'),
      'text stream was not READY',
    );
  });

  test('rejects invalid structured output', () async {
    await _expectFailure(
      _healthyModel(structuredText: '{"answer":"NOT_READY"}'),
      'structured answer was not READY',
    );
  });

  test('rejects missing, wrong, and duplicate tool execution', () async {
    await _expectFailure(_healthyModel(toolCalls: const []), 'tool call count');
    await _expectFailure(
      _healthyModel(toolCalls: [_toolCall(toolName: 'other')]),
      'called "other"',
    );
    await _expectFailure(
      _healthyModel(
        toolCalls: [
          _toolCall(toolName: 'lookup'),
          _toolCall(toolName: 'lookup'),
        ],
      ),
      'tool call count',
    );
  });
}

ProviderCanaryConfig _configuration() =>
    const ProviderCanaryConfig(name: 'test', apiKey: 'key', model: 'model');

LanguageModelV4ToolCallPart _toolCall({required String toolName}) =>
    LanguageModelV4ToolCallPart(
      toolCallId: '$toolName-call',
      toolName: toolName,
      input: const {},
    );

Future<void> _expectFailure(_ScriptedModel model, String message) async {
  await expectLater(
    runProviderCanary(_configuration(), modelOverride: model),
    throwsA(predicate<Object>((error) => error.toString().contains(message))),
  );
}

_ScriptedModel _healthyModel({
  String streamText = 'READY',
  String structuredText = '{"answer":"READY"}',
  List<LanguageModelV4ToolCallPart>? toolCalls,
}) {
  final calls = toolCalls ?? [_toolCall(toolName: 'lookup')];
  final reasoning = LanguageModelV4ReasoningPart(
    text: 'thinking',
    providerOptions: const {
      'test': {'signature': 'sig-1'},
    },
  );
  return _ScriptedModel(
    generateResponses: [
      _generate([const LanguageModelV4TextPart(text: 'READY')]),
      _generate([LanguageModelV4TextPart(text: structuredText)]),
      _generate(calls),
      _generate([const LanguageModelV4TextPart(text: 'READY')]),
      _generate([reasoning, ...calls]),
      _generate([const LanguageModelV4TextPart(text: 'READY')]),
    ],
    streamText: streamText,
  );
}

LanguageModelV4GenerateResult _generate(
  List<LanguageModelV4ContentPart> content,
) => LanguageModelV4GenerateResult(
  content: content,
  finishReason: content.any((part) => part is LanguageModelV4ToolCallPart)
      ? LanguageModelV4FinishReason.toolCalls
      : LanguageModelV4FinishReason.stop,
);

class _ScriptedModel extends LanguageModelV4 {
  _ScriptedModel({required this.generateResponses, required this.streamText});

  final List<LanguageModelV4GenerateResult> generateResponses;
  final String streamText;
  final generateCalls = <LanguageModelV4CallOptions>[];
  final streamCalls = <LanguageModelV4CallOptions>[];
  bool secondGenerationRetainedReasoning = false;

  @override
  String get provider => 'test';

  @override
  String get modelId => 'test-model';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    generateCalls.add(options);
    if (generateCalls.length == 6) {
      final parts = options.prompt.messages
          .expand((message) => message.content)
          .toList();
      secondGenerationRetainedReasoning = parts.any(
        (part) =>
            part is LanguageModelV4ReasoningPart &&
            part.text == 'thinking' &&
            part.providerOptions?['test']?['signature'] == 'sig-1',
      );
    }
    if (generateResponses.isEmpty) {
      throw StateError('unexpected extra generation call');
    }
    return generateResponses.removeAt(0);
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    streamCalls.add(options);
    final id = 'stream-text';
    return LanguageModelV4StreamResult(
      stream: Stream.fromIterable([
        const StreamPartStreamStart(),
        StreamPartTextStart(id: id),
        StreamPartTextDelta(id: id, delta: streamText),
        StreamPartTextEnd(id: id),
        const StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
      ]),
    );
  }
}
