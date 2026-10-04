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

  test('reports EOF before message-end as truncation', () async {
    final client = Dio()
      ..httpClientAdapter = _StreamAdapter(
        Stream.value(
          Uint8List.fromList(
            utf8.encode(
              '{"type":"content-delta","delta":{"message":{"content":{"text":"partial"}}}}\n',
            ),
          ),
        ),
      );
    addTearDown(() => client.close(force: true));
    final result = await CohereProvider(client: client)
        .call('command-r-plus')
        .doStream(
          const LanguageModelV4CallOptions(
            prompt: LanguageModelV4Prompt(messages: []),
          ),
        );
    final parts = await result.stream.toList();
    expect(parts.whereType<StreamPartError>(), hasLength(1));
    expect(parts.whereType<StreamPartFinish>(), isEmpty);
  });

  test('empty response body reports truncation after one start', () async {
    final client = Dio()
      ..httpClientAdapter = _StreamAdapter(const Stream.empty());
    addTearDown(() => client.close(force: true));
    final result = await CohereProvider(client: client)
        .call('command-r-plus')
        .doStream(
          const LanguageModelV4CallOptions(
            prompt: LanguageModelV4Prompt(messages: []),
          ),
        );
    final parts = await result.stream.toList();
    expect(parts.whereType<StreamPartStreamStart>(), hasLength(1));
    expect(parts.whereType<StreamPartError>(), hasLength(1));
    expect(parts.whereType<StreamPartFinish>(), isEmpty);
  });

  test('message-end without content remains a valid empty finish', () async {
    final client = Dio()
      ..httpClientAdapter = _StreamAdapter(
        Stream.value(
          Uint8List.fromList(utf8.encode('{"type":"message-end","delta":{}}')),
        ),
      );
    addTearDown(() => client.close(force: true));
    final result = await CohereProvider(client: client)
        .call('command-r-plus')
        .doStream(
          const LanguageModelV4CallOptions(
            prompt: LanguageModelV4Prompt(messages: []),
          ),
        );
    final parts = await result.stream.toList();
    expect(parts.whereType<StreamPartStreamStart>(), hasLength(1));
    expect(parts.whereType<StreamPartError>(), isEmpty);
    expect(parts.whereType<StreamPartFinish>(), hasLength(1));
  });

  test('parses Cohere v2 SSE event and data framing', () async {
    final wire = [
      'event: content-delta',
      'data: ${jsonEncode({
        'type': 'content-delta',
        'delta': {
          'message': {
            'content': {'text': 'SSE answer'},
          },
        },
      })}',
      '',
      'event: message-end',
      'data: ${jsonEncode({
        'type': 'message-end',
        'delta': {
          'finish_reason': 'COMPLETE',
          'usage': {
            'tokens': {'input_tokens': 2, 'output_tokens': 3},
          },
        },
      })}',
      '',
    ].join('\n');
    final client = Dio()
      ..httpClientAdapter = _StreamAdapter(
        Stream.value(Uint8List.fromList(utf8.encode(wire))),
      );
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
      parts.whereType<StreamPartTextDelta>().map((part) => part.delta).join(),
      'SSE answer',
    );
    expect(
      parts.whereType<StreamPartFinish>().single.usage.outputTokens.total,
      3,
    );
  });
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
