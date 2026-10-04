import 'dart:async';
import 'dart:convert';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

void main() {
  test('generateText keeps the default tool execution serial', () async {
    final model = _MultiToolModel(3);
    final gates = List.generate(3, (_) => Completer<String>());
    final future = generateText(
      model: model,
      prompt: 'run',
      maxSteps: 2,
      tools: {'run': _tool(gates, onIndexStart: model.notifyStarted)},
    );

    await model.waitForStarted(1);
    expect(model.started, [0]);
    gates[0].complete('result-0');
    await model.waitForStarted(2);
    expect(model.started, [0, 1]);
    gates[1].complete('result-1');
    await model.waitForStarted(3);
    gates[2].complete('result-2');

    final result = await future;
    expect(_resultTexts(result.steps.first.toolResults), [
      'result-0',
      'result-1',
      'result-2',
    ]);
  });

  test('generateText bounds concurrency and preserves result order', () async {
    final model = _MultiToolModel(4);
    final gates = List.generate(4, (_) => Completer<String>());
    var active = 0;
    var peak = 0;
    final future = generateText(
      model: model,
      prompt: 'run',
      maxSteps: 2,
      maxToolConcurrency: 2,
      tools: {
        'run': _tool(
          gates,
          onIndexStart: model.notifyStarted,
          onStart: () {
            active++;
            if (active > peak) peak = active;
          },
          onFinish: () => active--,
        ),
      },
    );

    await model.waitForStarted(2);
    expect(model.started, [0, 1]);
    expect(peak, 2);
    gates[1].complete('result-1');
    await model.waitForStarted(3);
    gates[2].complete('result-2');
    await model.waitForStarted(4);
    gates[3].complete('result-3');
    gates[0].complete('result-0');

    final result = await future;
    expect(peak, 2);
    expect(_resultTexts(result.steps.first.toolResults), [
      'result-0',
      'result-1',
      'result-2',
      'result-3',
    ]);
  });

  test('cancellation prevents queued tool calls from starting', () async {
    final model = _MultiToolModel(4);
    final gates = List.generate(4, (_) => Completer<String>());
    final signal = CancellationToken();
    final future = generateText(
      model: model,
      prompt: 'run',
      maxSteps: 2,
      maxToolConcurrency: 2,
      abortSignal: signal,
      tools: {'run': _tool(gates, onIndexStart: model.notifyStarted)},
    );

    await model.waitForStarted(2);
    signal.cancel();
    await expectLater(future, throwsA(isA<AiOperationCancelledError>()));
    expect(model.started, [0, 1]);
  });

  test('approval checks run before any unapproved tool executor', () async {
    final model = _MultiToolModel(2, includeDanger: true);
    final gates = [Completer<String>(), Completer<String>()];
    var deniedExecutorCalls = 0;
    final future = generateText(
      model: model,
      prompt: 'run',
      maxSteps: 2,
      maxToolConcurrency: 2,
      tools: {
        'run': _tool(gates, onIndexStart: model.notifyStarted),
        'danger': _tool(
          gates,
          onIndexStart: model.notifyStarted,
          needsApproval: true,
          onStart: () => deniedExecutorCalls++,
        ),
      },
    );

    await model.waitForStarted(1);
    gates[0].complete('safe');
    final result = await future;
    expect(deniedExecutorCalls, 0);
    expect(result.steps.first.toolApprovalRequests, hasLength(1));
    expect(_resultTexts(result.steps.first.toolResults), ['safe']);
  });

  test('streamText uses bounded execution and ordered final results', () async {
    final model = _MultiToolModel(3);
    final gates = List.generate(3, (_) => Completer<String>());
    final result = await streamText(
      model: model,
      prompt: 'run',
      maxSteps: 2,
      maxToolConcurrency: 2,
      tools: {'run': _tool(gates, onIndexStart: model.notifyStarted)},
    );
    final eventsFuture = result.fullStream.toList();

    await model.waitForStarted(2);
    gates[1].complete('result-1');
    await model.waitForStarted(3);
    gates[2].complete('result-2');
    gates[0].complete('result-0');
    final events = await eventsFuture;
    final finalResults = events
        .whereType<StreamTextToolResultEvent>()
        .where((event) => !event.preliminary)
        .map((event) => (event.toolResult.output as ToolResultOutputText).text)
        .toList();
    expect(finalResults, ['result-0', 'result-1', 'result-2']);
  });

  test('ToolLoopAgent forwards its explicit concurrency policy', () async {
    final model = _MultiToolModel(2);
    final gates = List.generate(2, (_) => Completer<String>());
    final agent = ToolLoopAgent(
      model: model,
      maxSteps: 2,
      maxToolConcurrency: 2,
      tools: {'run': _tool(gates, onIndexStart: model.notifyStarted)},
    );
    final future = agent.generate(prompt: 'run');
    await model.waitForStarted(2);
    gates[1].complete('result-1');
    gates[0].complete('result-0');
    final result = await future;
    expect(_resultTexts(result.steps.first.toolResults), [
      'result-0',
      'result-1',
    ]);
  });

  test('maxToolConcurrency must be positive', () async {
    final model = _MultiToolModel(0);
    await expectLater(
      generateText(model: model, prompt: 'run', maxToolConcurrency: 0),
      throwsArgumentError,
    );
    await expectLater(
      streamText(model: model, prompt: 'run', maxToolConcurrency: 0),
      throwsArgumentError,
    );
    expect(
      () => ToolLoopAgent(model: model, maxToolConcurrency: 0),
      throwsArgumentError,
    );
  });
}

Tool<Map<String, dynamic>, String> _tool(
  List<Completer<String>> gates, {
  bool needsApproval = false,
  void Function(int index)? onIndexStart,
  void Function()? onStart,
  void Function()? onFinish,
}) => tool<Map<String, dynamic>, String>(
  inputSchema: Schema<Map<String, dynamic>>(
    jsonSchema: const {
      'type': 'object',
      'properties': {
        'index': {'type': 'integer'},
      },
    },
    fromJson: (json) => json,
  ),
  needsApproval: needsApproval ? (_, _) => true : null,
  execute: (input, _) async {
    onStart?.call();
    try {
      final index = (input['index'] as num?)?.toInt() ?? 0;
      onIndexStart?.call(index);
      return await gates[index].future;
    } finally {
      onFinish?.call();
    }
  },
);

List<String> _resultTexts(List<LanguageModelV4ToolResultPart> results) =>
    results
        .map((result) => (result.output as ToolResultOutputText).text)
        .toList();

class _MultiToolModel extends LanguageModelV4 {
  _MultiToolModel(this.callCount, {this.includeDanger = false});

  final int callCount;
  final bool includeDanger;
  final started = <int>[];
  final _startWaiters = <({int count, Completer<void> completer})>[];
  var _modelCalls = 0;

  @override
  String get provider => 'test';

  @override
  String get modelId => 'tool-concurrency';

  @override
  String get specificationVersion => 'v4';

  Future<void> waitForStarted(int count) {
    if (started.length >= count) return Future<void>.value();
    final completer = Completer<void>();
    _startWaiters.add((count: count, completer: completer));
    return completer.future;
  }

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    if (_modelCalls++ > 0) {
      return const LanguageModelV4GenerateResult(
        content: [LanguageModelV4TextPart(text: 'done')],
        finishReason: LanguageModelV4FinishReason.stop,
      );
    }
    return LanguageModelV4GenerateResult(
      content: [
        for (var index = 0; index < callCount; index++)
          LanguageModelV4ToolCallPart(
            toolCallId: 'call-$index',
            toolName: index == 1 && includeDanger ? 'danger' : 'run',
            input: {'index': index},
          ),
      ],
      finishReason: LanguageModelV4FinishReason.toolCalls,
    );
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    if (_modelCalls++ > 0) {
      return LanguageModelV4StreamResult(
        stream: Stream<LanguageModelV4StreamPart>.fromIterable([
          StreamPartTextStart(id: 'text'),
          StreamPartTextDelta(id: 'text', delta: 'done'),
          StreamPartTextEnd(id: 'text'),
          StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
        ]),
      );
    }
    final parts = <LanguageModelV4StreamPart>[];
    for (var index = 0; index < callCount; index++) {
      final call = LanguageModelV4ToolCallPart(
        toolCallId: 'call-$index',
        toolName: 'run',
        input: {'index': index},
      );
      parts.add(StreamPartToolInputStart(id: call.toolCallId, toolName: 'run'));
      parts.add(
        StreamPartToolInputDelta(
          id: call.toolCallId,
          delta: jsonEncode(call.input),
        ),
      );
      parts.add(StreamPartToolInputEnd(id: call.toolCallId));
      parts.add(StreamPartToolCall(toolCall: call));
    }
    parts.add(
      const StreamPartFinish(
        finishReason: LanguageModelV4FinishReason.toolCalls,
      ),
    );
    return LanguageModelV4StreamResult(
      stream: Stream<LanguageModelV4StreamPart>.fromIterable(parts),
    );
  }

  void notifyStarted(int index) {
    started.add(index);
    for (final waiter in List.of(_startWaiters)) {
      if (started.length >= waiter.count && !waiter.completer.isCompleted) {
        waiter.completer.complete();
        _startWaiters.remove(waiter);
      }
    }
  }
}
