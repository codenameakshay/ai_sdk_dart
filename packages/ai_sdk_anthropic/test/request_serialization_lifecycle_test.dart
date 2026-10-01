import 'dart:async';

import 'package:ai_sdk_anthropic/ai_sdk_anthropic.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  for (final streaming in [false, true]) {
    test(
      '${streaming ? 'streaming' : 'generation'} reasoning configuration failures detach cancellation listeners',
      () async {
        final client = Dio();
        addTearDown(() => client.close(force: true));
        final signal = _ObservableSignal();
        addTearDown(signal.events.close);
        final model = AnthropicProvider(
          client: client,
        ).call('claude-3-7-sonnet');
        final options = LanguageModelV4CallOptions(
          abortSignal: signal,
          prompt: const LanguageModelV4Prompt(messages: []),
          maxOutputTokens: 512,
          reasoning: LanguageModelV4Reasoning.low,
        );
        await expectLater(
          streaming ? model.doStream(options) : model.doGenerate(options),
          throwsArgumentError,
        );
        expect(signal.active, 0);
      },
    );
    test(
      '${streaming ? 'streaming' : 'generation'} serialization failures detach cancellation listeners',
      () async {
        final client = Dio();
        addTearDown(() => client.close(force: true));
        final signal = _ObservableSignal();
        addTearDown(signal.events.close);
        final model = AnthropicProvider(client: client).call('claude-test');
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
