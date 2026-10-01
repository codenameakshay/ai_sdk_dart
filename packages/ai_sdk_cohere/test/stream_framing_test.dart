import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_sdk_cohere/ai_sdk_cohere.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  for (final fragmented in [false, true]) {
    test(
      fragmented
          ? 'decodes text split inside UTF-8 characters'
          : 'processes a final event without a trailing newline',
      () async {
        final events = [
          {
            'type': 'content-delta',
            'delta': {
              'message': {
                'content': {'text': 'नमस्ते 🌍'},
              },
            },
          },
          {
            'type': 'message-end',
            'delta': {
              'finish_reason': 'COMPLETE',
              'usage': {
                'tokens': {'input_tokens': 3, 'output_tokens': 5},
              },
            },
          },
        ];
        final bytes = utf8.encode(events.map(jsonEncode).join('\n'));
        final chunks = fragmented
            ? bytes.map((byte) => Uint8List.fromList([byte]))
            : [Uint8List.fromList(bytes)];
        final client = Dio()
          ..httpClientAdapter = _StreamAdapter(Stream.fromIterable(chunks));
        addTearDown(() => client.close(force: true));
        final result = await CohereProvider(client: client)
            .call('command-r-plus')
            .doStream(
              const LanguageModelV4CallOptions(
                prompt: LanguageModelV4Prompt(messages: []),
              ),
            );
        final parts = await result.stream.toList();
        expect(parts.whereType<StreamPartError>(), isEmpty);
        expect(
          parts
              .whereType<StreamPartTextDelta>()
              .map((part) => part.delta)
              .join(),
          'नमस्ते 🌍',
        );
        final finish = parts.whereType<StreamPartFinish>().single;
        expect(finish.finishReason, LanguageModelV4FinishReason.stop);
        expect(finish.usage.outputTokens.total, 5);
      },
    );
  }
}

class _StreamAdapter implements HttpClientAdapter {
  _StreamAdapter(this.chunks);

  final Stream<Uint8List> chunks;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody(chunks, 200);

  @override
  void close({bool force = false}) {}
}
