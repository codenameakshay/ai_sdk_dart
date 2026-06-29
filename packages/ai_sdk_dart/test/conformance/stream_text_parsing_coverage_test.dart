import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

/// Drives the JSON-extraction / partial-array / message-conversion helpers and
/// the remaining tool/output edge branches inside `streamText`.
void main() {
  Schema<Map<String, dynamic>> objectSchema() => Schema<Map<String, dynamic>>(
    jsonSchema: const {'type': 'object'},
    fromJson: (json) => json,
  );

  FakeStreamModel chunkedText(String text) {
    return FakeStreamModel([
      const StreamPartTextStart(id: 't1'),
      for (final ch in text.split('')) StreamPartTextDelta(id: 't1', delta: ch),
      const StreamPartTextEnd(id: 't1'),
      StreamPartFinish(finishReason: LanguageModelV3FinishReason.stop),
    ]);
  }

  group('streamText messages conversion', () {
    test('messages of every role are forwarded to the model', () async {
      final model = _CapturingStreamModel('hi');
      final result = await streamText(
        model: model,
        messages: const [
          ModelMessage(role: ModelMessageRole.system, content: 's'),
          ModelMessage(role: ModelMessageRole.user, content: 'u'),
          ModelMessage(role: ModelMessageRole.assistant, content: 'a'),
          ModelMessage(role: ModelMessageRole.tool, content: 't'),
        ],
      );
      await result.fullStream.toList();
      final roles = model.lastOptions!.prompt.messages
          .map((m) => m.role.name)
          .toList();
      expect(roles, ['system', 'user', 'assistant', 'tool']);
    });

    test('ModelMessage.parts content is preserved', () async {
      final model = _CapturingStreamModel('hi');
      final result = await streamText(
        model: model,
        messages: const [
          ModelMessage.parts(
            role: ModelMessageRole.user,
            parts: [LanguageModelV3TextPart(text: 'partbody')],
          ),
        ],
      );
      await result.fullStream.toList();
      final firstPart = model.lastOptions!.prompt.messages.first.content.first;
      expect((firstPart as LanguageModelV3TextPart).text, 'partbody');
    });
  });

  group('streamText reasoning finalization', () {
    test('reasoning-only stream closes reasoning at end of loop', () async {
      final model = FakeStreamModel([
        const StreamPartReasoningDelta(delta: 'just '),
        const StreamPartReasoningDelta(delta: 'thinking'),
        StreamPartFinish(finishReason: LanguageModelV3FinishReason.stop),
      ]);
      final result = await streamText(model: model, prompt: 'go');
      final events = await result.fullStream.toList();
      expect(events.whereType<StreamTextReasoningStartEvent>(), hasLength(1));
      expect(events.whereType<StreamTextReasoningEndEvent>(), hasLength(1));
      expect(await result.reasoningText, 'just thinking');
    });

    test('reasoning still open at stream end is closed in the finalizer',
        () async {
      // No finish part: the in-loop close (triggered by non-reasoning parts)
      // never fires, so the post-loop finalizer closes the reasoning block.
      final model = FakeStreamModel([
        const StreamPartReasoningDelta(delta: 'dangling'),
      ]);
      final result = await streamText(model: model, prompt: 'go');
      final events = await result.fullStream.toList();
      expect(events.whereType<StreamTextReasoningEndEvent>(), hasLength(1));
      expect(await result.reasoningText, 'dangling');
    });
  });

  group('streamText output JSON extraction', () {
    test('object output extracts JSON from surrounding prose', () async {
      final model = chunkedText('Here is the result: {"a":1} thanks!');
      final result = await streamText<Map<String, dynamic>>(
        model: model,
        prompt: 'json',
        output: Output.object(schema: objectSchema()),
      );
      expect(await result.output, {'a': 1});
    });

    test('object output extracts JSON from a fenced code block', () async {
      final model = chunkedText('```json\n{"b":2}\n```');
      final result = await streamText<Map<String, dynamic>>(
        model: model,
        prompt: 'json',
        output: Output.object(schema: objectSchema()),
      );
      expect(await result.output, {'b': 2});
    });

    test('array output throws when the value is not a JSON array', () async {
      final model = chunkedText('{"not":"an array"}');
      final result = await streamText<List<dynamic>>(
        model: model,
        prompt: 'json',
        output: Output.array(element: objectSchema()),
      );
      final expectation = expectLater(
        result.output,
        throwsA(isA<AiNoObjectGeneratedError>()),
      );
      await result.fullStream.toList();
      await expectation;
    });

    test('partial array elements stream incrementally', () async {
      // Stream a 3-element array char-by-char so partial flushes happen.
      final model = chunkedText('[{"i":1},{"i":2},{"i":3}]');
      final result = await streamText<List<dynamic>>(
        model: model,
        prompt: 'json',
        output: Output.array(element: objectSchema()),
      );
      final elements = await result.elementStream.toList();
      expect(elements.length, 3);
      expect((elements.last as Map)['i'], 3);
    });

    test('array embedded in prose is extracted via the manual tokenizer',
        () async {
      // jsonDecode of the whole text fails, but _extractJsonCandidate finds
      // the balanced [...] and the manual element tokenizer parses it.
      final model = chunkedText('Here you go: [{"i":1}, {"i":2}] done.');
      final result = await streamText<List<dynamic>>(
        model: model,
        prompt: 'json',
        output: Output.array(element: objectSchema()),
      );
      final output = await result.output;
      expect(output.length, 2);
      expect((output.last as Map)['i'], 2);
    });

    test('malformed array element is skipped by the manual tokenizer',
        () async {
      // The balanced [...] candidate fails a full jsonDecode (the bare token
      // "undefined" is not JSON), forcing element-by-element tokenization,
      // which decodes the valid objects and skips the bad token.
      final model = chunkedText('[{"i":1}, undefined, {"i":2}]');
      final result = await streamText<List<dynamic>>(
        model: model,
        prompt: 'json',
        output: Output.array(element: objectSchema()),
      );
      // The final full-array parse rejects the malformed token; observe it.
      final outputExpectation = expectLater(
        result.output,
        throwsA(isA<AiNoObjectGeneratedError>()),
      );
      final elements = await result.elementStream.toList();
      // Two valid elements survive the per-element tokenizer; the bad one is
      // dropped.
      expect(elements.length, 2);
      expect((elements.first as Map)['i'], 1);
      expect((elements.last as Map)['i'], 2);
      await outputExpectation;
    });

    test('tokenizer skips empty tokens from stray commas', () async {
      // The doubled comma yields an empty token that the tokenizer skips,
      // while the malformed bare word forces element-by-element parsing.
      final model = chunkedText('[{"i":1}, , undefined, {"i":2}]');
      final result = await streamText<List<dynamic>>(
        model: model,
        prompt: 'json',
        output: Output.array(element: objectSchema()),
      );
      final outputExpectation = expectLater(
        result.output,
        throwsA(isA<AiNoObjectGeneratedError>()),
      );
      final elements = await result.elementStream.toList();
      expect(elements.length, 2);
      await outputExpectation;
    });

    test('json output parses fenced JSON', () async {
      final model = chunkedText('```\n{"ok":true}\n```');
      final result = await streamText<Object?>(
        model: model,
        prompt: 'json',
        output: Output.json(),
      );
      final out = await result.output as Map<String, dynamic>;
      expect(out['ok'], isTrue);
    });

    test('array of scalars rejected when object elements are required',
        () async {
      // The final parse encounters scalar array elements and rejects them.
      final model = chunkedText('[1, 2, 3]');
      final result = await streamText<List<dynamic>>(
        model: model,
        prompt: 'json',
        output: Output.array(element: objectSchema()),
      );
      final outputExpectation = expectLater(
        result.output,
        throwsA(isA<AiNoObjectGeneratedError>()),
      );
      await result.fullStream.toList();
      await outputExpectation;
    });

    test('object output rejects a non-object JSON value', () async {
      // A bare JSON array is valid JSON but not an object → rejected.
      final model = chunkedText('[1, 2]');
      final result = await streamText<Map<String, dynamic>>(
        model: model,
        prompt: 'json',
        output: Output.object(schema: objectSchema()),
      );
      final outputExpectation = expectLater(
        result.output,
        throwsA(isA<AiNoObjectGeneratedError>()),
      );
      await result.fullStream.toList();
      await outputExpectation;
    });
  });

  group('streamText tool input parsing', () {
    test('strict dynamic tool rejects non-object input', () async {
      final model = _StreamSingleToolModel(
        toolName: 'dyn',
        // A bare list is not a JSON object → strict dynamic tool rejects it.
        input: const [1, 2, 3],
      );
      final result = await streamText(
        model: model,
        prompt: 'go',
        maxSteps: 1,
        tools: {
          'dyn': dynamicTool<String>(
            strict: true,
            execute: (_, __) async => 'ran',
          ),
        },
      );
      final events = await result.fullStream.toList();
      final toolResults = events
          .whereType<StreamTextToolResultEvent>()
          .where((e) => !e.preliminary)
          .toList();
      expect(toolResults.single.toolResult.isError, isTrue);
    });

    test('non-dynamic tool with non-object input errors', () async {
      final model = _StreamSingleToolModel(
        toolName: 'echo',
        input: 'a bare string',
      );
      final result = await streamText(
        model: model,
        prompt: 'go',
        maxSteps: 1,
        tools: {
          'echo': tool<Map<String, dynamic>, String>(
            inputSchema: objectSchema(),
            execute: (_, __) async => 'ran',
          ),
        },
      );
      final events = await result.fullStream.toList();
      final toolResults = events
          .whereType<StreamTextToolResultEvent>()
          .where((e) => !e.preliminary)
          .toList();
      expect(toolResults.single.toolResult.isError, isTrue);
    });

    test('tool with no executor returns an error result', () async {
      final model = _StreamSingleToolModel(toolName: 'noop', input: const {});
      final result = await streamText(
        model: model,
        prompt: 'go',
        maxSteps: 1,
        tools: {
          // A tool with no executor at all must report an error result.
          'noop': tool<Map<String, dynamic>, String>(
            inputSchema: objectSchema(),
          ),
        },
      );
      final events = await result.fullStream.toList();
      final toolResults = events
          .whereType<StreamTextToolResultEvent>()
          .where((e) => !e.preliminary)
          .toList();
      expect(toolResults.single.toolResult.isError, isTrue);
      expect(
        (toolResults.single.toolResult.output as ToolResultOutputText).text,
        contains('no executor'),
      );
    });
  });

  group('streamText preliminary onChunk', () {
    test('onChunk receives preliminary tool-result chunks', () async {
      final model = _ToolThenText(toolName: 'stream', finalText: 'done');
      final prelimChunks = <bool>[];
      final result = await streamText(
        model: model,
        prompt: 'go',
        maxSteps: 3,
        tools: {
          'stream': tool<Map<String, dynamic>, Object?>(
            inputSchema: objectSchema(),
            execute: (_, __) async => Stream.fromIterable(['x', 'y']),
          ),
        },
        onChunk: (chunk) {
          if (chunk is StreamTextToolResultChunk) {
            prelimChunks.add(chunk.preliminary);
          }
        },
      );
      await result.fullStream.toList();
      // One preliminary (x) + one final (y).
      expect(prelimChunks.where((p) => p).length, 1);
      expect(prelimChunks.where((p) => !p).length, 1);
    });
  });

}

// ---------------------------------------------------------------------------
// Helper models
// ---------------------------------------------------------------------------

class _CapturingStreamModel implements LanguageModelV3 {
  _CapturingStreamModel(this.text);
  final String text;
  LanguageModelV3CallOptions? lastOptions;

  @override
  String get provider => 'fake';
  @override
  String get modelId => 'capturing-stream';
  @override
  String get specificationVersion => 'v3';

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async {
    lastOptions = options;
    return LanguageModelV3GenerateResult(
      content: [LanguageModelV3TextPart(text: text)],
      finishReason: LanguageModelV3FinishReason.stop,
    );
  }

  @override
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  ) async {
    lastOptions = options;
    return LanguageModelV3StreamResult(
      stream: Stream<LanguageModelV3StreamPart>.fromIterable([
        const StreamPartTextStart(id: 't1'),
        StreamPartTextDelta(id: 't1', delta: text),
        const StreamPartTextEnd(id: 't1'),
        StreamPartFinish(finishReason: LanguageModelV3FinishReason.stop),
      ]),
    );
  }
}

/// Streams one tool call with an arbitrary [input] (may be non-object).
class _StreamSingleToolModel implements LanguageModelV3 {
  _StreamSingleToolModel({required this.toolName, required this.input});
  final String toolName;
  final Object input;

  @override
  String get provider => 'fake';
  @override
  String get modelId => 'single-tool';
  @override
  String get specificationVersion => 'v3';

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async =>
      throw UnimplementedError();

  @override
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  ) async {
    return LanguageModelV3StreamResult(
      stream: Stream<LanguageModelV3StreamPart>.fromIterable([
        StreamPartToolCallStart(toolCallId: 'tc-1', toolName: toolName),
        StreamPartToolCallEnd(
          toolCallId: 'tc-1',
          toolName: toolName,
          input: input,
        ),
        StreamPartFinish(
          finishReason: LanguageModelV3FinishReason.toolCalls,
        ),
      ]),
    );
  }
}

/// First call emits a tool call, second emits text.
class _ToolThenText implements LanguageModelV3 {
  _ToolThenText({required this.toolName, required this.finalText});
  final String toolName;
  final String finalText;
  int _calls = 0;

  @override
  String get provider => 'fake';
  @override
  String get modelId => 'tool-then-text';
  @override
  String get specificationVersion => 'v3';

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async =>
      throw UnimplementedError();

  @override
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  ) async {
    final parts = _calls == 0
        ? <LanguageModelV3StreamPart>[
            StreamPartToolCallStart(toolCallId: 'tc-1', toolName: toolName),
            StreamPartToolCallEnd(
              toolCallId: 'tc-1',
              toolName: toolName,
              input: const {},
            ),
            StreamPartFinish(
              finishReason: LanguageModelV3FinishReason.toolCalls,
            ),
          ]
        : <LanguageModelV3StreamPart>[
            const StreamPartTextStart(id: 't1'),
            StreamPartTextDelta(id: 't1', delta: finalText),
            const StreamPartTextEnd(id: 't1'),
            StreamPartFinish(finishReason: LanguageModelV3FinishReason.stop),
          ];
    _calls++;
    return LanguageModelV3StreamResult(
      stream: Stream<LanguageModelV3StreamPart>.fromIterable(parts),
    );
  }
}
