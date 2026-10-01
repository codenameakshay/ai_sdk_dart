import 'dart:async';

import 'package:ai_sdk_google/ai_sdk_google.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  for (final streaming in [false, true]) {
    test(
      '${streaming ? 'streaming' : 'generation'} serialization failures detach cancellation listeners',
      () async {
        final client = Dio();
        addTearDown(() => client.close(force: true));
        final signal = _ObservableSignal();
        addTearDown(signal.events.close);
        final model = GoogleGenerativeAIProvider(
          apiKey: 'test',
          client: client,
        ).call('gemini-test');
        final options = LanguageModelV4CallOptions(
          abortSignal: signal,
          prompt: const LanguageModelV4Prompt(
            messages: [
              LanguageModelV4Message(
                role: LanguageModelV4Role.tool,
                content: [
                  LanguageModelV4ToolResultPart(
                    toolCallId: 'call-1',
                    toolName: 'lookup',
                    output: ToolResultOutputContent([
                      LanguageModelV4ReasoningPart(text: 'unsupported'),
                    ]),
                  ),
                ],
              ),
            ],
          ),
        );
        await expectLater(
          streaming ? model.doStream(options) : model.doGenerate(options),
          throwsUnsupportedError,
        );
        expect(signal.active, 0);
      },
    );
  }
}

class _ObservableSignal implements ObservableAbortSignal {
  final events = StreamController<void>.broadcast();
  final _cancelled = Completer<void>();
  int active = 0;

  @override
  bool get isCancelled => false;

  @override
  Future<void> get onCancelled => _cancelled.future;

  @override
  Stream<void> get cancellationEvents => Stream.multi((controller) {
    active++;
    final subscription = events.stream.listen(controller.addSync);
    controller.onCancel = () async {
      active--;
      await subscription.cancel();
    };
  });
}
