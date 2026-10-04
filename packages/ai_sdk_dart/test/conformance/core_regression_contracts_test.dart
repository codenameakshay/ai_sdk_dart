import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

void main() {
  test(
    'cancellation does not leak the already-created provider failure',
    () async {
      final unhandled = <Object>[];
      await runZonedGuarded(() async {
        final token = CancellationToken();
        await expectLater(
          embed(
            model: _CancelAndFailEmbeddingModel(),
            value: 'value',
            abortSignal: token,
          ),
          throwsA(isA<AiOperationCancelledError>()),
        );
        await Future<void>.delayed(Duration.zero);
      }, (error, _) => unhandled.add(error));

      expect(unhandled, isEmpty);
    },
  );

  test(
    'resume validates the system-message policy before executing tools',
    () async {
      var executions = 0;
      final model = FakeTextModel('answer');
      const callId = 'resume-system-call';
      const approvalId = 'resume-system-approval';
      const fingerprint = '{}';
      final call = LanguageModelV4ToolCallPart(
        toolCallId: callId,
        toolName: 'mutate',
        input: const {},
      );
      final request = LanguageModelV4ToolApprovalRequestPart(
        approvalId: approvalId,
        toolCall: call,
        argumentsFingerprint: fingerprint,
        policyRevision: 'default',
      );
      final resume =
          ToolLoopAgent(
            model: model,
            tools: {
              'mutate': dynamicTool<String>(
                execute: (_, _) async {
                  executions++;
                  return 'done';
                },
              ),
            },
          ).resume(
            replay: ToolApprovalReplay(
              messages: [
                ModelMessage.parts(
                  role: ModelMessageRole.assistant,
                  parts: [call],
                ),
              ],
              requests: [request],
            ),
            toolApprovalResponses: const [
              LanguageModelV4ToolApprovalResponse(
                approvalId: approvalId,
                approved: true,
                toolCallId: callId,
                toolName: 'mutate',
                argumentsFingerprint: fingerprint,
                policyRevision: 'default',
              ),
            ],
            messages: const [
              ModelMessage(content: 'trusted?', role: ModelMessageRole.system),
            ],
          );

      await expectLater(resume, throwsA(isA<ArgumentError>()));
      expect(executions, 0);
      expect(model.lastCallOptions, isNull);
    },
  );

  test('simulated reasoning stream preserves the signature', () async {
    final wrapped = wrapLanguageModel(
      model: _ReasoningGenerateModel(),
      middleware: simulateStreamingMiddleware(),
    );
    final result = await wrapped.doStream(
      LanguageModelV4CallOptions(
        prompt: const LanguageModelV4Prompt(messages: []),
      ),
    );

    final end = (await result.stream.toList())
        .whereType<StreamPartReasoningEnd>()
        .single;
    expect(end.signature, 'signed-reasoning');
    expect(end.providerMetadata, {
      'fixture': {'opaque': 'preserved'},
    });
  });

  test('unstructured JSON output accepts the JSON null value', () async {
    final result = await generateText(
      model: FakeTextModel('null'),
      prompt: 'return null',
      output: Output.json(),
    );
    expect(result.output, isNull);
  });

  test('unstructured JSON output accepts fenced JSON null', () async {
    final result = await generateText(
      model: FakeTextModel('```json\nnull\n```'),
      prompt: 'return null',
      output: Output.json(),
    );
    expect(result.output, isNull);
  });

  test(
    'specific tool choice fails when the model returns no tool call',
    () async {
      await expectLater(
        generateText(
          model: FakeTextModel('I will answer without calling it.'),
          prompt: 'call lookup',
          tools: {
            'lookup': dynamicTool<String>(execute: (_, _) async => 'found'),
          },
          toolChoice: const ToolChoiceSpecific(toolName: 'lookup'),
        ),
        throwsA(isA<AiApiCallError>()),
      );
    },
  );

  test('resume response includes its newly executed replay result', () async {
    const callId = 'first-call';
    const approvalId = 'first-approval';
    const fingerprint = '{}';
    final firstCall = LanguageModelV4ToolCallPart(
      toolCallId: callId,
      toolName: 'first',
      input: const {},
    );
    final request = LanguageModelV4ToolApprovalRequestPart(
      approvalId: approvalId,
      toolCall: firstCall,
      argumentsFingerprint: fingerprint,
      policyRevision: 'default',
    );
    final finishEvents = <StreamTextFinishEvent<dynamic>>[];
    final result =
        await ToolLoopAgent(
          model: FakeToolModel(toolName: 'next', toolInput: const {}),
          tools: {
            'first': dynamicTool<String>(
              execute: (_, _) async => 'first-output',
            ),
            'next': dynamicTool<String>(
              needsApproval: (_, _) async => true,
              execute: (_, _) async => 'next-output',
            ),
          },
        ).resume(
          replay: ToolApprovalReplay(
            messages: [
              ModelMessage.parts(
                role: ModelMessageRole.assistant,
                parts: [firstCall],
              ),
            ],
            requests: [request],
          ),
          toolApprovalResponses: const [
            LanguageModelV4ToolApprovalResponse(
              approvalId: approvalId,
              approved: true,
              toolCallId: callId,
              toolName: 'first',
              argumentsFingerprint: fingerprint,
              policyRevision: 'default',
            ),
          ],
          onEnd: finishEvents.add,
        );
    final streamedFinishFuture = result.stream
        .where((event) => event is StreamTextFinishEvent)
        .cast<StreamTextFinishEvent<dynamic>>()
        .single;
    final response = await result.response;
    final streamedFinish = await streamedFinishFuture;
    final replayResult = response.messages
        .expand((message) => message.content)
        .whereType<LanguageModelV4ToolResultPart>()
        .where((part) => part.toolCallId == callId);

    expect(replayResult, hasLength(1));
    final callbackReplayResult = finishEvents.single.responseMessages
        .expand((message) => message.content)
        .whereType<LanguageModelV4ToolResultPart>()
        .where((part) => part.toolCallId == callId);
    expect(callbackReplayResult, hasLength(1));
    expect(
      finishEvents.single.response.messages
          .expand((message) => message.content)
          .whereType<LanguageModelV4ToolResultPart>()
          .where((part) => part.toolCallId == callId),
      hasLength(1),
    );
    final streamReplayResult = streamedFinish.responseMessages
        .expand((message) => message.content)
        .whereType<LanguageModelV4ToolResultPart>()
        .where((part) => part.toolCallId == callId);
    expect(streamReplayResult, hasLength(1));
    expect(
      streamedFinish.response.messages
          .expand((message) => message.content)
          .whereType<LanguageModelV4ToolResultPart>()
          .where((part) => part.toolCallId == callId),
      hasLength(1),
    );
  });

  test(
    'resume consumes unobserved response failure when stream fails',
    () async {
      final unhandled = <Object>[];
      await runZonedGuarded(() async {
        const callId = 'first-call';
        const approvalId = 'first-approval';
        const fingerprint = '{}';
        final call = LanguageModelV4ToolCallPart(
          toolCallId: callId,
          toolName: 'first',
          input: const {},
        );
        final request = LanguageModelV4ToolApprovalRequestPart(
          approvalId: approvalId,
          toolCall: call,
          argumentsFingerprint: fingerprint,
          policyRevision: 'default',
        );
        final result =
            await ToolLoopAgent(
              model: _FailingResumeModel(),
              tools: {
                'first': dynamicTool<String>(execute: (_, _) async => 'ok'),
              },
            ).resume(
              replay: ToolApprovalReplay(
                messages: [
                  ModelMessage.parts(
                    role: ModelMessageRole.assistant,
                    parts: [call],
                  ),
                ],
                requests: [request],
              ),
              toolApprovalResponses: const [
                LanguageModelV4ToolApprovalResponse(
                  approvalId: approvalId,
                  approved: true,
                  toolCallId: callId,
                  toolName: 'first',
                  argumentsFingerprint: fingerprint,
                  policyRevision: 'default',
                ),
              ],
            );
        await expectLater(result.finish, throwsA(isA<StateError>()));
        await Future<void>.delayed(Duration.zero);
      }, (error, _) => unhandled.add(error));

      expect(unhandled, isEmpty);
    },
  );

  test('array output is returned with its declared element type', () async {
    final result = await generateText<List<Map<String, dynamic>>>(
      model: FakeTextModel('[{"x":1}]'),
      prompt: 'return an array',
      output: Output.array<Map<String, dynamic>>(
        element: Schema<Map<String, dynamic>>(
          jsonSchema: const {
            'type': 'object',
            'properties': {
              'x': {'type': 'integer'},
            },
          },
          fromJson: (json) => json,
        ),
      ),
    );

    expect(result.output.single['x'], 1);
  });

  test('partial array snapshots follow the final tool-loop step', () async {
    final model = _TwoStepArrayModel();
    final result = await streamText<List<Object?>>(
      model: model,
      prompt: 'make an array',
      maxSteps: 2,
      output: Output.array<Object?>(
        element: Schema<Object?>(
          jsonSchema: const {
            'type': 'object',
            'properties': {
              'x': {'type': 'integer'},
            },
          },
          fromJson: (json) => json,
        ),
      ),
      tools: {'next': dynamicTool<String>(execute: (_, _) async => 'done')},
    );
    final partials = <Object?>[];
    final subscription = result.partialOutputStream.listen(partials.add);
    List<Object?> output = const [];
    try {
      output = await result.output;
    } catch (_) {}
    await subscription.cancel();

    expect(model._calls, 2);
    expect((output.single as Map)['x'], 2);
    expect(partials, isNotEmpty);
    expect(((partials.last as List).single as Map)['x'], 2);
  });

  test('partial object snapshots follow the final tool-loop step', () async {
    final model = _TwoStepObjectModel();
    final result = await streamText<Map<String, dynamic>>(
      model: model,
      prompt: 'make an object',
      maxSteps: 2,
      output: Output.object<Map<String, dynamic>>(
        schema: Schema<Map<String, dynamic>>(
          jsonSchema: const {
            'type': 'object',
            'properties': {
              'x': {'type': 'integer'},
            },
          },
          fromJson: (json) => json,
        ),
      ),
      tools: {'next': dynamicTool<String>(execute: (_, _) async => 'done')},
    );
    final partials = <Object?>[];
    final subscription = result.partialOutputStream.listen(partials.add);
    Map<String, dynamic> output = const {};
    try {
      output = await result.output;
    } finally {
      await subscription.cancel();
    }

    expect(model.calls, 2);
    expect(output['x'], 2);
    expect(partials, isNotEmpty);
    expect((partials.last as Map)['x'], 2);
  });

  test(
    'partial array snapshots publish an empty final tool-loop array',
    () async {
      final model = _TwoStepArrayModel(finalText: '[]');
      final result = await streamText<List<Object?>>(
        model: model,
        prompt: 'make an array',
        maxSteps: 2,
        output: Output.array<Object?>(
          element: Schema<Object?>(
            jsonSchema: const {'type': 'object'},
            fromJson: (json) => json,
          ),
        ),
        tools: {'next': dynamicTool<String>(execute: (_, _) async => 'done')},
      );
      final partials = <Object?>[];
      final subscription = result.partialOutputStream.listen(partials.add);
      final output = await result.output;
      await subscription.cancel();

      expect(output, isEmpty);
      expect(partials, isNotEmpty);
      expect(partials.last, isEmpty);
    },
  );

  test(
    'partial object snapshots publish an empty final tool-loop object',
    () async {
      final model = _TwoStepObjectModel(finalText: '{}');
      final result = await streamText<Map<String, dynamic>>(
        model: model,
        prompt: 'make an object',
        maxSteps: 2,
        output: Output.object<Map<String, dynamic>>(
          schema: Schema<Map<String, dynamic>>(
            jsonSchema: const {'type': 'object'},
            fromJson: (json) => json,
          ),
        ),
        tools: {'next': dynamicTool<String>(execute: (_, _) async => 'done')},
      );
      final partials = <Object?>[];
      final subscription = result.partialOutputStream.listen(partials.add);
      final output = await result.output;
      await subscription.cancel();

      expect(output, isEmpty);
      expect(partials, isNotEmpty);
      expect(partials.last, isEmpty);
    },
  );
}

class _CancelAndFailEmbeddingModel implements EmbeddingModelV2<String> {
  @override
  int? get maxEmbeddingsPerCall => null;

  @override
  bool get supportsParallelCalls => true;

  @override
  String get provider => 'audit';

  @override
  String get modelId => 'cancel-and-fail';

  @override
  String get specificationVersion => 'v2';

  @override
  Future<EmbeddingModelV2GenerateResult<String>> doEmbed(
    EmbeddingModelV2CallOptions<String> options,
  ) {
    (options.abortSignal! as CancellationToken).cancel();
    return Future.error(StateError('provider failure after cancellation'));
  }
}

class _ReasoningGenerateModel extends FakeTextModel {
  _ReasoningGenerateModel() : super('unused');

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async => const LanguageModelV4GenerateResult(
    content: [
      LanguageModelV4ReasoningPart(
        text: 'thinking',
        signature: 'signed-reasoning',
        providerOptions: {
          'fixture': {'opaque': 'preserved'},
        },
      ),
    ],
    finishReason: LanguageModelV4FinishReason.stop,
  );
}

class _FailingResumeModel extends FakeTextModel {
  _FailingResumeModel() : super('unused');

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) => Future.error(StateError('provider stream failed'));
}

class _TwoStepArrayModel extends FakeTextModel {
  _TwoStepArrayModel({this.finalText = '[{"x":2}]'}) : super('unused');

  final String finalText;

  var _calls = 0;

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    if (_calls++ == 0) {
      return LanguageModelV4StreamResult(
        stream: Stream.fromIterable([
          const StreamPartTextStart(id: 'text'),
          const StreamPartTextDelta(id: 'text', delta: '[{"x":1}]'),
          const StreamPartTextEnd(id: 'text'),
          const StreamPartToolCall(
            toolCall: LanguageModelV4ToolCallPart(
              toolCallId: 'next-call',
              toolName: 'next',
              input: {},
            ),
          ),
          const StreamPartFinish(
            finishReason: LanguageModelV4FinishReason.toolCalls,
          ),
        ]),
      );
    }
    return LanguageModelV4StreamResult(
      stream: Stream.fromIterable([
        const StreamPartTextStart(id: 'text'),
        StreamPartTextDelta(id: 'text', delta: finalText),
        const StreamPartTextEnd(id: 'text'),
        const StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
      ]),
    );
  }
}

class _TwoStepObjectModel extends FakeTextModel {
  _TwoStepObjectModel({this.finalText = '{"x":2}'}) : super('unused');

  final String finalText;

  var calls = 0;

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    if (calls++ == 0) {
      return LanguageModelV4StreamResult(
        stream: Stream.fromIterable([
          const StreamPartTextStart(id: 'text'),
          const StreamPartTextDelta(id: 'text', delta: '{"x":1}'),
          const StreamPartTextEnd(id: 'text'),
          const StreamPartToolCall(
            toolCall: LanguageModelV4ToolCallPart(
              toolCallId: 'next-call',
              toolName: 'next',
              input: {},
            ),
          ),
          const StreamPartFinish(
            finishReason: LanguageModelV4FinishReason.toolCalls,
          ),
        ]),
      );
    }
    return LanguageModelV4StreamResult(
      stream: Stream.fromIterable([
        const StreamPartTextStart(id: 'text'),
        StreamPartTextDelta(id: 'text', delta: finalText),
        const StreamPartTextEnd(id: 'text'),
        const StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
      ]),
    );
  }
}
