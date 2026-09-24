import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  test(
    'terminal Responses events preserve raw chunks and finish reasons',
    () async {
      for (final (event, reason) in <(Map<String, dynamic>, Object)>[
        (
          {
            'type': 'response.incomplete',
            'response': {
              'id': 'incomplete',
              'model': 'gpt-test',
              'status': 'incomplete',
              'incomplete_details': {'reason': 'content_filter'},
            },
          },
          LanguageModelV4FinishReason.contentFilter,
        ),
        (
          {
            'type': 'response.failed',
            'response': {
              'id': 'failed',
              'status': 'failed',
              'error': {'code': 'server_error', 'message': 'failed'},
            },
          },
          LanguageModelV4FinishReason.error,
        ),
      ]) {
        final result = await _model(
          _streamAdapter([event]),
        ).doStream(_options(includeRawChunks: true));
        final parts = await result.stream.toList();
        expect(parts.whereType<StreamPartRaw>(), hasLength(1));
        expect(parts.whereType<StreamPartFinish>().single.finishReason, reason);
        if (event['type'] == 'response.failed') {
          expect(parts.whereType<StreamPartError>(), hasLength(1));
        }
      }
    },
  );

  test(
    'stream reports protocol failures and preserves valid hosted media',
    () async {
      final adapter = _streamAdapter([
        {
          'type': 'response.output_item.added',
          'item': {
            'type': 'function_call',
            'id': 'fn1',
            'call_id': 'call1',
            'name': 'lookup',
          },
        },
        {
          'type': 'response.output_item.added',
          'item': {
            'type': 'function_call',
            'id': 'fn1',
            'call_id': 'changed',
            'name': 'lookup',
          },
        },
      ]);
      final parts = await (await _model(
        adapter,
      ).doStream(_options())).stream.toList();
      expect(parts.whereType<StreamPartError>(), hasLength(1));
      expect(parts.whereType<StreamPartFinish>(), isEmpty);

      final hosted = await (await _model(
        _streamAdapter([
          {
            'type': 'response.output_item.done',
            'item': {
              'type': 'mcp_call',
              'id': 'hosted1',
              'name': 'search',
              'server_label': 'docs',
              'arguments': '{}',
              'output': {'ok': true},
            },
          },
        ]),
      ).doStream(_options())).stream.toList();
      expect(
        hosted.whereType<StreamPartToolCall>().map(
          (part) => part.toolCall.toolName,
        ),
        contains('mcp.search'),
      );
      expect(hosted.whereType<StreamPartToolResult>(), hasLength(1));
    },
  );

  test(
    'generate maps MCP approval requests and hosted search results',
    () async {
      final adapter = _generateAdapter({
        'id': 'r1',
        'status': 'completed',
        'output': [
          {
            'type': 'mcp_approval_request',
            'id': 'approval-item',
            'approval_request_id': 'approval1',
            'name': 'search',
          },
          {
            'type': 'web_search_call',
            'id': 'search-item',
            'approval_request_id': 'approval1',
            'status': 'completed',
            'action': {
              'sources': [
                {'url': 'https://example.test', 'title': 'Example'},
              ],
            },
          },
        ],
      });
      final result = await _model(adapter).doGenerate(_options());
      expect(
        result.content.whereType<LanguageModelV4ToolApprovalRequestPart>(),
        hasLength(1),
      );
      expect(
        result.content.whereType<LanguageModelV4ToolCallPart>().last.toolCallId,
        'approval-item',
      );
      expect(
        result.content.whereType<LanguageModelV4SourcePart>().single.url,
        'https://example.test',
      );
    },
  );

  test(
    'stream maps terminal annotations and function-call completion',
    () async {
      final result = await _model(
        _streamAdapter([
          {
            'type': 'response.output_text.annotation.added',
            'annotation': {'type': 'file_citation', 'file_id': 'file1'},
          },
          {
            'type': 'response.reasoning_summary_text.delta',
            'item_id': 'reason1',
            'delta': 'thinking',
          },
          {
            'type': 'response.output_item.done',
            'output_index': 1,
            'item': {'type': 'message', 'id': 'message1'},
          },
          {
            'type': 'response.output_item.done',
            'item': {
              'type': 'function_call',
              'id': 'function1',
              'call_id': 'call1',
              'name': 'lookup',
              'arguments': '{"ok":true}',
            },
          },
          {
            'type': 'response.output_item.done',
            'item': {
              'type': 'reasoning',
              'id': 'reason1',
              'encrypted_content': 'encrypted',
            },
          },
          {
            'type': 'response.completed',
            'response': {'id': 'r1'},
          },
        ]),
      ).doStream(_options());
      final parts = await result.stream.toList();
      expect(parts.whereType<StreamPartDocumentSource>(), hasLength(1));
      expect(
        parts.whereType<StreamPartReasoningDelta>().single.delta,
        'thinking',
      );
      expect(parts.whereType<StreamPartTextEnd>().single.id, 'message1');
      expect(parts.whereType<StreamPartToolCall>().single.toolCall.input, {
        'ok': true,
      });
      expect(parts.whereType<StreamPartReasoningEnd>(), hasLength(1));
      expect(
        parts.whereType<StreamPartFinish>().single.finishReason,
        LanguageModelV4FinishReason.stop,
      );
    },
  );

  test(
    'tool output content serializes text and rejects unsupported parts',
    () async {
      final adapter = _generateAdapter({
        'id': 'r1',
        'status': 'completed',
        'output': [],
      });
      final prompt = LanguageModelV4Prompt(
        messages: [
          LanguageModelV4Message(
            role: LanguageModelV4Role.tool,
            content: [
              const LanguageModelV4ToolResultPart(
                toolCallId: 'call1',
                toolName: 'lookup',
                output: ToolResultOutputContent([
                  LanguageModelV4TextPart(text: 'result'),
                ]),
              ),
            ],
          ),
        ],
      );
      await _model(
        adapter,
      ).doGenerate(LanguageModelV4CallOptions(prompt: prompt));
      expect(jsonDecode((adapter as _Adapter).lastBody), isA<Map>());

      final invalidPrompt = LanguageModelV4Prompt(
        messages: [
          LanguageModelV4Message(
            role: LanguageModelV4Role.tool,
            content: [
              const LanguageModelV4ToolResultPart(
                toolCallId: 'call2',
                toolName: 'lookup',
                output: ToolResultOutputContent([
                  LanguageModelV4ReasoningPart(text: 'hidden'),
                ]),
              ),
            ],
          ),
        ],
      );
      await expectLater(
        _model(
          _generateAdapter({'id': 'r1', 'status': 'completed', 'output': []}),
        ).doGenerate(LanguageModelV4CallOptions(prompt: invalidPrompt)),
        throwsA(isA<UnsupportedError>()),
      );
    },
  );
}

LanguageModelV4 _model(HttpClientAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return OpenAIProvider(apiKey: 'fixture', client: dio).responses('gpt-test');
}

LanguageModelV4CallOptions _options({bool includeRawChunks = false}) =>
    LanguageModelV4CallOptions(
      prompt: const LanguageModelV4Prompt(messages: []),
      includeRawChunks: includeRawChunks,
    );

HttpClientAdapter _streamAdapter(List<Map<String, dynamic>> events) => _Adapter(
  (_) => events.map((event) => 'data: ${jsonEncode(event)}\n\n').join(),
  streaming: true,
);

HttpClientAdapter _generateAdapter(Map<String, dynamic> response) =>
    _Adapter((_) => jsonEncode(response));

class _Adapter implements HttpClientAdapter {
  _Adapter(this.body, {this.streaming = false});
  final String Function(RequestOptions) body;
  final bool streaming;
  String lastBody = '';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastBody = body(options);
    return ResponseBody.fromString(
      lastBody,
      200,
      headers: {
        'content-type': [streaming ? 'text/event-stream' : 'application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
