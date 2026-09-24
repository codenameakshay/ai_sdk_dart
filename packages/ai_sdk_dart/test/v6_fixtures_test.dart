import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
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
      expect(result.finishReason, LanguageModelV4FinishReason.stop);
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
  final file = File('packages/ai_sdk_dart/test/fixtures/v6_examples/$name');
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
    StreamTextOpaqueEvent() => 'opaque',
    StreamTextUsageEvent() => 'usage',
    StreamTextErrorEvent() => 'error',
    StreamTextRawEvent() => 'raw',
    StreamTextDocumentSourceEvent() => 'document-source',
    StreamTextReasoningFileEvent() => 'reasoning-file',
  };
}

class _FixtureTextModel extends LanguageModelV4 {
  @override
  String get modelId => 'fixture-text';

  @override
  String get provider => 'fixture';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    return const LanguageModelV4GenerateResult(
      content: [
        LanguageModelV4TextPart(
          text: 'The weather in Paris is mild and cloudy.',
        ),
      ],
      finishReason: LanguageModelV4FinishReason.stop,
    );
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    throw UnimplementedError();
  }
}

class _FixtureStructuredModel extends LanguageModelV4 {
  @override
  String get modelId => 'fixture-structured';

  @override
  String get provider => 'fixture';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    return const LanguageModelV4GenerateResult(
      content: [LanguageModelV4TextPart(text: '{"city":"Paris","tempC":21}')],
      finishReason: LanguageModelV4FinishReason.stop,
    );
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    throw UnimplementedError();
  }
}

class _FixtureToolLoopModel extends LanguageModelV4 {
  @override
  String get modelId => 'fixture-tool-loop';

  @override
  String get provider => 'fixture';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    final hasToolResult = options.prompt.messages.any(
      (message) =>
          message.role == LanguageModelV4Role.tool &&
          message.content.whereType<LanguageModelV4ToolResultPart>().isNotEmpty,
    );
    if (!hasToolResult) {
      return const LanguageModelV4GenerateResult(
        content: [
          LanguageModelV4ToolCallPart(
            toolCallId: 'fixture_call_1',
            toolName: 'weather',
            input: {'city': 'San Francisco'},
          ),
        ],
        finishReason: LanguageModelV4FinishReason.toolCalls,
      );
    }
    return const LanguageModelV4GenerateResult(
      content: [LanguageModelV4TextPart(text: 'tool summary response')],
      finishReason: LanguageModelV4FinishReason.stop,
    );
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    throw UnimplementedError();
  }
}

class _FixtureStreamModel extends LanguageModelV4 {
  @override
  String get modelId => 'fixture-stream';

  @override
  String get provider => 'fixture';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    final hasToolResult = options.prompt.messages.any(
      (message) =>
          message.role == LanguageModelV4Role.tool &&
          message.content.whereType<LanguageModelV4ToolResultPart>().isNotEmpty,
    );
    if (hasToolResult) {
      return LanguageModelV4StreamResult(
        stream: Stream<LanguageModelV4StreamPart>.fromIterable(const [
          StreamPartTextStart(id: 'text-1'),
          StreamPartTextDelta(id: 'text-1', delta: 'Done'),
          StreamPartTextEnd(id: 'text-1'),
          StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
        ]),
      );
    }

    return LanguageModelV4StreamResult(
      stream: Stream<LanguageModelV4StreamPart>.fromIterable(const [
        StreamPartTextStart(id: 'text-0'),
        StreamPartTextDelta(id: 'text-0', delta: 'Hello'),
        StreamPartTextEnd(id: 'text-0'),
        StreamPartReasoningStart(id: 'reasoning-0'),
        StreamPartReasoningDelta(
          id: 'reasoning-0',
          delta: 'Because stream fixture',
        ),
        StreamPartReasoningEnd(id: 'reasoning-0'),
        StreamPartToolInputStart(id: 'call_1', toolName: 'weather'),
        StreamPartToolInputDelta(id: 'call_1', delta: '{"city":"Paris"}'),
        StreamPartToolInputEnd(id: 'call_1'),
        StreamPartToolCall(
          toolCall: LanguageModelV4ToolCallPart(
            toolCallId: 'call_1',
            toolName: 'weather',
            input: {'city': 'Paris'},
          ),
        ),
        StreamPartFinish(finishReason: LanguageModelV4FinishReason.toolCalls),
      ]),
    );
  }
}
