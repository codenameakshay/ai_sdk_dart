import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_anthropic/ai_sdk_anthropic.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import '../../ai_sdk_provider/test/support/prompts.dart';

void main() {
  test(
    'portable legacy reasoning budget stays below default max_tokens',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final captured = <Map<String, dynamic>>[];
      server.listen((request) async {
        final body =
            (jsonDecode(await utf8.decoder.bind(request).join()) as Map)
                .cast<String, dynamic>();
        captured.add(body);
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'content': []}));
        await request.response.close();
      });

      final model = AnthropicProvider(
        apiKey: 'test',
        baseUrl: 'http://${server.address.address}:${server.port}',
      ).call('claude-3-7-sonnet-20250219');
      for (final reasoning in [
        LanguageModelV4Reasoning.minimal,
        LanguageModelV4Reasoning.low,
        LanguageModelV4Reasoning.medium,
        LanguageModelV4Reasoning.high,
        LanguageModelV4Reasoning.xhigh,
      ]) {
        await model.doGenerate(
          LanguageModelV4CallOptions(
            prompt: const LanguageModelV4Prompt(messages: []),
            reasoning: reasoning,
          ),
        );
      }

      for (final body in captured) {
        final thinking = body['thinking'] as Map;
        expect(thinking['budget_tokens'], lessThan(body['max_tokens'] as int));
      }
    },
  );

  test(
    'streaming legacy reasoning also exceeds the default max_tokens',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final captured = Completer<Map<String, dynamic>>();
      server.listen((request) async {
        final body =
            (jsonDecode(await utf8.decoder.bind(request).join()) as Map)
                .cast<String, dynamic>();
        captured.complete(body);
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'content': []}));
        await request.response.close();
      });

      final model = AnthropicProvider(
        apiKey: 'test',
        baseUrl: 'http://${server.address.address}:${server.port}',
      ).call('claude-3-7-sonnet-20250219');
      final result = await model.doStream(
        LanguageModelV4CallOptions(
          prompt: const LanguageModelV4Prompt(messages: []),
          reasoning: LanguageModelV4Reasoning.minimal,
        ),
      );
      await result.stream.toList();
      final body = await captured.future;

      expect(
        (body['thinking'] as Map)['budget_tokens'],
        lessThan(body['max_tokens'] as int),
      );
    },
  );

  test(
    'explicit thinking budgets are retained and get a compatible default',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final captured = <Map<String, dynamic>>[];
      server.listen((request) async {
        captured.add(
          (jsonDecode(await utf8.decoder.bind(request).join()) as Map)
              .cast<String, dynamic>(),
        );
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'content': []}));
        await request.response.close();
      });
      final model = AnthropicProvider(
        apiKey: 'test',
        baseUrl: 'http://${server.address.address}:${server.port}',
      ).call('claude-3-7-sonnet-20250219');

      for (final budget in [1024, 10000]) {
        await model.doGenerate(
          LanguageModelV4CallOptions(
            prompt: userPrompt('budget $budget'),
            providerOptions: {
              'anthropic': AnthropicThinkingOptions(
                budgetTokens: budget,
              ).toMap(),
            },
          ),
        );
      }
      await model.doGenerate(
        LanguageModelV4CallOptions(
          prompt: userPrompt('preserved max'),
          maxOutputTokens: 3072,
          providerOptions: {
            'anthropic': const AnthropicThinkingOptions(
              budgetTokens: 1024,
            ).toMap(),
          },
        ),
      );
      expect(
        captured.map((body) => (body['thinking'] as Map)['budget_tokens']),
        [1024, 10000, 1024],
      );
      expect(captured.map((body) => body['max_tokens']), [2048, 11024, 3072]);
    },
  );

  test(
    'explicit thinking budget equal to explicit max is rejected before dispatch',
    () async {
      var dispatched = false;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        dispatched = true;
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
      });
      final model = AnthropicProvider(
        apiKey: 'test',
        baseUrl: 'http://${server.address.address}:${server.port}',
      ).call('claude-3-7-sonnet-20250219');

      await expectLater(
        model.doGenerate(
          LanguageModelV4CallOptions(
            prompt: userPrompt('budget boundary'),
            maxOutputTokens: 1024,
            providerOptions: {
              'anthropic': const AnthropicThinkingOptions(
                budgetTokens: 1024,
              ).toMap(),
            },
          ),
        ),
        throwsArgumentError,
      );
      expect(dispatched, isFalse);
    },
  );

  for (final budget in ['1024', 1024.0, 0, 1023]) {
    for (final streaming in [false, true]) {
      test(
        '${streaming ? 'streaming' : 'generation'} rejects invalid explicit thinking budget $budget before dispatch and detaches cancellation listener',
        () async {
          var dispatched = false;
          final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          addTearDown(server.close);
          server.listen((request) async {
            dispatched = true;
            request.response.statusCode = HttpStatus.ok;
            await request.response.close();
          });
          final signal = _ObservableSignal();
          addTearDown(signal.events.close);
          final model = AnthropicProvider(
            apiKey: 'test',
            baseUrl: 'http://${server.address.address}:${server.port}',
          ).call('claude-3-7-sonnet-20250219');
          final options = LanguageModelV4CallOptions(
            abortSignal: signal,
            prompt: userPrompt('invalid budget $budget'),
            providerOptions: {
              'anthropic': {
                'thinking': {'type': 'enabled', 'budget_tokens': budget},
              },
            },
          );

          await expectLater(
            streaming ? model.doStream(options) : model.doGenerate(options),
            throwsArgumentError,
          );
          expect(dispatched, isFalse);
          expect(signal.active, 0);
        },
      );
    }
  }
}

class _ObservableSignal implements ObservableAbortSignal {
  final events = StreamController<void>.broadcast();
  final _cancelled = Completer<void>();
  int active = 0;

  @override
  bool get isCancelled => false;

  @override
  Future<void> get onCancelled => _cancelled.future;

  @override
  Stream<void> get cancellationEvents => Stream.multi((controller) {
    active++;
    final subscription = events.stream.listen(controller.addSync);
    controller.onCancel = () async {
      active--;
      await subscription.cancel();
    };
  });
}
