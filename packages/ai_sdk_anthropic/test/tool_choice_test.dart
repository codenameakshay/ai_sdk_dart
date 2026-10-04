import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_sdk_anthropic/ai_sdk_anthropic.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  for (final streaming in [false, true]) {
    test(
      '${streaming ? 'streaming' : 'generation'} disables tool use when choice is none',
      () async {
        final adapter = _Adapter();
        final client = Dio()..httpClientAdapter = adapter;
        addTearDown(() => client.close(force: true));
        final model = AnthropicProvider(client: client).call('claude-test');
        const options = LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(messages: []),
          tools: [
            LanguageModelV4FunctionTool(
              name: 'lookup',
              inputSchema: {'type': 'object'},
            ),
          ],
          toolChoice: ToolChoiceNone(),
        );
        if (streaming) {
          final result = await model.doStream(options);
          await result.stream.drain<void>();
        } else {
          await model.doGenerate(options);
        }
        expect(adapter.body['tool_choice'], {'type': 'none'});
      },
    );
  }
}

class _Adapter implements HttpClientAdapter {
  late Map<String, dynamic> body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    body = (options.data as Map).cast<String, dynamic>();
    return ResponseBody.fromString(
      body['stream'] == true
          ? ''
          : jsonEncode({'content': [], 'stop_reason': 'end_turn'}),
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
