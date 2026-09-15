import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

class _ApprovalReplayModel extends LanguageModelV4 {
  int streamCalls = 0;
  List<LanguageModelV4Message> resumedMessages = const [];

  @override
  String get provider => 'mock';

  @override
  String get modelId => 'approval-replay';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) => throw UnimplementedError();

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    streamCalls++;
    resumedMessages = options.prompt.messages;
    const call = LanguageModelV4ToolCallPart(
      toolCallId: 'provider-call-1',
      toolName: 'secureTool',
      input: {'path': '/x'},
    );
    final parts = streamCalls == 1
        ? <LanguageModelV4StreamPart>[
            const StreamPartToolInputStart(
              id: 'provider-call-1',
              toolName: 'secureTool',
            ),
            const StreamPartToolInputDelta(
              id: 'provider-call-1',
              delta: '{"path":"/x"}',
            ),
            const StreamPartToolInputEnd(id: 'provider-call-1'),
            const StreamPartToolCall(toolCall: call),
            const StreamPartFinish(
              finishReason: LanguageModelV4FinishReason.toolCalls,
            ),
          ]
        : <LanguageModelV4StreamPart>[
            const StreamPartTextStart(id: 'answer'),
            const StreamPartTextDelta(id: 'answer', delta: 'continued'),
            const StreamPartTextEnd(id: 'answer'),
            const StreamPartFinish(
              finishReason: LanguageModelV4FinishReason.stop,
            ),
          ];
    return LanguageModelV4StreamResult(stream: Stream.fromIterable(parts));
  }
}

void main() {
  group('ChatController', () {
    test('starts ready and empty (or with initial messages)', () {
      final controller = ChatController();
      expect(controller.status, ChatStatus.ready);
      expect(controller.isLoading, isFalse);
      expect(controller.isStreaming, isFalse);
      expect(controller.messages, isEmpty);
      expect(controller.streamingContent, isEmpty);
      controller.dispose();

      final seeded = ChatController(
        initialMessages: const [
          ModelMessage(role: ModelMessageRole.system, content: 'sys'),
        ],
      );
      expect(seeded.messages, hasLength(1));
      seeded.dispose();
    });

    test('append adds a message without generating', () {
      final controller = ChatController();
      controller.append(
        const ModelMessage(role: ModelMessageRole.user, content: 'hi'),
      );
      expect(controller.messages, hasLength(1));
      expect(controller.status, ChatStatus.ready);
      controller.dispose();
    });

    test(
      'sendMessage runs ready -> submitted -> streaming -> ready and appends '
      'the assistant reply',
      () async {
        final controller = ChatController();
        final statuses = <ChatStatus>[];
        controller.addListener(() => statuses.add(controller.status));

        await controller.sendMessage(
          agent: textAgent('Hello world'),
          text: 'Hi',
        );
        await pumpUntil(() => controller.status == ChatStatus.ready);

        expect(statuses, contains(ChatStatus.submitted));
        expect(statuses, contains(ChatStatus.streaming));
        expect(controller.status, ChatStatus.ready);
        expect(controller.isStreaming, isFalse);
        expect(controller.isLoading, isFalse);

        // user message + assistant reply
        expect(controller.messages, hasLength(2));
        expect(controller.messages.first.role, ModelMessageRole.user);
        expect(controller.messages.last.role, ModelMessageRole.assistant);
        expect(controller.messages.last.content, 'Hello world');

        // streaming buffer is cleared once the turn completes
        expect(controller.streamingContent, isEmpty);
        controller.dispose();
      },
    );

    test('isStreaming mirrors status == streaming during the stream', () async {
      final controller = ChatController();
      var sawStreamingTrue = false;
      controller.addListener(() {
        if (controller.status == ChatStatus.streaming) {
          // Whenever status is streaming, isStreaming must agree.
          expect(controller.isStreaming, isTrue);
          sawStreamingTrue = true;
        }
      });

      await controller.sendMessage(agent: textAgent('streamed'), text: 'go');
      await pumpUntil(() => controller.status == ChatStatus.ready);
      expect(sawStreamingTrue, isTrue);
      controller.dispose();
    });

    test('onFinish fires with the assistant message', () async {
      ModelMessage? finished;
      final controller = ChatController(onFinish: (m) => finished = m);
      await controller.sendMessage(agent: textAgent('done'), text: 'x');
      await pumpUntil(() => finished != null);
      expect(finished, isNotNull);
      expect(finished!.content, 'done');
      expect(finished!.role, ModelMessageRole.assistant);
      controller.dispose();
    });

    test('onError fires and status becomes error on stream failure', () async {
      Object? captured;
      final controller = ChatController(onError: (e) => captured = e);
      final failure = StateError('boom');

      await controller.sendMessage(agent: erroringAgent(failure), text: 'x');
      await pumpUntil(() => controller.status == ChatStatus.error);

      expect(controller.status, ChatStatus.error);
      expect(controller.error, isNotNull);
      expect(captured, isNotNull);
      // user message remains, no assistant message appended
      expect(controller.messages, hasLength(1));
      controller.dispose();
    });

    test('clearError resets error status to ready', () async {
      final controller = ChatController();
      await controller.sendMessage(
        agent: erroringAgent(StateError('x')),
        text: 'x',
      );
      await pumpUntil(() => controller.status == ChatStatus.error);
      expect(controller.status, ChatStatus.error);

      controller.clearError();
      expect(controller.status, ChatStatus.ready);
      expect(controller.error, isNull);
      controller.dispose();
    });

    test('reload removes the last assistant message and regenerates', () async {
      final controller = ChatController();
      await controller.sendMessage(agent: textAgent('first'), text: 'q');
      await pumpUntil(() => controller.status == ChatStatus.ready);
      expect(controller.messages.last.content, 'first');

      // reload uses the cached agent.
      await controller.reload();
      await pumpUntil(() => controller.status == ChatStatus.ready);
      // still 2 messages: user + freshly-generated assistant
      expect(controller.messages, hasLength(2));
      expect(controller.messages.last.role, ModelMessageRole.assistant);
      expect(controller.messages.last.content, 'first');
      controller.dispose();
    });

    test('regenerate is an alias of reload', () async {
      final controller = ChatController();
      await controller.sendMessage(agent: textAgent('a'), text: 'q');
      await pumpUntil(() => controller.status == ChatStatus.ready);
      await controller.regenerate();
      await pumpUntil(() => controller.status == ChatStatus.ready);
      expect(controller.messages, hasLength(2));
      controller.dispose();
    });

    test('clear resets to initial messages', () async {
      final controller = ChatController(
        initialMessages: const [
          ModelMessage(role: ModelMessageRole.system, content: 'sys'),
        ],
      );
      await controller.sendMessage(agent: textAgent('a'), text: 'q');
      await pumpUntil(() => controller.status == ChatStatus.ready);
      expect(controller.messages.length, greaterThan(1));

      controller.clear();
      expect(controller.messages, hasLength(1));
      expect(controller.messages.single.content, 'sys');
      expect(controller.status, ChatStatus.ready);
      controller.dispose();
    });

    test(
      'addToolApprovalResponse records a pending approval without error',
      () {
        final controller = ChatController();
        controller.addToolApprovalResponse(approvalId: 'a1', approved: true);
        // No public getter; assert it simply notified and stayed ready.
        expect(controller.status, ChatStatus.ready);
        controller.dispose();
      },
    );

    test('stop leaves the controller ready', () async {
      final controller = ChatController();
      // With the mock the stream completes quickly; stop after completion must
      // be a no-op that leaves us ready.
      await controller.sendMessage(agent: textAgent('x'), text: 'q');
      await pumpUntil(() => controller.status == ChatStatus.ready);
      await controller.stop();
      expect(controller.status, ChatStatus.ready);
      controller.dispose();
    });

    test(
      'stop mid-stream flushes the partial buffer as an assistant message',
      () async {
        final controller = ChatController();
        final model = HoldingTextModel('partial answer');

        // Don't await: the holding model keeps the stream open so we can stop
        // while content is buffered but the turn hasn't finished.
        unawaited(
          controller.sendMessage(
            agent: ToolLoopAgent(model: model),
            text: 'q',
          ),
        );
        await pumpUntil(() => controller.streamingContent.isNotEmpty);
        expect(controller.streamingContent, 'partial answer');

        await controller.stop();

        // The buffered text is committed as a trailing assistant message and the
        // buffer is cleared.
        expect(controller.status, ChatStatus.ready);
        expect(controller.streamingContent, isEmpty);
        expect(controller.messages.last.role, ModelMessageRole.assistant);
        expect(controller.messages.last.content, 'partial answer');

        model.finish();
        controller.dispose();
      },
    );

    test(
      'a pending tool approval is consumed by the next generation',
      () async {
        final controller = ChatController();
        controller.addToolApprovalResponse(approvalId: 'a1', approved: true);

        // sendMessage runs _runGeneration, which consumes pending approvals.
        // We only need the generation to start and finish cleanly.
        await controller.sendMessage(agent: textAgent('ok'), text: 'go');
        await pumpUntil(() => controller.status == ChatStatus.ready);
        expect(controller.messages.last.content, 'ok');

        // A second generation with no pending approvals still works (the buffer
        // was cleared by the first consume).
        await controller.reload();
        await pumpUntil(() => controller.status == ChatStatus.ready);
        expect(controller.status, ChatStatus.ready);
        controller.dispose();
      },
    );

    test(
      'a synchronous failure from agent.stream() is caught and reported',
      () async {
        Object? captured;
        final controller = ChatController(onError: (e) => captured = e);
        final failure = StateError('sync boom');

        // throwOnStream makes doStream throw synchronously, so the
        // `await agent.stream(...)` itself rejects and is handled by the
        // try/catch in _runGeneration (not the stream error listener).
        await controller.sendMessage(
          agent: syncThrowingAgent(failure),
          text: 'x',
        );
        await pumpUntil(() => controller.status == ChatStatus.error);

        expect(controller.status, ChatStatus.error);
        expect(controller.error, same(failure));
        expect(captured, same(failure));
        controller.dispose();
      },
    );
  });

  group('ChatController surfacing', () {
    test('captures the last usage after a turn', () async {
      final controller = ChatController();
      const usage = LanguageModelV4Usage(
        inputTokens: LanguageModelV4InputTokenUsage(total: 7),
        outputTokens: LanguageModelV4OutputTokenUsage(total: 11),
      );

      await controller.sendMessage(
        agent: textAgentWithUsage('hi', usage),
        text: 'q',
      );
      await pumpUntil(() => controller.status == ChatStatus.ready);

      expect(controller.lastUsage?.inputTokens.total, 7);
      expect(controller.lastUsage?.outputTokens.total, 11);
      controller.dispose();
    });

    test('captures the reasoning text after a turn', () async {
      final controller = ChatController();

      await controller.sendMessage(
        agent: reasoningAgent(reasoning: 'because reasons', text: 'answer'),
        text: 'why',
      );
      await pumpUntil(() => controller.status == ChatStatus.ready);

      expect(controller.reasoningText, contains('because reasons'));
      expect(controller.streamingReasoning, isEmpty); // reset once committed
      expect(controller.messages.last.content, 'answer');
      controller.dispose();
    });

    test('pauses for tool approval and exposes the pending request', () async {
      final controller = ChatController();

      await controller.sendMessage(agent: approvalAgent(), text: 'go');
      await pumpUntil(() => controller.status == ChatStatus.awaitingApproval);

      expect(controller.status, ChatStatus.awaitingApproval);
      expect(controller.isLoading, isFalse);
      expect(controller.pendingApprovalRequests, hasLength(1));
      expect(
        controller.pendingApprovalRequests.single.approvalId,
        'approval_c1',
      );
      // No assistant message committed while awaiting approval.
      expect(controller.messages, hasLength(1));
      expect(controller.messages.single.role, ModelMessageRole.user);
      controller.dispose();
    });

    test(
      'approval resume replays the exact pending call for a real provider',
      () async {
        final model = _ApprovalReplayModel();
        var executions = 0;
        final secureTool = tool<Map<String, dynamic>, String>(
          inputSchema: Schema<Map<String, dynamic>>(
            jsonSchema: const {'type': 'object'},
            fromJson: (json) => json,
          ),
          approvalPolicy: ToolApprovalPolicy.always,
          execute: (_, _) async {
            executions++;
            return 'approved';
          },
        );
        final controller = ChatController();
        final agent = ToolLoopAgent(
          model: model,
          tools: {'secureTool': secureTool},
          maxSteps: 3,
        );

        await controller.sendMessage(agent: agent, text: 'go');
        await pumpUntil(() => controller.status == ChatStatus.awaitingApproval);
        expect(
          controller.pendingApprovalRequests.single.approvalId,
          'approval_provider-call-1',
        );

        controller.addToolApprovalResponse(
          approvalId: 'approval_provider-call-1',
          approved: true,
        );
        await pumpUntil(() => controller.status == ChatStatus.ready);

        expect(executions, 1);
        expect(controller.messages.last.content, 'continued');
        final assistant = model.resumedMessages
            .where((message) => message.role == LanguageModelV4Role.assistant)
            .single;
        final replayedCall = assistant.content
            .whereType<LanguageModelV4ToolCallPart>()
            .single;
        expect(replayedCall.toolCallId, 'provider-call-1');
        final toolMessage = model.resumedMessages
            .where((message) => message.role == LanguageModelV4Role.tool)
            .single;
        final replayedResult = toolMessage.content
            .whereType<LanguageModelV4ToolResultPart>()
            .single;
        expect(replayedResult.toolCallId, 'provider-call-1');
        controller.dispose();
      },
    );

    test(
      'approving the tool preserves approval-step metadata after resume',
      () async {
        final controller = ChatController();
        final agent = RecordingStreamAgent();
        const source = LanguageModelV4SourcePart(
          id: 'source-1',
          url: 'https://example.com/weather',
          title: 'Weather source',
        );
        const call = LanguageModelV4ToolCallPart(
          toolCallId: 'c1',
          toolName: 'deleteFile',
          input: {'path': '/x'},
        );
        const result = LanguageModelV4ToolResultPart(
          toolCallId: 'c1',
          toolName: 'deleteFile',
          output: ToolResultOutputText('done'),
        );
        const request = LanguageModelV4ToolApprovalRequestPart(
          approvalId: 'approval_c1',
          toolCall: call,
        );

        unawaited(controller.sendMessage(agent: agent, text: 'go'));
        await pumpUntil(() => agent.invocations.length == 1);
        await agent.invocations.first.finish(
          finalText: '',
          steps: const [
            GenerateTextStep(
              stepNumber: 1,
              content: [call, source],
              toolCalls: [call],
              toolResults: [result],
              toolApprovalRequests: [request],
              response: LanguageModelV4GenerateResult(
                content: [call, source],
                finishReason: LanguageModelV4FinishReason.toolCalls,
              ),
              text: '',
              finishReason: LanguageModelV4FinishReason.toolCalls,
            ),
          ],
          sources: const [source],
          toolCalls: const [call],
          toolResults: const [result],
        );
        await pumpUntil(() => controller.status == ChatStatus.awaitingApproval);

        controller.addToolApprovalResponse(
          approvalId: 'approval_c1',
          approved: true,
        );
        await pumpUntil(() => agent.invocations.length == 2);
        agent.invocations.last.emitText('final answer');
        await agent.invocations.last.finish(finalText: 'final answer');
        await pumpUntil(() => controller.status == ChatStatus.ready);

        expect(controller.pendingApprovalRequests, isEmpty);
        expect(controller.messages.last.role, ModelMessageRole.assistant);
        expect(controller.messages.last.content, 'final answer');
        expect(controller.lastToolCalls, [call]);
        expect(controller.lastToolResults, [result]);
        expect(controller.lastSources, [source]);
        controller.dispose();
      },
    );

    test(
      'approval resume merges prior and resumed metadata without duplicates',
      () async {
        final controller = ChatController();
        final agent = RecordingStreamAgent();
        const firstSource = LanguageModelV4SourcePart(
          id: 'source-1',
          url: 'https://example.com/one',
          title: 'First source',
        );
        const secondSource = LanguageModelV4SourcePart(
          id: 'source-2',
          url: 'https://example.com/two',
          title: 'Second source',
        );
        const firstCall = LanguageModelV4ToolCallPart(
          toolCallId: 'c1',
          toolName: 'toolOne',
          input: {'step': 1},
        );
        const secondCall = LanguageModelV4ToolCallPart(
          toolCallId: 'c2',
          toolName: 'toolTwo',
          input: {'step': 2},
        );
        const firstResult = LanguageModelV4ToolResultPart(
          toolCallId: 'c1',
          toolName: 'toolOne',
          output: ToolResultOutputText('first'),
        );
        const secondResult = LanguageModelV4ToolResultPart(
          toolCallId: 'c2',
          toolName: 'toolTwo',
          output: ToolResultOutputText('second'),
        );
        const request = LanguageModelV4ToolApprovalRequestPart(
          approvalId: 'approval_c1',
          toolCall: firstCall,
        );

        unawaited(controller.sendMessage(agent: agent, text: 'go'));
        await pumpUntil(() => agent.invocations.length == 1);
        await agent.invocations.first.finish(
          finalText: '',
          steps: const [
            GenerateTextStep(
              stepNumber: 1,
              content: [firstCall, firstSource],
              toolCalls: [firstCall],
              toolResults: [firstResult],
              toolApprovalRequests: [request],
              response: LanguageModelV4GenerateResult(
                content: [firstCall, firstSource],
                finishReason: LanguageModelV4FinishReason.toolCalls,
              ),
              text: '',
              finishReason: LanguageModelV4FinishReason.toolCalls,
            ),
          ],
          sources: const [firstSource],
          toolCalls: const [firstCall],
          toolResults: const [firstResult],
        );
        await pumpUntil(() => controller.status == ChatStatus.awaitingApproval);

        controller.addToolApprovalResponse(
          approvalId: 'approval_c1',
          approved: true,
        );
        await pumpUntil(() => agent.invocations.length == 2);
        await agent.invocations.last.finish(
          finalText: 'merged answer',
          sources: const [secondSource],
          toolCalls: const [secondCall],
          toolResults: const [secondResult],
        );
        await pumpUntil(() => controller.status == ChatStatus.ready);

        expect(controller.lastSources, [firstSource, secondSource]);
        expect(controller.lastToolCalls, [firstCall, secondCall]);
        expect(controller.lastToolResults, [firstResult, secondResult]);
        controller.dispose();
      },
    );

    test('an agent.stream() that throws synchronously is caught', () async {
      Object? captured;
      final controller = ChatController(onError: (e) => captured = e);
      final failure = StateError('stream() threw');

      await controller.sendMessage(
        agent: ThrowingStreamAgent(failure),
        text: 'x',
      );
      await pumpUntil(() => controller.status == ChatStatus.error);

      expect(controller.status, ChatStatus.error);
      expect(controller.error, same(failure));
      expect(captured, same(failure));
      controller.dispose();
    });

    test('clear resets the surfaced state', () async {
      final controller = ChatController();
      await controller.sendMessage(agent: approvalAgent(), text: 'go');
      await pumpUntil(() => controller.status == ChatStatus.awaitingApproval);

      controller.clear();

      expect(controller.status, ChatStatus.ready);
      expect(controller.pendingApprovalRequests, isEmpty);
      expect(controller.messages, isEmpty);
      controller.dispose();
    });

    test('a second sendMessage supersedes the active turn and ignores stale '
        'events from the first turn', () async {
      final agent = RecordingStreamAgent();
      final controller = ChatController();

      unawaited(controller.sendMessage(agent: agent, text: 'first'));
      await pumpUntil(() => agent.invocations.length == 1);
      final first = agent.invocations.first;
      first.emitText('old answer');
      await pumpUntil(() => controller.streamingContent == 'old answer');

      unawaited(controller.sendMessage(agent: agent, text: 'second'));
      await pumpUntil(() => agent.invocations.length == 2);
      final second = agent.invocations.last;

      expect(first.abortSignal, isNotNull);
      expect(first.abortSignal!.isCancelled, isTrue);
      expect(first.textSubscriptionCancelled, isTrue);
      expect(first.fullStreamSubscriptionCancelled, isTrue);
      expect(controller.streamingContent, isEmpty);

      second.emitText('new answer');
      await second.finish(finalText: 'new answer');
      await pumpUntil(
        () =>
            controller.status == ChatStatus.ready &&
            controller.messages.length == 3,
      );

      first.emitText(' stale');
      first.emitError(StateError('stale'));
      await first.finish(finalText: 'old stale');
      await Future<void>.delayed(Duration.zero);

      expect(controller.messages.map((message) => message.content).toList(), [
        'first',
        'second',
        'new answer',
      ]);
      expect(controller.messages.last.role, ModelMessageRole.assistant);
      expect(controller.status, ChatStatus.ready);
      expect(controller.error, isNull);
      controller.dispose();
    });

    test('clear cancels the active turn and ignores late events', () async {
      final agent = RecordingStreamAgent();
      final controller = ChatController();

      unawaited(controller.sendMessage(agent: agent, text: 'first'));
      await pumpUntil(() => agent.invocations.length == 1);
      final invocation = agent.invocations.single;
      invocation.emitText('partial');
      await pumpUntil(() => controller.streamingContent == 'partial');

      controller.clear();

      expect(invocation.abortSignal, isNotNull);
      expect(invocation.abortSignal!.isCancelled, isTrue);
      expect(invocation.textSubscriptionCancelled, isTrue);
      expect(invocation.fullStreamSubscriptionCancelled, isTrue);
      expect(controller.messages, isEmpty);
      expect(controller.streamingContent, isEmpty);
      expect(controller.status, ChatStatus.ready);

      invocation.emitText(' late');
      invocation.emitError(StateError('late'));
      await invocation.finish(finalText: 'late');
      await Future<void>.delayed(Duration.zero);

      expect(controller.messages, isEmpty);
      expect(controller.error, isNull);
      controller.dispose();
    });

    test(
      'forwards full-stream subscription errors to controller error state',
      () async {
        final agent = RecordingStreamAgent();
        final controller = ChatController();

        unawaited(controller.sendMessage(agent: agent, text: 'go'));
        await pumpUntil(() => agent.invocations.length == 1);
        await pumpUntil(() => controller.status == ChatStatus.streaming);
        final invocation = agent.invocations.single;

        invocation.emitFullStreamFailure(StateError('full stream failed'));
        await pumpUntil(() => controller.status == ChatStatus.error);

        expect(controller.error, isA<StateError>());
        controller.dispose();
      },
    );

    test(
      'forwards addListener/removeListener/hasListeners to the root listenable',
      () {
        final controller = ChatController();
        void listener() {}

        expect(controller.hasListeners, isFalse);
        controller.addListener(listener);
        expect(controller.hasListeners, isTrue);
        controller.removeListener(listener);
        expect(controller.hasListeners, isFalse);
        controller.dispose();
      },
    );

    test('streaming deltas coalesce per frame and approval-free completion '
        'flushes without duplicate notifications', () async {
      final scheduler = FakeFrameNotificationScheduler();
      final agent = RecordingStreamAgent();
      final controller = ChatController(notificationScheduler: scheduler);
      var rootNotifications = 0;
      var statusNotifications = 0;
      var contentNotifications = 0;
      controller.addListener(() {
        rootNotifications++;
      });
      controller.statusListenable.addListener(() {
        statusNotifications++;
      });
      controller.contentListenable.addListener(() {
        contentNotifications++;
      });

      unawaited(controller.sendMessage(agent: agent, text: 'go'));
      await pumpUntil(() => agent.invocations.length == 1);
      await pumpUntil(() => controller.status == ChatStatus.streaming);
      final invocation = agent.invocations.single;

      rootNotifications = 0;
      statusNotifications = 0;
      contentNotifications = 0;

      invocation.emitText('a');
      invocation.emitText('b');
      invocation.emitReasoning('why');
      invocation.emitText('c');
      await pumpUntil(
        () =>
            controller.streamingContent == 'abc' &&
            controller.streamingReasoning == 'why',
      );

      expect(controller.streamingContent, 'abc');
      expect(controller.streamingReasoning, 'why');
      expect(rootNotifications, 0);
      expect(statusNotifications, 0);
      expect(contentNotifications, 0);
      expect(scheduler.pendingCallbackCount, 2);

      scheduler.flush();

      expect(rootNotifications, 1);
      expect(statusNotifications, 0);
      expect(contentNotifications, 1);

      invocation.emitText('d');
      await pumpUntil(() => controller.streamingContent == 'abcd');
      await invocation.finish(finalText: 'abcd', reasoningText: 'why');
      await pumpUntil(() => controller.status == ChatStatus.ready);

      expect(controller.messages.last.content, 'abcd');
      expect(controller.streamingContent, isEmpty);
      expect(rootNotifications, 2);
      expect(statusNotifications, 1);
      expect(contentNotifications, 2);
      expect(scheduler.pendingCallbackCount, 0);
      controller.dispose();
    });

    test('dispose cancels a queued frame notification', () async {
      final scheduler = FakeFrameNotificationScheduler();
      final agent = RecordingStreamAgent();
      final controller = ChatController(notificationScheduler: scheduler);
      var notifications = 0;
      controller.addListener(() {
        notifications++;
      });

      unawaited(controller.sendMessage(agent: agent, text: 'go'));
      await pumpUntil(() => agent.invocations.length == 1);
      await pumpUntil(() => controller.status == ChatStatus.streaming);
      final invocation = agent.invocations.single;

      notifications = 0;
      invocation.emitText('partial');
      await pumpUntil(() => controller.streamingContent == 'partial');
      expect(controller.streamingContent, 'partial');
      expect(scheduler.pendingCallbackCount, 2);

      controller.dispose();
      scheduler.flush();

      expect(notifications, 0);
    });
  });
}
