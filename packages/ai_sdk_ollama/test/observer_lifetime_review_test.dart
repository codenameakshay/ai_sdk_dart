import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_sdk_ollama/ai_sdk_ollama.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  for (final operation in ['generate', 'stream', 'embed']) {
    test(
      '$operation releases observable cancellation after completion',
      () async {
        final signal = _Signal();
        final dio = Dio()..httpClientAdapter = _Adapter();
        addTearDown(() => dio.close(force: true));
        addTearDown(signal.events.close);
        final provider = OllamaProvider(client: dio);
        for (var i = 0; i < 5; i++) {
          final options = LanguageModelV4CallOptions(
            prompt: const LanguageModelV4Prompt(messages: []),
            abortSignal: signal,
          );
          switch (operation) {
            case 'generate':
              await provider('fixture').doGenerate(options);
            case 'stream':
              await (await provider(
                'fixture',
              ).doStream(options)).stream.toList();
            case 'embed':
              await provider
                  .embedding('fixture')
                  .doEmbed(
                    EmbeddingModelV2CallOptions(
                      values: ['x'],
                      abortSignal: signal,
                    ),
                  );
          }
          expect(
            signal.futureReads,
            0,
            reason: 'Observable callers must use detachable subscriptions',
          );
          expect(signal.active, 0);
          expect(signal.attached, greaterThan(0));
        }
      },
    );
  }
}

class _Signal implements ObservableAbortSignal {
  final events = StreamController<void>.broadcast();
  final _cancelled = Completer<void>();
  int active = 0;
  int attached = 0;
  int futureReads = 0;
  @override
  bool get isCancelled => false;
  @override
  Future<void> get onCancelled {
    futureReads++;
    return _cancelled.future;
  }

  @override
  Stream<void> get cancellationEvents => Stream.multi((controller) {
    active++;
    attached++;
    final subscription = events.stream.listen(controller.addSync);
    controller.onCancel = () async {
      active--;
      await subscription.cancel();
    };
  });
}

class _Adapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final payload = options.path.endsWith('/embed')
        ? {
            'embeddings': [
              [1.0, 2.0],
            ],
          }
        : {
            'message': {'role': 'assistant', 'content': 'ok'},
            'done': true,
            'done_reason': 'stop',
          };
    final streaming = (options.data as Map)['stream'] == true;
    return ResponseBody.fromString(
      '${jsonEncode(payload)}${streaming ? '\n' : ''}',
      200,
      headers: {
        'content-type': [
          streaming ? 'application/x-ndjson' : 'application/json',
        ],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
