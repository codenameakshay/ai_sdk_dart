import 'dart:async';
import 'dart:typed_data';

import 'package:ai_sdk_openai_compatible/ai_sdk_openai_compatible.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  for (final streaming in [false, true]) {
    test(
      'actual Chat requests release each observer (stream=$streaming)',
      () async {
        final signal = _Signal();
        addTearDown(signal.close);
        final adapter = _Adapter();
        final dio = Dio()..httpClientAdapter = adapter;
        addTearDown(() => dio.close(force: true));
        final model = OpenAICompatibleChatLanguageModel(
          modelId: 'fixture',
          config: OpenAICompatibleConfig(
            provider: 'fixture',
            baseUrl: 'http://fixture.test',
            client: dio,
            headers: () async => const {},
          ),
        );
        for (var iteration = 0; iteration < 10; iteration++) {
          adapter.fail = iteration.isOdd;
          final options = LanguageModelV4CallOptions(
            prompt: const LanguageModelV4Prompt(messages: []),
            abortSignal: signal,
          );
          Future<void> request() async {
            if (streaming) {
              final result = await model.doStream(options);
              await result.stream.toList();
            } else {
              await model.doGenerate(options);
            }
          }

          if (adapter.fail) {
            await expectLater(request(), throwsA(isA<AiApiCallError>()));
          } else {
            await request();
          }
          expect(signal.active, 0, reason: 'request $iteration');
          expect(signal.detached, signal.attached);
        }
        expect(signal.attached, greaterThanOrEqualTo(10));
      },
    );
  }
}

class _Signal implements ObservableAbortSignal {
  final events = StreamController<void>.broadcast();
  var active = 0;
  var attached = 0;
  var detached = 0;
  @override
  bool get isCancelled => false;
  @override
  Future<void> get onCancelled => Completer<void>().future;
  @override
  Stream<void> get cancellationEvents => Stream.multi((controller) {
    attached++;
    active++;
    final subscription = events.stream.listen(controller.addSync);
    controller.onCancel = () {
      active--;
      detached++;
      return subscription.cancel();
    };
  }, isBroadcast: true);
  Future<void> close() => events.close();
}

class _Adapter implements HttpClientAdapter {
  bool fail = false;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final streaming = (options.data as Map)['stream'] == true;
    return ResponseBody.fromString(
      fail
          ? '{"error":{"message":"fixture failure","code":"invalid_request"}}'
          : streaming
          ? 'data: {"choices":[{"delta":{"content":"ok"},"finish_reason":"stop"}]}\n\ndata: [DONE]\n\n'
          : '{"choices":[{"message":{"content":"ok"},"finish_reason":"stop"}]}',
      fail ? 400 : 200,
      headers: {
        'content-type': [
          streaming && !fail ? 'text/event-stream' : 'application/json',
        ],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
