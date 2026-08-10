import 'dart:async';
import 'dart:convert';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_dart/test.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:flutter/foundation.dart';

/// Builds a [ToolLoopAgent] whose model streams [text] as a single text part.
ToolLoopAgent textAgent(String text) {
  return ToolLoopAgent(model: MockLanguageModelV3(response: [mockText(text)]));
}

/// A language model that emits a text delta and then *holds* the stream open
/// (no finish part) until [finish] is called — useful for asserting transient
/// streaming UI (e.g. the optimistic in-flight bubble) that an immediate mock
/// would race past.
class HoldingTextModel implements LanguageModelV3 {
  HoldingTextModel(this.text);

  final String text;
  final _controller = StreamController<LanguageModelV3StreamPart>();

  /// Emits the finish part and closes the stream.
  void finish() {
    if (_controller.isClosed) return;
    _controller.add(
      const StreamPartFinish(
        finishReason: LanguageModelV3FinishReason.stop,
        rawFinishReason: 'stop',
      ),
    );
    _controller.close();
  }

  @override
  String get provider => 'mock';
  @override
  String get modelId => 'holding-text';
  @override
  String get specificationVersion => 'v3';

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async {
    return LanguageModelV3GenerateResult(
      content: [LanguageModelV3TextPart(text: text)],
      finishReason: LanguageModelV3FinishReason.stop,
    );
  }

  @override
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  ) async {
    const id = 'text-1';
    _controller
      ..add(const StreamPartTextStart(id: id))
      ..add(StreamPartTextDelta(id: id, delta: text))
      ..add(const StreamPartTextEnd(id: id));
    return LanguageModelV3StreamResult(stream: _controller.stream);
  }
}

/// Pumps the event loop until [condition] is true or [tries] is exhausted.
///
/// The controllers drive `streamText`, which delivers stream events on later
/// microtasks/timer ticks — so awaiting a `sendMessage`/`complete` call only
/// guarantees the stream *started*, not that it finished. Use this to wait for
/// a terminal state in tests.
Future<void> pumpUntil(bool Function() condition, {int tries = 200}) async {
  for (var i = 0; i < tries; i++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
}

/// Builds a [ToolLoopAgent] whose model throws on stream, to exercise error
/// paths.
ToolLoopAgent erroringAgent(Object error) {
  return ToolLoopAgent(model: MockLanguageModelV3(doStreamError: error));
}

/// A language model that throws [error] synchronously from `doStream`, before
/// any stream is opened — so the `await agent.stream(...)` call itself rejects
/// and is handled by the controller's surrounding try/catch rather than its
/// stream-error listener.
class _SyncThrowingModel implements LanguageModelV3 {
  _SyncThrowingModel(this.error);

  final Object error;

  @override
  String get provider => 'mock';
  @override
  String get modelId => 'sync-throwing';
  @override
  String get specificationVersion => 'v3';

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) {
    throw error;
  }

  @override
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  ) {
    throw error;
  }
}

/// Builds a [ToolLoopAgent] whose model throws synchronously, so the
/// `agent.stream()` future rejects (exercising the controller's try/catch).
ToolLoopAgent syncThrowingAgent(Object error) {
  return ToolLoopAgent(model: _SyncThrowingModel(error));
}

/// An agent whose `stream(...)` itself throws synchronously — so the awaited
/// `agent.stream(...)` call rejects and is handled by the controller's
/// surrounding try/catch (rather than its stream-error listener).
class ThrowingStreamAgent extends ToolLoopAgent {
  ThrowingStreamAgent(this.error) : super(model: MockLanguageModelV3());

  final Object error;

  @override
  Future<StreamTextResult> stream({
    String? prompt,
    List<ModelMessage>? messages,
    List<LanguageModelV3ToolApprovalResponse> toolApprovalResponses = const [],
    CancellationToken? abortSignal,
    Duration? timeout,
  }) async {
    throw error;
  }
}

class RecordedStreamInvocation {
  RecordedStreamInvocation({
    required this.abortSignal,
    required this.prompt,
    required this.messages,
    required this.toolApprovalResponses,
  });

  final CancellationToken? abortSignal;
  final String? prompt;
  final List<ModelMessage>? messages;
  final List<LanguageModelV3ToolApprovalResponse> toolApprovalResponses;

  late final StreamController<String> _textController =
      StreamController<String>(
        onCancel: () {
          textSubscriptionCancelled = true;
        },
      );
  late final StreamController<StreamTextEvent> _fullController =
      StreamController<StreamTextEvent>(
        onCancel: () {
          fullStreamSubscriptionCancelled = true;
        },
      );
  final Completer<String> _textCompleter = Completer<String>();
  final Completer<Object?> _outputCompleter = Completer<Object?>();
  final Completer<List<LanguageModelV3ContentPart>> _contentCompleter =
      Completer<List<LanguageModelV3ContentPart>>();
  final Completer<String> _reasoningTextCompleter = Completer<String>();
  final Completer<List<GenerateTextStep>> _stepsCompleter =
      Completer<List<GenerateTextStep>>();
  final Completer<LanguageModelV3Usage?> _usageCompleter =
      Completer<LanguageModelV3Usage?>();
  final Completer<LanguageModelV3Usage?> _totalUsageCompleter =
      Completer<LanguageModelV3Usage?>();
  final Completer<List<LanguageModelV3SourcePart>> _sourcesCompleter =
      Completer<List<LanguageModelV3SourcePart>>();
  final Completer<List<LanguageModelV3ToolCallPart>> _toolCallsCompleter =
      Completer<List<LanguageModelV3ToolCallPart>>();
  final Completer<List<LanguageModelV3ToolResultPart>> _toolResultsCompleter =
      Completer<List<LanguageModelV3ToolResultPart>>();

  bool textSubscriptionCancelled = false;
  bool fullStreamSubscriptionCancelled = false;

  StreamTextResult<Object?> buildResult() {
    return StreamTextResult<Object?>(
      stream: const Stream.empty(),
      fullStream: _fullController.stream,
      textStream: _textController.stream,
      partialOutputStream: const Stream.empty(),
      elementStream: const Stream.empty(),
      text: _textCompleter.future,
      output: _outputCompleter.future,
      content: _contentCompleter.future,
      reasoning: Future.value(const []),
      reasoningText: _reasoningTextCompleter.future,
      files: Future.value(const []),
      sources: _sourcesCompleter.future,
      toolCalls: _toolCallsCompleter.future,
      toolResults: _toolResultsCompleter.future,
      finishReason: Future.value(LanguageModelV3FinishReason.stop),
      rawFinishReason: Future.value('stop'),
      usage: _usageCompleter.future,
      totalUsage: _totalUsageCompleter.future,
      warnings: Future.value(const []),
      steps: _stepsCompleter.future,
      request: Future.value(
        const GenerateTextRequest(system: null, messages: []),
      ),
      response: Future.value(
        const GenerateTextResponse(messages: [], body: null, metadata: null),
      ),
      providerMetadata: Future.value(null),
      finish: Future.value(
        const StreamPartFinish(
          finishReason: LanguageModelV3FinishReason.stop,
          rawFinishReason: 'stop',
        ),
      ),
    );
  }

  void emitText(String delta) {
    _textController.add(delta);
  }

  void emitReasoning(String delta, {String id = 'reasoning-1'}) {
    _fullController.add(StreamTextReasoningDeltaEvent(id: id, delta: delta));
  }

  void emitError(Object error) {
    _fullController.add(StreamTextErrorEvent(error: error));
  }

  Future<void> finish({
    String finalText = '',
    String reasoningText = '',
    LanguageModelV3Usage? usage,
    List<GenerateTextStep> steps = const [],
    List<LanguageModelV3SourcePart> sources = const [],
    List<LanguageModelV3ToolCallPart> toolCalls = const [],
    List<LanguageModelV3ToolResultPart> toolResults = const [],
  }) async {
    if (!_textCompleter.isCompleted) _textCompleter.complete(finalText);
    if (!_outputCompleter.isCompleted) _outputCompleter.complete(finalText);
    if (!_contentCompleter.isCompleted) {
      _contentCompleter.complete([
        if (finalText.isNotEmpty) LanguageModelV3TextPart(text: finalText),
      ]);
    }
    if (!_reasoningTextCompleter.isCompleted) {
      _reasoningTextCompleter.complete(reasoningText);
    }
    if (!_stepsCompleter.isCompleted) _stepsCompleter.complete(steps);
    if (!_usageCompleter.isCompleted) _usageCompleter.complete(usage);
    if (!_totalUsageCompleter.isCompleted) _totalUsageCompleter.complete(usage);
    if (!_sourcesCompleter.isCompleted) _sourcesCompleter.complete(sources);
    if (!_toolCallsCompleter.isCompleted)
      _toolCallsCompleter.complete(toolCalls);
    if (!_toolResultsCompleter.isCompleted) {
      _toolResultsCompleter.complete(toolResults);
    }
    await _fullController.close();
    await _textController.close();
  }
}

class RecordingStreamAgent extends ToolLoopAgent {
  RecordingStreamAgent() : super(model: MockLanguageModelV3());

  final List<RecordedStreamInvocation> invocations = [];

  @override
  Future<StreamTextResult> stream({
    String? prompt,
    List<ModelMessage>? messages,
    List<LanguageModelV3ToolApprovalResponse> toolApprovalResponses = const [],
    CancellationToken? abortSignal,
    Duration? timeout,
  }) async {
    final invocation = RecordedStreamInvocation(
      abortSignal: abortSignal,
      prompt: prompt,
      messages: messages,
      toolApprovalResponses: toolApprovalResponses,
    );
    invocations.add(invocation);
    return invocation.buildResult();
  }
}

/// A simple object schema returning the JSON map unchanged.
final Schema<Map<String, dynamic>> mapSchema = Schema<Map<String, dynamic>>(
  jsonSchema: const {
    'type': 'object',
    'properties': {
      'title': {'type': 'string'},
    },
  },
  fromJson: (json) => json,
);

/// Builds a [ToolLoopAgent] that streams [text] and reports [usage] on finish.
ToolLoopAgent textAgentWithUsage(String text, LanguageModelV3Usage usage) {
  return ToolLoopAgent(
    model: MockLanguageModelV3(response: [mockText(text)], usage: usage),
  );
}

/// Builds a [ToolLoopAgent] that streams a reasoning part then [text].
ToolLoopAgent reasoningAgent({
  required String reasoning,
  required String text,
}) {
  return ToolLoopAgent(
    model: MockLanguageModelV3(
      response: [mockReasoning(reasoning), mockText(text)],
    ),
  );
}

/// A language model that returns a different scripted response on each
/// `doStream` call, repeating the last entry once exhausted.
///
/// Lets a test drive a multi-step tool loop — e.g. `[[toolCall], [toolCall],
/// [text]]` models "call a tool, re-issue it after approval, then answer".
class QueuedStreamModel implements LanguageModelV3 {
  QueuedStreamModel(this.responses, {this.usage});

  final List<List<LanguageModelV3ContentPart>> responses;
  final LanguageModelV3Usage? usage;
  int _call = 0;

  @override
  String get provider => 'mock';
  @override
  String get modelId => 'queued';
  @override
  String get specificationVersion => 'v3';

  List<LanguageModelV3ContentPart> _nextResponse() {
    final index = _call < responses.length ? _call : responses.length - 1;
    _call++;
    return responses[index];
  }

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async {
    return LanguageModelV3GenerateResult(
      content: _nextResponse(),
      finishReason: LanguageModelV3FinishReason.stop,
      usage: usage,
    );
  }

  @override
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  ) async {
    final response = _nextResponse();
    final parts = <LanguageModelV3StreamPart>[];
    var i = 0;
    for (final part in response) {
      final id = 'text-$_call-$i';
      if (part is LanguageModelV3TextPart) {
        parts
          ..add(StreamPartTextStart(id: id))
          ..add(StreamPartTextDelta(id: id, delta: part.text))
          ..add(StreamPartTextEnd(id: id));
      } else if (part is LanguageModelV3ReasoningPart) {
        parts.add(StreamPartReasoningDelta(delta: part.text));
      } else if (part is LanguageModelV3ToolCallPart) {
        parts
          ..add(
            StreamPartToolCallStart(
              toolCallId: part.toolCallId,
              toolName: part.toolName,
            ),
          )
          ..add(
            StreamPartToolCallDelta(
              toolCallId: part.toolCallId,
              toolName: part.toolName,
              argsTextDelta: jsonEncode(part.input),
            ),
          )
          ..add(
            StreamPartToolCallEnd(
              toolCallId: part.toolCallId,
              toolName: part.toolName,
              input: part.input,
            ),
          );
      }
      i++;
    }
    parts.add(
      StreamPartFinish(
        finishReason: LanguageModelV3FinishReason.stop,
        rawFinishReason: 'stop',
        usage: usage,
      ),
    );
    return LanguageModelV3StreamResult(stream: Stream.fromIterable(parts));
  }
}

/// A tool that always requires approval and returns [output] when executed.
Tool<Map<String, dynamic>, String> approvalTool(String output) {
  return Tool<Map<String, dynamic>, String>(
    inputSchema: Schema<Map<String, dynamic>>(
      jsonSchema: const {'type': 'object'},
      fromJson: (json) => json,
    ),
    requiresApproval: true,
    executeDynamic: (input, options) async => output,
  );
}

/// An agent that calls [toolName] (which needs approval), then — once the call
/// is approved — replies with [finalText].
ToolLoopAgent approvalAgent({
  String toolName = 'deleteFile',
  String finalText = 'final answer',
  String toolCallId = 'c1',
}) {
  final call = mockToolCall(
    toolName: toolName,
    input: const {'path': '/x'},
    toolCallId: toolCallId,
  );
  return ToolLoopAgent(
    model: QueuedStreamModel([
      [call],
      [call],
      [mockText(finalText)],
    ]),
    tools: {toolName: approvalTool('done')},
    maxSteps: 5,
  );
}

class FakeFrameNotificationScheduler implements FrameNotificationScheduler {
  final Map<int, VoidCallback> _callbacks = <int, VoidCallback>{};
  int _nextId = 0;

  int get pendingCallbackCount => _callbacks.length;

  @override
  CancelFrameNotification schedule(VoidCallback callback) {
    final id = ++_nextId;
    _callbacks[id] = callback;
    return () {
      _callbacks.remove(id);
    };
  }

  void flush() {
    final callbacks = _callbacks.values.toList();
    _callbacks.clear();
    for (final callback in callbacks) {
      callback();
    }
  }
}
