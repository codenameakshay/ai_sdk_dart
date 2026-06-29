import 'dart:async';
import 'dart:convert';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_dart/test.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';

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
  }) async {
    throw error;
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
