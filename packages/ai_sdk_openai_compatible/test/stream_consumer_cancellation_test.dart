import 'dart:async';
import 'dart:typed_data';

import 'package:ai_sdk_openai_compatible/ai_sdk_openai_compatible.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  test(
    'consumer cancellation closes a silent Chat response without a signal',
    () async {
      final source = StreamController<Uint8List>();
      final cancelled = Completer<void>();
      source.onCancel = () => cancelled.complete();
      final dio = Dio()..httpClientAdapter = _StreamAdapter(source.stream);
      addTearDown(() => dio.close(force: true));
      final model = OpenAICompatibleChatLanguageModel(
        modelId: 'm',
        config: OpenAICompatibleConfig(
          provider: 'test',
          baseUrl: 'http://chat.test',
          client: dio,
          headers: () => const {},
        ),
      );
      final result = await model.doStream(
        const LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(messages: []),
        ),
      );
      final subscription = result.stream.listen((_) {});
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
