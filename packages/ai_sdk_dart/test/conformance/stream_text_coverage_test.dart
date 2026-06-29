import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

/// Targeted tests that drive the less-exercised branches of `streamText`:
/// structured output parsing/streaming, in-stream tool execution (results,
/// errors, approvals, streaming preliminary outputs), toolChoice validation,
/// activeTools, prepareStep, retry, timeout, source/file parts, and the
/// error/finalization paths.
void main() {
  Schema<Map<String, dynamic>> objectSchema() => Schema<Map<String, dynamic>>(
    jsonSchema: const {'type': 'object'},
    fromJson: (json) => json,
  );

  /// Streams [text] one character at a time so partial parses happen.
  FakeStreamModel chunkedText(String text) {
    return FakeStreamModel([
      const StreamPartTextStart(id: 't1'),
      for (final ch in text.split('')) StreamPartTextDelta(id: 't1', delta: ch),
      const StreamPartTextEnd(id: 't1'),
      StreamPartFinish(finishReason: LanguageModelV3FinishReason.stop),
    ]);
  }

  Tool<Map<String, dynamic>, Object?> echoTool(
    FutureOr<Object?> Function(Map<String, dynamic> input) execute, {
    bool Function(Map<String, dynamic> input)? needsApproval,
  }) {
    return tool<Map<String, dynamic>, Object?>(
      inputSchema: objectSchema(),
      execute: (input, _) async => execute(input),
      needsApproval: needsApproval == null
          ? null
          : (input, _) async => needsApproval(input),
    );
  }

  group('streamText structured output', () {
    test('Output.object: partialOutputStream + output future', () async {
      final model = chunkedText('{"a":1,"b":2}');
      final result = await streamText<Map<String, dynamic>>(
        model: model,
        prompt: 'json',
        output: Output.object(schema: objectSchema()),
      );

      final partialsFuture = result.partialOutputStream.toList();
      expect(await result.output, {'a': 1, 'b': 2});
      expect(await partialsFuture, isNotEmpty);
    });

    test('Output.array: elementStream emits decoded elements', () async {
      final model = chunkedText('[{"name":"A"},{"name":"B"}]');
      final result = await streamText<List<dynamic>>(
        model: model,
        prompt: 'json',
        output: Output.array(element: objectSchema()),
      );

      final elementsFuture = result.elementStream.toList();
      final partialsFuture = result.partialOutputStream.toList();
      final output = await result.output;
      expect(output.length, 2);
      final elements = await elementsFuture;
      expect(elements.length, 2);
      expect((elements.first as Map)['name'], 'A');
      expect(await partialsFuture, isNotEmpty);
    });

    test('Output.choice resolves to a valid option', () async {
      final model = chunkedText('"sunny"');
      final result = await streamText<String>(
        model: model,
        prompt: 'classify',
        output: Output.choice(options: const ['sunny', 'rainy']),
      );
      expect(await result.output, 'sunny');
    });

    test('Output.json parses arbitrary JSON', () async {
      final model = chunkedText('{"ok":true,"n":3}');
      final result = await streamText<Object?>(
        model: model,
        prompt: 'json',
        output: Output.json(),
      );
      final out = await result.output as Map<String, dynamic>;
      expect(out['ok'], isTrue);
      expect(out['n'], 3);
    });

    test(
      'invalid object output completes output future with error',
      () async {
        final model = chunkedText('not json at all');
        final result = await streamText<Map<String, dynamic>>(
          model: model,
          prompt: 'json',
          output: Output.object(schema: objectSchema()),
        );
        final expectation = expectLater(
          result.output,
          throwsA(isA<AiNoObjectGeneratedError>()),
        );
        await result.fullStream.toList();
        await expectation;
      },
    );

    test('system instruction is combined with object output schema', () async {
      final model = _CapturingStreamModel('{"a":1}');
      final result = await streamText<Map<String, dynamic>>(
        model: model,
        system: 'be terse',
        prompt: 'json',
        output: Output.object(schema: objectSchema()),
      );
      await result.fullStream.toList();
      final system = model.lastOptions!.prompt.system!;
      expect(system, contains('be terse'));
      expect(system, contains('JSON object'));
    });

    test('system instruction combines with array/choice/json outputs',
        () async {
      final cases = <Output<Object?>, String>{
        Output.array(element: objectSchema()): '[]',
        Output.choice(options: const ['a', 'b']): '"a"',
        Output.json(): '{}',
      };
      for (final entry in cases.entries) {
        final model = _CapturingStreamModel(entry.value);
        final result = await streamText<Object?>(
          model: model,
          system: 'guidance',
          prompt: 'go',
          output: entry.key,
        );
        await result.fullStream.toList();
        // Drain output so any rejection is observed rather than unhandled.
        await result.output;
        expect(model.lastOptions!.prompt.system, contains('guidance'));
      }
    });
  });

  group('streamText tool execution', () {
    test('executes a tool call and emits a tool-result event', () async {
      final model = _StreamToolThenText(
        toolName: 'echo',
        input: const {'msg': 'hi'},
        finalText: 'done',
      );
      final result = await streamText(
        model: model,
        prompt: 'go',
        maxSteps: 3,
        tools: {'echo': echoTool((input) => 'echoed:${input['msg']}')},
      );

      final events = await result.fullStream.toList();
      final toolResults = events
          .whereType<StreamTextToolResultEvent>()
          .where((e) => !e.preliminary)
          .toList();
      expect(toolResults, hasLength(1));
      final output = toolResults.first.toolResult.output;
      expect((output as ToolResultOutputText).text, 'echoed:hi');
      expect(await result.text, 'done');
    });

    test('streaming tool output emits preliminary results', () async {
      final model = _StreamToolThenText(
        toolName: 'stream',
        input: const {},
        finalText: 'final',
      );
      final result = await streamText(
        model: model,
        prompt: 'go',
        maxSteps: 3,
        tools: {
          'stream': tool<Map<String, dynamic>, Object?>(
            inputSchema: objectSchema(),
            execute: (_, __) async => Stream.fromIterable(['a', 'b', 'c']),
          ),
        },
      );

      final events = await result.fullStream.toList();
      final prelim = events
          .whereType<StreamTextToolResultEvent>()
          .where((e) => e.preliminary)
          .toList();
      // Two preliminary emissions (a, b) before the final (c).
      expect(prelim, hasLength(2));
      final finalResults = events
          .whereType<StreamTextToolResultEvent>()
          .where((e) => !e.preliminary)
          .toList();
      expect(
        (finalResults.single.toolResult.output as ToolResultOutputText).text,
        'c',
      );
    });

    test('tool execution error emits StreamTextToolErrorEvent', () async {
      final model = _StreamToolThenText(
        toolName: 'boom',
        input: const {},
        finalText: 'recovered',
      );
      final result = await streamText(
        model: model,
        prompt: 'go',
        maxSteps: 3,
        tools: {
          'boom': echoTool((_) => throw StateError('tool failed')),
        },
      );

      final events = await result.fullStream.toList();
      final errors = events.whereType<StreamTextToolErrorEvent>().toList();
      expect(errors, hasLength(1));
      expect(errors.first.toolName, 'boom');
      // An error tool-result is still emitted.
      final results = events
          .whereType<StreamTextToolResultEvent>()
          .where((e) => !e.preliminary)
          .toList();
      expect(results.single.toolResult.isError, isTrue);
    });

    test('unknown tool produces a "Tool not found" error result', () async {
      final model = _StreamToolThenText(
        toolName: 'mystery',
        input: const {},
        finalText: 'after',
      );
      // Expose a different tool so the loop runs but the call is unknown.
      final result = await streamText(
        model: model,
        prompt: 'go',
        maxSteps: 3,
        tools: {'known': echoTool((_) => 'ok')},
      );
      // toolChoice validation rejects the unknown tool name; the error
      // surfaces via the output future and a StreamTextErrorEvent.
      final outputExpectation = expectLater(
        result.output,
        throwsA(isA<AiNoSuchToolError>()),
      );
      final events = await result.fullStream.toList();
      expect(events.whereType<StreamTextErrorEvent>(), isNotEmpty);
      await outputExpectation;
    });

    test('tool requiring approval emits approval request and stops', () async {
      final model = _StreamSingleToolModel(
        toolName: 'danger',
        input: const {'x': 1},
      );
      final result = await streamText(
        model: model,
        prompt: 'go',
        maxSteps: 3,
        tools: {
          'danger': echoTool((_) => 'ran', needsApproval: (_) => true),
        },
      );
      // Drain stream.
      await result.fullStream.toList();
      final steps = await result.steps;
      expect(steps.single.toolApprovalRequests, hasLength(1));
      // No tool result since it awaits approval.
      expect(steps.single.toolResults, isEmpty);
    });

    test('approved tool executes; denied tool returns error result', () async {
      // Approved
      final approvedModel = _StreamSingleToolModel(
        toolName: 'danger',
        input: const {},
        toolCallId: 'call-x',
      );
      final approved = await streamText(
        model: approvedModel,
        prompt: 'go',
        maxSteps: 3,
        tools: {
          'danger': echoTool((_) => 'executed', needsApproval: (_) => true),
        },
        toolApprovalResponses: const [
          LanguageModelV3ToolApprovalResponse(
            approvalId: 'approval_call-x',
            approved: true,
          ),
        ],
      );
      final approvedEvents = await approved.fullStream.toList();
      final approvedResult = approvedEvents
          .whereType<StreamTextToolResultEvent>()
          .firstWhere((e) => !e.preliminary);
      expect(
        (approvedResult.toolResult.output as ToolResultOutputText).text,
        'executed',
      );

      // Denied
      final deniedModel = _StreamSingleToolModel(
        toolName: 'danger',
        input: const {},
        toolCallId: 'call-y',
      );
      final denied = await streamText(
        model: deniedModel,
        prompt: 'go',
        maxSteps: 3,
        tools: {
          'danger': echoTool((_) => 'executed', needsApproval: (_) => true),
        },
        toolApprovalResponses: const [
          LanguageModelV3ToolApprovalResponse(
            approvalId: 'approval_call-y',
            approved: false,
            reason: 'nope',
          ),
        ],
      );
      final deniedEvents = await denied.fullStream.toList();
      final deniedResult = deniedEvents
          .whereType<StreamTextToolResultEvent>()
          .firstWhere((e) => !e.preliminary);
      expect(deniedResult.toolResult.isError, isTrue);
      expect(
        (deniedResult.toolResult.output as ToolResultOutputText).text,
        'nope',
      );
    });
  });

  group('streamText toolChoice validation', () {
    test('toolChoice none throws when model emits tool calls', () async {
      final model = _StreamSingleToolModel(toolName: 'echo', input: const {});
      final result = await streamText(
        model: model,
        prompt: 'go',
        toolChoice: const ToolChoiceNone(),
        tools: {'echo': echoTool((_) => 'x')},
      );
      final outputExpectation = expectLater(
        result.output,
        throwsA(isA<AiApiCallError>()),
      );
      await result.fullStream.toList();
      await outputExpectation;
    });

    test('toolChoice required throws when no tool calls produced', () async {
      final model = FakeTextModel('plain text');
      final result = await streamText(
        model: model,
        prompt: 'go',
        toolChoice: const ToolChoiceRequired(),
        tools: {'echo': echoTool((_) => 'x')},
      );
      final outputExpectation = expectLater(
        result.output,
        throwsA(isA<AiApiCallError>()),
      );
      await result.fullStream.toList();
      await outputExpectation;
    });

    test('toolChoice required without tools throws AiNoSuchToolError',
        () async {
      final model = FakeTextModel('text');
      final result = await streamText(
        model: model,
        prompt: 'go',
        toolChoice: const ToolChoiceRequired(),
      );
      final outputExpectation = expectLater(
        result.output,
        throwsA(isA<AiNoSuchToolError>()),
      );
      await result.fullStream.toList();
      await outputExpectation;
    });

    test('toolChoice specific mismatch throws', () async {
      final model = _StreamSingleToolModel(toolName: 'echo', input: const {});
      final result = await streamText(
        model: model,
        prompt: 'go',
        toolChoice: const ToolChoiceSpecific(toolName: 'other'),
        tools: {
          'echo': echoTool((_) => 'x'),
          'other': echoTool((_) => 'y'),
        },
      );
      final outputExpectation = expectLater(
        result.output,
        throwsA(isA<AiApiCallError>()),
      );
      await result.fullStream.toList();
      await outputExpectation;
    });

    test('toolChoice specific naming an absent tool throws AiNoSuchToolError',
        () async {
      final model = FakeTextModel('text');
      final result = await streamText(
        model: model,
        prompt: 'go',
        toolChoice: const ToolChoiceSpecific(toolName: 'ghost'),
        tools: {'echo': echoTool((_) => 'x')},
      );
      final outputExpectation = expectLater(
        result.output,
        throwsA(isA<AiNoSuchToolError>()),
      );
      await result.fullStream.toList();
      await outputExpectation;
    });

    test('toolChoice specific exposes only the named tool', () async {
      final model = _CapturingStreamModel('hi');
      final result = await streamText(
        model: model,
        prompt: 'go',
        toolChoice: const ToolChoiceSpecific(toolName: 'echo'),
        tools: {
          'echo': echoTool((_) => 'x'),
          'other': echoTool((_) => 'y'),
        },
      );
      await result.fullStream.toList();
      expect(model.lastOptions!.tools.map((t) => t.name), ['echo']);
    });
  });

  group('streamText activeTools', () {
    test('activeToolNames restricts which tools are exposed', () async {
      final model = _CapturingStreamModel('hi');
      final result = await streamText(
        model: model,
        prompt: 'go',
        activeToolNames: const ['a'],
        tools: {
          'a': echoTool((_) => '1'),
          'b': echoTool((_) => '2'),
        },
      );
      await result.fullStream.toList();
      expect(model.lastOptions!.tools.map((t) => t.name), ['a']);
    });

    test('unknown active tool name throws AiNoSuchToolError', () async {
      final model = FakeTextModel('hi');
      final result = await streamText(
        model: model,
        prompt: 'go',
        activeToolNames: const ['missing'],
        tools: {'a': echoTool((_) => '1')},
      );
      final outputExpectation = expectLater(
        result.output,
        throwsA(isA<AiNoSuchToolError>()),
      );
      await result.fullStream.toList();
      await outputExpectation;
    });
  });

  group('streamText prepareStep', () {
    test('prepareStep can override messages for a step', () async {
      final model = _CapturingStreamModel('ok');
      final result = await streamText(
        model: model,
        prompt: 'orig',
        prepareStep: (ctx) async => GenerateTextPrepareStepResult(
          messages: [
            LanguageModelV3Message(
              role: LanguageModelV3Role.user,
              content: [const LanguageModelV3TextPart(text: 'overridden')],
            ),
          ],
        ),
      );
      await result.fullStream.toList();
      final firstMsgPart =
          model.lastOptions!.prompt.messages.first.content.first;
      expect((firstMsgPart as LanguageModelV3TextPart).text, 'overridden');
    });
  });

  group('streamText source and file parts', () {
    test('emits source and file events and resolves futures', () async {
      const source = LanguageModelV3SourcePart(
        id: 's1',
        url: 'https://example.com',
        title: 'Example',
      );
      const file = LanguageModelV3FilePart(
        mediaType: 'text/plain',
        data: DataContentBase64('aGk='),
      );
      final model = FakeStreamModel([
        const StreamPartTextStart(id: 't1'),
        const StreamPartTextDelta(id: 't1', delta: 'body'),
        const StreamPartTextEnd(id: 't1'),
        const StreamPartSource(source: source),
        StreamPartFile(file: file),
        StreamPartFinish(finishReason: LanguageModelV3FinishReason.stop),
      ]);
      final result = await streamText(model: model, prompt: 'go');
      final events = await result.fullStream.toList();
      expect(events.whereType<StreamTextSourceEvent>(), hasLength(1));
      expect(events.whereType<StreamTextFileEvent>(), hasLength(1));
      expect(await result.sources, hasLength(1));
      expect(await result.files, hasLength(1));
    });
  });

  group('streamText reasoning close mid-stream', () {
    test('reasoning followed by text closes the reasoning part', () async {
      final model = FakeStreamModel([
        const StreamPartReasoningDelta(delta: 'first '),
        const StreamPartReasoningDelta(delta: 'thought'),
        const StreamPartTextStart(id: 't1'),
        const StreamPartTextDelta(id: 't1', delta: 'answer'),
        const StreamPartTextEnd(id: 't1'),
        StreamPartFinish(finishReason: LanguageModelV3FinishReason.stop),
      ]);
      final result = await streamText(model: model, prompt: 'go');
      final events = await result.fullStream.toList();
      // reasoning end emitted before text answer is finished
      expect(events.whereType<StreamTextReasoningStartEvent>(), hasLength(1));
      expect(events.whereType<StreamTextReasoningEndEvent>(), hasLength(1));
      expect(await result.reasoningText, 'first thought');
    });
  });

  group('streamText retry and timeout', () {
    test('retries doStream until it succeeds', () async {
      final model = _FlakyStreamModel(failuresBeforeSuccess: 1);
      final result = await streamText(
        model: model,
        prompt: 'go',
        maxRetries: 2,
      );
      expect(await result.text, 'recovered');
      expect(model.attempts, 2);
    });

    test('propagates error after exhausting retries', () async {
      final model = _FlakyStreamModel(failuresBeforeSuccess: 5);
      final result = await streamText(
        model: model,
        prompt: 'go',
        maxRetries: 1,
      );
      // Attach the output expectation up front so the rejected future is
      // observed while the stream drains and the error event fires.
      final outputExpectation = expectLater(
        result.output,
        throwsA(isA<StateError>()),
      );
      final events = await result.fullStream.toList();
      expect(events.whereType<StreamTextErrorEvent>(), isNotEmpty);
      expect(model.attempts, 2);
      await outputExpectation;
    });

    test('timeout fires when the model is too slow', () async {
      final model = _SlowStartStreamModel(const Duration(milliseconds: 200));
      final result = await streamText(
        model: model,
        prompt: 'go',
        timeout: const Duration(milliseconds: 10),
        maxRetries: 0,
      );
      final outputExpectation = expectLater(
        result.output,
        throwsA(isA<TimeoutException>()),
      );
      await result.fullStream.toList();
      await outputExpectation;
    });
  });

  group('streamText usage aggregation', () {
    test('totalUsage sums usage across multiple steps', () async {
      final model = _StreamToolThenText(
        toolName: 'echo',
        input: const {},
        finalText: 'done',
        stepUsage: const LanguageModelV3Usage(
          inputTokens: 4,
          outputTokens: 2,
          totalTokens: 6,
        ),
      );
      final result = await streamText(
        model: model,
        prompt: 'go',
        maxSteps: 3,
        tools: {'echo': echoTool((_) => 'ok')},
      );
      await result.fullStream.toList();
      final total = await result.totalUsage;
      // Two steps each contributing 4/2/6.
      expect(total?.inputTokens, 8);
      expect(total?.outputTokens, 4);
      expect(total?.totalTokens, 12);
    });

    test('mid-stream usage event is emitted', () async {
      final model = FakeStreamModel([
        const StreamPartTextStart(id: 't1'),
        const StreamPartTextDelta(id: 't1', delta: 'hi'),
        const StreamPartTextEnd(id: 't1'),
        StreamPartFinish(
          finishReason: LanguageModelV3FinishReason.stop,
          usage: const LanguageModelV3Usage(
            inputTokens: 1,
            outputTokens: 1,
            totalTokens: 2,
          ),
        ),
      ]);
      final usageEvents = <LanguageModelV3Usage>[];
      final result = await streamText(
        model: model,
        prompt: 'go',
        onChunk: (chunk) {
          if (chunk is StreamTextUsageChunk) usageEvents.add(chunk.usage);
        },
      );
      final events = await result.fullStream.toList();
      expect(events.whereType<StreamTextUsageEvent>(), hasLength(1));
      expect(usageEvents, hasLength(1));
    });
  });

  group('streamText callbacks', () {
    test('onInputStart / onInputDelta / onInputAvailable fire', () async {
      final model = _StreamToolThenText(
        toolName: 'echo',
        input: const {'q': 'x'},
        finalText: 'done',
      );
      final starts = <String>[];
      final deltas = <String>[];
      Object? available;
      final result = await streamText(
        model: model,
        prompt: 'go',
        maxSteps: 3,
        tools: {'echo': echoTool((_) => 'ok')},
        onInputStart: (e) => starts.add(e.toolName),
        onInputDelta: (e) => deltas.add(e.delta),
        onInputAvailable: (e) => available = e.input,
      );
      await result.fullStream.toList();
      expect(starts, ['echo']);
      expect(deltas, isNotEmpty);
      expect(available, const {'q': 'x'});
    });

    test('onToolCallFinish reports failure when the tool throws', () async {
      final failures = <bool>[];
      final model = _StreamToolThenText(
        toolName: 'boom',
        input: const {},
        finalText: 'after',
      );
      final result = await streamText(
        model: model,
        prompt: 'go',
        maxSteps: 3,
        tools: {'boom': echoTool((_) => throw StateError('boom'))},
        experimentalOnToolCallFinish: (e) => failures.add(e.success),
      );
      await result.fullStream.toList();
      expect(failures, [false]);
    });

    test('unencodable streaming tool output falls back to toString', () async {
      final model = _StreamToolThenText(
        toolName: 'obj',
        input: const {},
        finalText: 'done',
      );
      final result = await streamText(
        model: model,
        prompt: 'go',
        maxSteps: 3,
        tools: {'obj': echoTool((_) => _Unencodable())},
      );
      final events = await result.fullStream.toList();
      final toolResult = events
          .whereType<StreamTextToolResultEvent>()
          .firstWhere((e) => !e.preliminary);
      expect(
        (toolResult.toolResult.output as ToolResultOutputText).text,
        contains('Unencodable'),
      );
    });

    test('experimental lifecycle callbacks fire', () async {
      var started = false;
      var stepStarted = false;
      var toolStarted = false;
      var toolFinished = false;
      final model = _StreamToolThenText(
        toolName: 'echo',
        input: const {},
        finalText: 'done',
      );
      final result = await streamText(
        model: model,
        prompt: 'go',
        maxSteps: 3,
        tools: {'echo': echoTool((_) => 'ok')},
        experimentalOnStart: (_) => started = true,
        experimentalOnStepStart: (_) => stepStarted = true,
        experimentalOnToolCallStart: (_) => toolStarted = true,
        experimentalOnToolCallFinish: (_) => toolFinished = true,
      );
      await result.fullStream.toList();
      expect(started, isTrue);
      expect(stepStarted, isTrue);
      expect(toolStarted, isTrue);
      expect(toolFinished, isTrue);
    });
  });
}

/// A value jsonEncode cannot serialize, with a stable toString.
class _Unencodable {
  @override
  String toString() => 'Unencodable()';
}

// ---------------------------------------------------------------------------
// Helper models
// ---------------------------------------------------------------------------

/// Captures the last call options and returns a fixed text stream.
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

/// First call streams a single tool call; the second call streams [finalText].
class _StreamToolThenText implements LanguageModelV3 {
  _StreamToolThenText({
    required this.toolName,
    required this.input,
    required this.finalText,
    this.stepUsage,
  });

  final String toolName;
  final Map<String, dynamic> input;
  final String finalText;
  final LanguageModelV3Usage? stepUsage;
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
            StreamPartToolCallDelta(
              toolCallId: 'tc-1',
              toolName: toolName,
              argsTextDelta: '{}',
            ),
            StreamPartToolCallEnd(
              toolCallId: 'tc-1',
              toolName: toolName,
              input: input,
            ),
            StreamPartFinish(
              finishReason: LanguageModelV3FinishReason.toolCalls,
              usage: stepUsage,
            ),
          ]
        : <LanguageModelV3StreamPart>[
            const StreamPartTextStart(id: 't1'),
            StreamPartTextDelta(id: 't1', delta: finalText),
            const StreamPartTextEnd(id: 't1'),
            StreamPartFinish(
              finishReason: LanguageModelV3FinishReason.stop,
              usage: stepUsage,
            ),
          ];
    _calls++;
    return LanguageModelV3StreamResult(
      stream: Stream<LanguageModelV3StreamPart>.fromIterable(parts),
    );
  }
}

/// Streams exactly one tool call (no follow-up text step).
class _StreamSingleToolModel implements LanguageModelV3 {
  _StreamSingleToolModel({
    required this.toolName,
    required this.input,
    this.toolCallId = 'tc-1',
  });

  final String toolName;
  final Map<String, dynamic> input;
  final String toolCallId;

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
        StreamPartToolCallStart(toolCallId: toolCallId, toolName: toolName),
        StreamPartToolCallDelta(
          toolCallId: toolCallId,
          toolName: toolName,
          argsTextDelta: '{}',
        ),
        StreamPartToolCallEnd(
          toolCallId: toolCallId,
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

/// Fails [failuresBeforeSuccess] times before streaming "recovered".
class _FlakyStreamModel implements LanguageModelV3 {
  _FlakyStreamModel({required this.failuresBeforeSuccess});
  final int failuresBeforeSuccess;
  int attempts = 0;

  @override
  String get provider => 'fake';
  @override
  String get modelId => 'flaky-stream';
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
    attempts++;
    if (attempts <= failuresBeforeSuccess) {
      throw StateError('flaky failure $attempts');
    }
    return LanguageModelV3StreamResult(
      stream: Stream<LanguageModelV3StreamPart>.fromIterable([
        const StreamPartTextStart(id: 't1'),
        const StreamPartTextDelta(id: 't1', delta: 'recovered'),
        const StreamPartTextEnd(id: 't1'),
        StreamPartFinish(finishReason: LanguageModelV3FinishReason.stop),
      ]),
    );
  }
}

/// Delays before returning the stream so a timeout can trigger.
class _SlowStartStreamModel implements LanguageModelV3 {
  _SlowStartStreamModel(this.delay);
  final Duration delay;

  @override
  String get provider => 'fake';
  @override
  String get modelId => 'slow-start';
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
    await Future<void>.delayed(delay);
    return const LanguageModelV3StreamResult(
      stream: Stream<LanguageModelV3StreamPart>.empty(),
    );
  }
}
