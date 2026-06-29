import 'dart:async';

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
