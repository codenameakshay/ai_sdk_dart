import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_dart/test.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

class _InterleavedModel extends MockLanguageModelV4 {
  final chunks = StreamController<LanguageModelV4StreamPart>();

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async => LanguageModelV4StreamResult(stream: chunks.stream);
}

void main() {
  test('ChatController keeps interleaved reasoning out of the reply', () async {
    final source = _InterleavedModel();
    var finishes = 0;
    ModelMessage? finished;
    final controller = ChatController(
      onFinish: (message) {
        finishes++;
        finished = message;
      },
    );
    addTearDown(controller.dispose);
    final statuses = <ChatStatus>[];
    controller.addListener(() => statuses.add(controller.status));
    await controller.sendMessage(
      agent: ToolLoopAgent(
        model: wrapLanguageModel(
          model: source,
          middleware: extractReasoningMiddleware(),
        ),
      ),
      text: 'go',
    );
    for (final part in const <LanguageModelV4StreamPart>[
      StreamPartTextStart(id: 'a'),
      StreamPartTextStart(id: 'b'),
      StreamPartTextDelta(id: 'a', delta: '<thi'),
      StreamPartRaw(rawValue: {'diagnostic': true}),
      StreamPartTextDelta(id: 'b', delta: '<think>beta</think>BBBBBBBBBBBB'),
      StreamPartTextDelta(id: 'a', delta: 'nk>alpha</thi'),
      StreamPartRaw(rawValue: {'diagnostic': false}),
      StreamPartTextDelta(id: 'a', delta: 'nk>AAAAAAAAAAAA'),
      StreamPartTextEnd(id: 'b'),
      StreamPartTextEnd(id: 'a'),
    ]) {
      source.chunks.add(part);
    }
    await pumpUntil(() => controller.streamingContent.length == 24);
    final visible = controller.streamingContent;
    expect(visible.length, 24);
    expect(visible.replaceAll('A', '').replaceAll('B', ''), isEmpty);
    expect(controller.streamingReasoning, 'betaalpha');
    expect(controller.status, ChatStatus.streaming);
    source.chunks.add(
      const StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
    );
    await source.chunks.close();
    await pumpUntil(() => finishes == 1);
    expect(finishes, 1);
    expect(controller.status, ChatStatus.ready);
    expect(controller.error, isNull);
    expect(controller.messages, hasLength(2));
    expect(controller.messages.last.text, visible);
    expect(finished!.text, visible);
    expect(controller.reasoningText, 'betaalpha');
    expect(
      controller.chatMessages.last.finishReason,
      LanguageModelV4FinishReason.stop,
    );
    expect(
      statuses,
      containsAllInOrder([
        ChatStatus.submitted,
        ChatStatus.streaming,
        ChatStatus.ready,
      ]),
    );
  });
}
