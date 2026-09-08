import 'dart:io';

import 'package:ai_sdk_groq/ai_sdk_groq.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

import '../../ai_sdk_provider/test/support/http_helpers.dart';
import '../../ai_sdk_provider/test/support/prompts.dart';
import '../../ai_sdk_provider/test/support/test_server.dart';
import '../../ai_sdk_provider/test/support/tracking_http_client_adapter.dart';

void main() {
  group('GroqProvider', () {
    test('creates language model with correct provider/spec/modelId', () {
      final provider = GroqProvider(apiKey: 'test-key');
      final model = provider('llama3-8b-8192');
      expect(model.provider, 'groq');
      expect(model.modelId, 'llama3-8b-8192');
      expect(model.specificationVersion, 'v4');
    });

    test('credentials are resolved immediately before each request', () async {
      final authorizations = <String?>[];
      final server = await _startServer((request) async {
        authorizations.add(request.headers.value('authorization'));
        writeOk(request);
      });
      addTearDown(server.close);

      var token = 'first-token';
      final provider = GroqProvider(
        baseUrl: server.baseUrl,
        credentialProvider: () async => token,
      );

      await provider(
        'llama3-8b-8192',
      ).doGenerate(LanguageModelV4CallOptions(prompt: userPrompt('first')));
      token = 'second-token';
      await provider(
        'llama3-8b-8192',
      ).doGenerate(LanguageModelV4CallOptions(prompt: userPrompt('second')));

      expect(authorizations, ['Bearer first-token', 'Bearer second-token']);
    });

    test(
      'dispose closes owned clients and leaves injected clients open',
      () async {
        final server = await _startServer((request) async {
          writeOk(request);
        });
        addTearDown(server.close);

        final ownedProvider = GroqProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        );
        ownedProvider.dispose();
        await expectLater(
          ownedProvider('llama3-8b-8192').doGenerate(
            LanguageModelV4CallOptions(prompt: userPrompt('after-dispose')),
          ),
          throwsA(anything),
        );

        final client = Dio(BaseOptions(baseUrl: server.baseUrl));
        final adapter = attachTrackingAdapter(client);
        final injectedProvider = GroqProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
          client: client,
        );

        injectedProvider.dispose(force: false);
        await injectedProvider('llama3-8b-8192').doGenerate(
          LanguageModelV4CallOptions(prompt: userPrompt('still-open')),
        );

        expect(adapter.closeCount, 0);
        client.close(force: true);
        expect(adapter.closeCount, 1);
        expect(adapter.lastForce, true);
      },
    );
  });

  group('OpenAI-compatible capabilities (via shared base)', () {
    test('serializes tools and tool_choice', () async {
      late Map<String, dynamic> captured;
      final server = await _startServer((request) async {
        captured = await captureBody(request);
        writeOk(request);
      });
      addTearDown(server.close);

      final model = GroqProvider(apiKey: 'key', baseUrl: server.baseUrl)(
        'llama3-groq-70b-8192-tool-use-preview',
      );
      await model.doGenerate(
        LanguageModelV4CallOptions(
          prompt: userPrompt('weather in Tokyo'),
          tools: const [
            LanguageModelV4FunctionTool(
              name: 'weather',
              inputSchema: {'type': 'object'},
            ),
          ],
          toolChoice: const ToolChoiceRequired(),
        ),
      );

      final tools = (captured['tools'] as List).cast<Map<String, dynamic>>();
      expect((tools.single['function'] as Map)['name'], 'weather');
      expect(captured['tool_choice'], 'required');
    });

    test('serializes multimodal image content part', () async {
      late Map<String, dynamic> captured;
      final server = await _startServer((request) async {
        captured = await captureBody(request);
        writeOk(request);
      });
      addTearDown(server.close);

      final model = GroqProvider(apiKey: 'key', baseUrl: server.baseUrl)(
        'llama-3.2-90b-vision-preview',
      );
      await model.doGenerate(LanguageModelV4CallOptions(prompt: imagePrompt()));

      final messages = (captured['messages'] as List)
          .cast<Map<String, dynamic>>();
      final content = (messages.first['content'] as List)
          .cast<Map<String, dynamic>>();
      expect(content[0]['type'], 'text');
      expect(content[1]['type'], 'image_url');
    });

    test('uses max_tokens (not max_completion_tokens)', () async {
      late Map<String, dynamic> captured;
      final server = await _startServer((request) async {
        captured = await captureBody(request);
        writeOk(request);
      });
      addTearDown(server.close);

      final model = GroqProvider(apiKey: 'key', baseUrl: server.baseUrl)(
        'llama3-8b-8192',
      );
      await model.doGenerate(
        LanguageModelV4CallOptions(
          prompt: userPrompt('hi'),
          maxOutputTokens: 256,
        ),
      );
      expect(captured['max_tokens'], 256);
      expect(captured.containsKey('max_completion_tokens'), isFalse);
    });
  });
}

Future<TestServer> _startServer(
  Future<void> Function(HttpRequest request) handler,
) => TestServer.start(handler, pathSuffix: '/v1');
