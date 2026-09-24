import 'dart:async';

import 'package:ai_sdk_openai_compatible/ai_sdk_openai_compatible.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  test('cancelTokenFor returns null without an abort signal', () {
    expect(cancelTokenFor(null), isNull);
  });

  test('cancelTokenFor mirrors pre-cancelled and later cancellation', () async {
    final preCancelled = _Signal()..cancel();
    final preCancelledToken = cancelTokenFor(preCancelled);
    expect(preCancelledToken, isNotNull);
    expect(preCancelledToken!.isCancelled, isTrue);

    final signal = _Signal();
    final token = cancelTokenFor(signal);
    expect(token, isNotNull);
    expect(token!.isCancelled, isFalse);
    signal.cancel();
    await signal.onCancelled;
    await Future<void>.delayed(Duration.zero);
    expect(token.isCancelled, isTrue);
  });

  for (final streaming in [false, true]) {
    test(
      'pre-cancelled compatible request skips auth (stream=$streaming)',
      () async {
        var authCalls = 0;
        final client = Dio();
        addTearDown(() => client.close(force: true));
        final model = OpenAICompatibleChatLanguageModel(
          modelId: 'fixture',
          config: OpenAICompatibleConfig(
            provider: 'fixture',
            baseUrl: 'http://provider.test',
            client: client,
            headers: () async {
              authCalls++;
              return const {};
            },
          ),
        );
        final options = LanguageModelV4CallOptions(
          prompt: const LanguageModelV4Prompt(messages: []),
          abortSignal: _Signal()..cancel(),
        );
        await expectLater(
          streaming ? model.doStream(options) : model.doGenerate(options),
          throwsA(anything),
        );
        expect(authCalls, 0);
      },
    );
  }
}

class _Signal implements AbortSignal {
  final _cancelled = Completer<void>();
  @override
  bool get isCancelled => _cancelled.isCompleted;
  @override
  Future<void> get onCancelled => _cancelled.future;
  void cancel() => _cancelled.complete();
}
