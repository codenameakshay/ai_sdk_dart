import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_google/ai_sdk_google.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import '../../ai_sdk_provider/test/support/prompts.dart';
import '../../ai_sdk_provider/test/support/test_server.dart';

const _blocked = {
  'promptFeedback': {'blockReason': 'SAFETY'},
};

void main() {
  test(
    'maps prompt-level safety blocks in generation to content-filter',
    () async {
      final server = await TestServer.start((request) async {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(_blocked));
        await request.response.close();
      }, pathSuffix: '/v1beta');
      addTearDown(server.close);

      final generated =
          await GoogleGenerativeAIProvider(
                apiKey: 'test',
                baseUrl: server.baseUrl,
              )
              .call('gemini-2.0-flash')
              .doGenerate(
                LanguageModelV4CallOptions(
                  prompt: userPrompt('blocked prompt'),
                ),
              );
      expect(generated.finishReason, LanguageModelV4FinishReason.contentFilter);
      expect(generated.rawFinishReason, 'SAFETY');
    },
  );

  test('known prompt block reasons map to content-filter', () async {
    var reason = '';
    final server = await TestServer.start((request) async {
      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'promptFeedback': {'blockReason': reason},
        }),
      );
      await request.response.close();
    }, pathSuffix: '/v1beta');
    addTearDown(server.close);
    final model = GoogleGenerativeAIProvider(
      apiKey: 'test',
      baseUrl: server.baseUrl,
    ).call('gemini-2.0-flash');

    for (final blockReason in [
      'SAFETY',
      'BLOCKLIST',
      'PROHIBITED_CONTENT',
      'IMAGE_SAFETY',
    ]) {
      reason = blockReason;
      final generated = await model.doGenerate(
        LanguageModelV4CallOptions(prompt: userPrompt('blocked')),
      );
      expect(generated.finishReason, LanguageModelV4FinishReason.contentFilter);
      expect(generated.rawFinishReason, blockReason);
    }
  });

  test('emits a content-filter finish for an empty blocked stream', () async {
    final server = await TestServer.start((request) async {
      request.response.statusCode = 200;
      request.response.headers.set('content-type', 'text/event-stream');
      request.response.write('data: ${jsonEncode(_blocked)}\n\n');
      await request.response.close();
    }, pathSuffix: '/v1beta');
    addTearDown(server.close);

    final streamed =
        await GoogleGenerativeAIProvider(
              apiKey: 'test',
              baseUrl: server.baseUrl,
            )
            .call('gemini-2.0-flash')
            .doStream(
              LanguageModelV4CallOptions(prompt: userPrompt('blocked prompt')),
            );
    final parts = await streamed.stream.toList();
    expect(parts.whereType<StreamPartError>(), isEmpty);
    final finish = parts.whereType<StreamPartFinish>().single;
    expect(finish.finishReason, LanguageModelV4FinishReason.contentFilter);
    expect(finish.rawFinishReason, 'SAFETY');
  });

  test('empty response body emits one start and a truncation error', () async {
    final server = await TestServer.start((request) async {
      request.response.statusCode = 200;
      request.response.headers.set('content-type', 'text/event-stream');
      await request.response.close();
    }, pathSuffix: '/v1beta');
    addTearDown(server.close);

    final streamed =
        await GoogleGenerativeAIProvider(
              apiKey: 'test',
              baseUrl: server.baseUrl,
            )
            .call('gemini-2.0-flash')
            .doStream(
              LanguageModelV4CallOptions(prompt: userPrompt('empty response')),
            );
    final parts = await streamed.stream.toList();
    expect(parts.whereType<StreamPartStreamStart>(), hasLength(1));
    expect(parts.whereType<StreamPartError>(), hasLength(1));
    expect(parts.whereType<StreamPartFinish>(), isEmpty);
  });

  test('candidate finish without content remains a valid empty finish', () async {
    final server = await TestServer.start((request) async {
      request.response.statusCode = 200;
      request.response.headers.set('content-type', 'text/event-stream');
      request.response.write(
        'data: {"candidates":[{"content":{"parts":[]},"finishReason":"STOP"}]}\n\n',
      );
      await request.response.close();
    }, pathSuffix: '/v1beta');
    addTearDown(server.close);

    final streamed =
        await GoogleGenerativeAIProvider(
              apiKey: 'test',
              baseUrl: server.baseUrl,
            )
            .call('gemini-2.0-flash')
            .doStream(
              LanguageModelV4CallOptions(prompt: userPrompt('empty terminal')),
            );
    final parts = await streamed.stream.toList();
    expect(parts.whereType<StreamPartStreamStart>(), hasLength(1));
    expect(parts.whereType<StreamPartError>(), isEmpty);
    expect(parts.whereType<StreamPartFinish>(), hasLength(1));
  });
}
