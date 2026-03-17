import 'dart:convert';
import 'dart:io';

import 'package:ai/ai.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

void main() {
  group('v6 fixture conformance', () {
    test('text-basic fixture', () async {
      final fixture = _readFixture('text-basic.json');
      final result = await generateText<String>(
        model: _FixtureTextModel(),
        prompt: fixture['input']['prompt'] as String,
      );

      expect(result.text, fixture['expected']['text']);
      expect(result.finishReason, LanguageModelV3FinishReason.stop);
    });

    test('structured-output fixture', () async {
      final fixture = _readFixture('structured-output.json');
      final result = await generateText<Map<String, dynamic>>(
        model: _FixtureStructuredModel(),
        output: Output.object(
          schema: Schema<Map<String, dynamic>>(
            jsonSchema: const {'type': 'object'},
            fromJson: (json) => json,
          ),
        ),
      );

      expect(result.output, fixture['expected']['object']);
    });

    test('tools-multistep fixture', () async {
      final fixture = _readFixture('tools-multistep.json');
      final result = await generateText<String>(
        model: _FixtureToolLoopModel(),
        maxSteps: 3,
        tools: {
          'weather': tool<Map<String, dynamic>, Map<String, dynamic>>(
            inputSchema: Schema<Map<String, dynamic>>(
              jsonSchema: const {'type': 'object'},
              fromJson: (json) => json,
            ),
            execute: (input, _) async => {'city': input['city'], 'tempC': 23},
          ),
        },
      );

      expect(
        result.steps.length,
        (fixture['expected']['steps'] as List).length,
      );
      expect(
        result.text,
        contains(fixture['expected']['finalTextContains'] as String),
      );
    });

    test('stream-events fixture', () async {
      final fixture = _readFixture('stream-events.json');
      final result = await streamText<String>(
        model: _FixtureStreamModel(),
        maxSteps: 3,
        tools: {
          'weather': tool<Map<String, dynamic>, Map<String, dynamic>>(
            inputSchema: Schema<Map<String, dynamic>>(
              jsonSchema: const {'type': 'object'},
              fromJson: (json) => json,
            ),
            execute: (input, _) async => {'city': input['city'], 'tempC': 23},
          ),
        },
      );

      final events = await result.fullStream
          .where((event) => event is! StreamTextRawEvent)
          .toList();
      final mapped = events.map(_eventName).toList();
      expect(mapped, fixture['expectedSequence']);
    });
  });
}

Map<String, dynamic> _readFixture(String name) {
  final file = File('packages/ai/test/fixtures/v6_examples/$name');
  return (jsonDecode(file.readAsStringSync()) as Map).cast<String, dynamic>();
}

String _eventName(StreamTextEvent event) {
  return switch (event) {
    StreamTextStartEvent() => 'start',
    StreamTextStartStepEvent() => 'start-step',
    StreamTextTextStartEvent() => 'text-start',
    StreamTextTextDeltaEvent() => 'text-delta',
    StreamTextTextEndEvent() => 'text-end',
    StreamTextReasoningStartEvent() => 'reasoning-start',
    StreamTextReasoningDeltaEvent() => 'reasoning-delta',
    StreamTextReasoningEndEvent() => 'reasoning-end',
    StreamTextToolInputStartEvent() => 'tool-input-start',
    StreamTextToolInputDeltaEvent() => 'tool-input-delta',
    StreamTextToolInputEndEvent() => 'tool-input-end',
    StreamTextToolResultEvent() => 'tool-result',
    StreamTextToolErrorEvent() => 'tool-error',
    StreamTextFinishStepEvent() => 'finish-step',
    StreamTextFinishEvent() => 'finish',
    StreamTextSourceEvent() => 'source',
    StreamTextFileEvent() => 'file',
    StreamTextErrorEvent() => 'error',
    StreamTextRawEvent() => 'raw',
  };
}

class _FixtureTextModel implements LanguageModelV3 {
  @override
  String get modelId => 'fixture-text';

  @override
  String get provider => 'fixture';

  @override
  String get specificationVersion => 'v3';

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async {
    return const LanguageModelV3GenerateResult(
      content: [
        LanguageModelV3TextPart(
          text: 'The weather in Paris is mild and cloudy.',
        ),
      ],
      finishReason: LanguageModelV3FinishReason.stop,
    );
  }

  @override
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  ) async {
    throw UnimplementedError();
  }
}

class _FixtureStructuredModel implements LanguageModelV3 {
  @override
  String get modelId => 'fixture-structured';

  @override
  String get provider => 'fixture';

  @override
  String get specificationVersion => 'v3';

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async {
    return const LanguageModelV3GenerateResult(
      content: [LanguageModelV3TextPart(text: '{"city":"Paris","tempC":21}')],
      finishReason: LanguageModelV3FinishReason.stop,
    );
  }

  @override
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  ) async {
    throw UnimplementedError();
  }
}

class _FixtureToolLoopModel implements LanguageModelV3 {
  @override
  String get modelId => 'fixture-tool-loop';

  @override
  String get provider => 'fixture';

  @override
  String get specificationVersion => 'v3';

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async {
    final hasToolResult = options.prompt.messages.any(
      (message) =>
          message.role == LanguageModelV3Role.tool &&
          message.content.whereType<LanguageModelV3ToolResultPart>().isNotEmpty,
    );
    if (!hasToolResult) {
      return const LanguageModelV3GenerateResult(
        content: [
          LanguageModelV3ToolCallPart(
            toolCallId: 'fixture_call_1',
            toolName: 'weather',
            input: {'city': 'San Francisco'},
          ),
        ],
        finishReason: LanguageModelV3FinishReason.toolCalls,
      );
    }
    return const LanguageModelV3GenerateResult(
      content: [LanguageModelV3TextPart(text: 'tool summary response')],
      finishReason: LanguageModelV3FinishReason.stop,
    );
  }

  @override
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  ) async {
    throw UnimplementedError();
  }
}

class _FixtureStreamModel implements LanguageModelV3 {
  @override
  String get modelId => 'fixture-stream';

  @override
  String get provider => 'fixture';

  @override
  String get specificationVersion => 'v3';

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  ) async {
    final hasToolResult = options.prompt.messages.any(
      (message) =>
          message.role == LanguageModelV3Role.tool &&
          message.content.whereType<LanguageModelV3ToolResultPart>().isNotEmpty,
    );
    if (hasToolResult) {
      return LanguageModelV3StreamResult(
        stream: Stream<LanguageModelV3StreamPart>.fromIterable(const [
          StreamPartTextStart(id: 'text-1'),
          StreamPartTextDelta(id: 'text-1', delta: 'Done'),
          StreamPartTextEnd(id: 'text-1'),
          StreamPartFinish(finishReason: LanguageModelV3FinishReason.stop),
        ]),
      );
    }

    return LanguageModelV3StreamResult(
      stream: Stream<LanguageModelV3StreamPart>.fromIterable(const [
        StreamPartTextStart(id: 'text-0'),
        StreamPartTextDelta(id: 'text-0', delta: 'Hello'),
        StreamPartTextEnd(id: 'text-0'),
        StreamPartReasoningDelta(delta: 'Because stream fixture'),
        StreamPartToolCallStart(toolCallId: 'call_1', toolName: 'weather'),
        StreamPartToolCallDelta(
          toolCallId: 'call_1',
          toolName: 'weather',
          argsTextDelta: '{"city":"Paris"}',
        ),
        StreamPartToolCallEnd(
          toolCallId: 'call_1',
          toolName: 'weather',
          input: {'city': 'Paris'},
        ),
        StreamPartFinish(finishReason: LanguageModelV3FinishReason.toolCalls),
      ]),
    );
  }
}
