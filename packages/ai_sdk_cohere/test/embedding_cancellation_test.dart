import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_cohere/ai_sdk_cohere.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import '../../ai_sdk_provider/test/support/cancellation_adapter.dart';

void main() {
  test('embedding cancellation closes the live HTTP request socket', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final started = Completer<void>();
    final disconnected = Completer<void>();
    server.listen((request) async {
      await utf8.decoder.bind(request).join();
      final socket = await request.response.detachSocket(writeHeaders: false);
      addTearDown(socket.destroy);
      socket.listen(
        (_) {},
        onDone: disconnected.complete,
        onError: (Object _) {
          if (!disconnected.isCompleted) disconnected.complete();
        },
      );
      started.complete();
    });
    final provider = CohereProvider(
      apiKey: 'fixture',
      baseUrl: 'http://127.0.0.1:${server.port}',
    );
    addTearDown(provider.dispose);
    final signal = TestAbortSignal();
    final error = expectLater(
      provider
          .embedding('fixture')
          .doEmbed(
            EmbeddingModelV2CallOptions(values: ['a'], abortSignal: signal),
          ),
      throwsA(isA<AiOperationCancelledError>()),
    );
    await started.future.timeout(const Duration(seconds: 2));
    signal.cancel();
    await error.timeout(const Duration(seconds: 2));
    await disconnected.future.timeout(const Duration(seconds: 2));
  });
}
