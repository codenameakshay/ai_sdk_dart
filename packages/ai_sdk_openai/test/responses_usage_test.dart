import 'dart:convert';

import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

import 'support/fake_adapter.dart';

void main() {
  for (final streaming in [false, true]) {
    test(
      '${streaming ? 'stream' : 'generate'} maps Responses cached and text usage',
      () async {
        final usage = await _run(
          streaming: streaming,
          usage: {
            'input_tokens': 100,
            'input_tokens_details': {'cached_tokens': 80},
            'output_tokens': 30,
            'output_tokens_details': {'reasoning_tokens': 20},
          },
        );

        expect(usage.inputTokens.total, 100);
        expect(usage.inputTokens.cacheRead, 80);
        expect(usage.inputTokens.noCache, 20);
        expect(usage.outputTokens.total, 30);
        expect(usage.outputTokens.reasoning, 20);
        expect(usage.outputTokens.text, 10);
      },
    );

    test(
      '${streaming ? 'stream' : 'generate'} preserves unknown usage breakdowns',
      () async {
        final absent = await _run(
          streaming: streaming,
          usage: {'input_tokens': 100, 'output_tokens': 30},
        );
        expect(absent.inputTokens.total, 100);
        expect(absent.inputTokens.cacheRead, isNull);
        expect(absent.inputTokens.noCache, isNull);
        expect(absent.outputTokens.total, 30);
        expect(absent.outputTokens.reasoning, isNull);
        expect(absent.outputTokens.text, isNull);

        final partial = await _run(
          streaming: streaming,
          usage: {
            'input_tokens_details': {'cached_tokens': 80},
            'output_tokens_details': {'reasoning_tokens': 20},
          },
        );
        expect(partial.inputTokens.total, isNull);
        expect(partial.inputTokens.cacheRead, 80);
        expect(partial.inputTokens.noCache, isNull);
        expect(partial.outputTokens.total, isNull);
        expect(partial.outputTokens.reasoning, 20);
        expect(partial.outputTokens.text, isNull);
      },
    );
  }
}

Future<LanguageModelV4Usage> _run({
  required bool streaming,
  required Map<String, dynamic> usage,
}) async {
  final client = Dio(BaseOptions(baseUrl: 'https://api.openai.test/v1'))
    ..httpClientAdapter = FakeHttpAdapter((request) async {
      final response = {
        'id': 'resp_usage',
        'model': 'gpt-5',
        'status': 'completed',
        'output': [],
        'usage': usage,
      };
      if (streaming) {
        return ResponseBody.fromString(
          'data: ${jsonEncode({'type': 'response.completed', 'response': response})}\n\n',
          200,
          headers: {
            'content-type': ['text/event-stream'],
          },
        );
      }
      return ResponseBody.fromString(
        jsonEncode(response),
        200,
        headers: {
          'content-type': ['application/json'],
        },
      );
    });
  addTearDown(() => client.close(force: true));
  final model = OpenAIProvider(
    apiKey: 'test',
    client: client,
  ).responses('gpt-5');
  const options = LanguageModelV4CallOptions(
    prompt: LanguageModelV4Prompt(messages: []),
  );
  if (!streaming) {
    return (await model.doGenerate(options)).usage;
  }
  final result = await model.doStream(options);
  return (await result.stream.toList())
      .whereType<StreamPartFinish>()
      .single
      .usage;
}
