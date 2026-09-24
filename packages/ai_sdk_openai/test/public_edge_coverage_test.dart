import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  test('default provider instance is public', () {
    expect(openai, isA<OpenAIProvider>());
  });

  test('batch exceptions and non-positive timeouts fail locally', () {
    expect(
      const OpenAIBatchException('bad').toString(),
      'OpenAIBatchException: bad',
    );
    expect(
      OpenAIBatchSubmissionException(
        const DataContentProviderReference(namespace: 'openai', id: 'file-1'),
        StateError('cause'),
      ).toString(),
      contains('cause'),
    );
    final files = OpenAIFiles(
      client: Dio()..httpClientAdapter = _Adapter((_) => '{}'),
      headers: () async => const {},
      baseUrl: 'https://api.openai.test/v1/',
    );
    expect(
      () => files.retrieve(
        const DataContentProviderReference(namespace: 'openai', id: 'file-1'),
        timeout: Duration.zero,
      ),
      throwsArgumentError,
    );
    expect(
      () => files.retrieve(
        const DataContentProviderReference(namespace: 'openai', id: 'file-1'),
        timeout: const Duration(microseconds: -1),
      ),
      throwsArgumentError,
    );
  });

  test(
    'file helpers serialize and download setup failures propagate',
    () async {
      expect(OpenAIFileException('bad').toString(), 'OpenAIFileException: bad');
      expect(const OpenAIFileExpiry(seconds: 60).toJson(), {
        'anchor': 'created_at',
        'seconds': 60,
      });

      final dio = Dio();
      addTearDown(() => dio.close(force: true));
      final files = OpenAIFiles(
        client: dio,
        headers: () async => throw StateError('auth failed'),
        baseUrl: 'https://api.openai.test/v1',
      );
      await expectLater(
        files.download(
          const DataContentProviderReference(namespace: 'openai', id: 'file-1'),
        ),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'stream maps file annotations and hosted MCP fallback identifiers',
    () async {
      final parts = await (await _model(
        _Adapter.streaming([
          {
            'type': 'response.output_text.annotation.added',
            'annotation': {
              'type': 'file_citation',
              'file_id': 'file-1',
              'filename': 'report.pdf',
            },
          },
          {
            'type': 'response.output_item.done',
            'item': {
              'type': 'mcp_approval_request',
              'id': 'approval-1',
              'name': 'search',
              'arguments': {'query': 'Dart'},
            },
          },
          {
            'type': 'response.completed',
            'response': {'id': 'r1', 'status': 'completed'},
          },
        ]),
      ).doStream(_options())).stream.toList();

      expect(parts.whereType<StreamPartFile>(), isEmpty);
      expect(
        parts.whereType<StreamPartDocumentSource>().single.source.filename,
        'report.pdf',
      );
      final call = parts.whereType<StreamPartToolCall>().single.toolCall;
      expect(call.toolCallId, 'approval-1');
      expect(call.input, {'query': 'Dart'});
      expect(parts.whereType<StreamPartToolApprovalRequest>(), hasLength(1));
    },
  );

  test(
    'generate uses hosted MCP item id as the approval id fallback',
    () async {
      final result = await _model(
        _Adapter(
          (_) => jsonEncode({
            'id': 'r1',
            'status': 'completed',
            'output': [
              {
                'type': 'mcp_approval_request',
                'id': 'approval-gen',
                'name': 'search',
                'arguments': {'query': 'Dart'},
              },
            ],
          }),
        ),
      ).doGenerate(_options());

      expect(
        result.content
            .whereType<LanguageModelV4ToolCallPart>()
            .single
            .toolCallId,
        'approval-gen',
      );
      expect(
        result.content
            .whereType<LanguageModelV4ToolApprovalRequestPart>()
            .single
            .approvalId,
        'approval-gen',
      );
    },
  );

  test('stream rejects a null response body', () async {
    final dio = Dio()..interceptors.add(_NullStreamBodyInterceptor());
    addTearDown(() => dio.close(force: true));
    final model = OpenAIResponsesLanguageModel(
      modelId: 'gpt-test',
      client: dio,
      headers: () async => const {},
      baseUrl: 'https://api.openai.test/v1/responses',
    );

    await expectLater(
      model.doStream(_options()),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('stream body is null'),
        ),
      ),
    );
  });

  test(
    'computer output rejects non-screenshot outputs and accepts error JSON',
    () async {
      final adapter = _Adapter.generate();
      final model = _model(adapter);
      Future<void> send(LanguageModelV4ToolResultOutput output) =>
          model.doGenerate(
            LanguageModelV4CallOptions(
              prompt: LanguageModelV4Prompt(
                messages: [
                  LanguageModelV4Message(
                    role: LanguageModelV4Role.tool,
                    content: [
                      LanguageModelV4ToolResultPart(
                        toolCallId: 'computer-1',
                        toolName: 'computer',
                        output: output,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );

      await send(
        const ToolResultOutputErrorJson({
          'output': {
            'type': 'computer_screenshot',
            'imageUrl': 'https://example.test/screenshot.png',
          },
        }),
      );
      await expectLater(
        send(const ToolResultOutputText('not a screenshot')),
        throwsA(isA<UnsupportedError>()),
      );
      await expectLater(
        send(
          ToolResultOutputContent([
            LanguageModelV4TextPart(text: 'no screenshot'),
            LanguageModelV4ImagePart(
              image: DataContentUrl(Uri.parse('https://example.test/a.png')),
              mediaType: 'image/png',
            ),
          ]),
        ),
        throwsA(isA<UnsupportedError>()),
      );

      for (final invalid in [
        <String, dynamic>{
          'output': {'type': 'computer_screenshot'},
        },
        <String, dynamic>{
          'output': {'type': 'computer_screenshot', 'imageUrl': 1},
        },
        <String, dynamic>{
          'output': {'type': 'computer_screenshot', 'imageUrl': 'x'},
          'acknowledgedSafetyChecks': [
            {'id': 'safe', 'code': 1},
          ],
        },
      ]) {
        await expectLater(
          send(ToolResultOutputJson(invalid)),
          throwsA(isA<FormatException>()),
        );
      }

      await expectLater(
        send(
          ToolResultOutputJson({
            'output': {
              'type': 'computer_screenshot',
              'imageUrl': 'https://example.test/a.png',
              'fileId': 1,
            },
          }),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('Computer screenshot references must be strings.'),
          ),
        ),
      );
    },
  );

  test(
    'function argument events preserve identity and reject invalid order',
    () async {
      final parts = await (await _model(
        _Adapter.streaming([
          {
            'type': 'response.output_item.added',
            'item': {
              'type': 'function_call',
              'id': 'fn-1',
              'call_id': 'call-1',
              'name': 'lookup',
            },
          },
          {
            'type': 'response.function_call_arguments.delta',
            'item_id': 'fn-1',
            'delta': '{"query":',
          },
          {
            'type': 'response.function_call_arguments.delta',
            'item_id': 'fn-1',
            'delta': '"Dart"}',
          },
          {
            'type': 'response.function_call_arguments.done',
            'item_id': 'fn-1',
            'arguments': '{"query":"Dart"}',
          },
          {
            'type': 'response.completed',
            'response': {'id': 'r1', 'status': 'completed'},
          },
        ]),
      ).doStream(_options())).stream.toList();
      expect(parts.whereType<StreamPartToolInputStart>(), hasLength(1));
      expect(parts.whereType<StreamPartToolInputDelta>(), hasLength(2));
      expect(parts.whereType<StreamPartToolInputEnd>(), hasLength(1));
      expect(parts.whereType<StreamPartToolCall>().single.toolCall.input, {
        'query': 'Dart',
      });

      for (final events in [
        [
          {
            'type': 'response.output_item.added',
            'item': {
              'type': 'function_call',
              'id': 'fn-1',
              'call_id': 'call-1',
              'name': 'lookup',
            },
          },
          {
            'type': 'response.output_item.done',
            'item': {
              'type': 'function_call',
              'id': 'fn-1',
              'call_id': 'changed',
              'name': 'lookup',
            },
          },
        ],
        [
          {
            'type': 'response.function_call_arguments.done',
            'item_id': 'unknown',
          },
        ],
      ]) {
        final errors = await (await _model(
          _Adapter.streaming(events),
        ).doStream(_options())).stream.toList();
        expect(errors.whereType<StreamPartError>(), hasLength(1));
      }
    },
  );
}

OpenAIResponsesLanguageModel _model(HttpClientAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return OpenAIResponsesLanguageModel(
    modelId: 'gpt-test',
    client: dio,
    headers: () async => const {},
    baseUrl: 'https://api.openai.test/v1/responses',
  );
}

LanguageModelV4CallOptions _options() => const LanguageModelV4CallOptions(
  prompt: LanguageModelV4Prompt(messages: []),
);

class _Adapter implements HttpClientAdapter {
  _Adapter(this._response);

  factory _Adapter.generate() => _Adapter(
    (_) => jsonEncode({'id': 'r1', 'status': 'completed', 'output': []}),
  );

  factory _Adapter.streaming(List<Map<String, dynamic>> events) => _Adapter(
    (_) => events.map((event) => 'data: ${jsonEncode(event)}\n\n').join(),
  );

  final String Function(RequestOptions request) _response;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = _response(options);
    final streaming = (options.data as Map)['stream'] == true;
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [
          streaming ? 'text/event-stream' : Headers.jsonContentType,
        ],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _NullStreamBodyInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.resolve(
      Response<dynamic>(requestOptions: options, statusCode: 200),
    );
  }
}
