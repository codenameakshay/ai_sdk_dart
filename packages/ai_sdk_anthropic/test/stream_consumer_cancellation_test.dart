import 'dart:async';
import 'dart:typed_data';

import 'package:ai_sdk_anthropic/ai_sdk_anthropic.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  test(
    'consumer cancellation closes a silent response without an abort signal',
    () async {
      final source = StreamController<Uint8List>();
      final listening = Completer<void>();
      final cancelled = Completer<void>();
      source.onListen = listening.complete;
      source.onCancel = cancelled.complete;
      addTearDown(source.close);
      final client = Dio()..httpClientAdapter = _StreamAdapter(source.stream);
      addTearDown(() => client.close(force: true));
      final model = AnthropicProvider(client: client).call('claude-test');
      final result = await model.doStream(
        const LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(messages: []),
        ),
      );
      final subscription = result.stream.listen((_) {});
      await listening.future;
      await subscription.cancel();
      await cancelled.future.timeout(const Duration(seconds: 1));
    },
  );
}

class _StreamAdapter implements HttpClientAdapter {
  _StreamAdapter(this.source);

  final Stream<Uint8List> source;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody(source, 200);

  @override
  void close({bool force = false}) {}
}
