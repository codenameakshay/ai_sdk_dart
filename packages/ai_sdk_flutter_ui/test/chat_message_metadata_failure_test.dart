import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  test('a usage failure does not discard the reported finish reason', () async {
    final controller = ChatController();
    addTearDown(controller.dispose);
    final agent = RecordingStreamAgent();

    await controller.sendMessage(agent: agent, text: 'question');
    final invocation = agent.invocations.single;
    invocation.emitText('answer');
    await pumpUntil(() => controller.streamingContent == 'answer');
    invocation.failUsage(StateError('usage unavailable'));
    await invocation.finish(finalText: 'answer');
    await pumpUntil(() => controller.status == ChatStatus.ready);

    expect(controller.messages.last.content, 'answer');
    expect(controller.chatMessages.last.provider, 'mock');
    expect(controller.chatMessages.last.modelId, 'mock-language-model');
    expect(
      controller.chatMessages.last.finishReason,
      LanguageModelV4FinishReason.stop,
    );
  });
}
